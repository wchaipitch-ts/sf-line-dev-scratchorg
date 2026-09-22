/**
 * LWC API for reps (02 §2). Everything a rep can reach goes through here.
 *
 * `with sharing` and user-mode checks: the rep must be able to see the conversation (OWD Private, owner = the OA's rep)
 * and to create messages, before any callout is made. Errors reach the LWC as `AuraHandledException` carrying a
 * Custom Label message; LINE's own message is passed through where it helps the rep (e.g. the monthly limit).
 *
 * Reads are paged with keyset pagination on (`Sent_At__c`, `Id`) and never use OFFSET (D12), so a conversation with
 * a million messages pages as fast as a new one.
 *
 * M4: sending text. M5: conversation and message reads, polling, mark-as-read.
 */
public with sharing class LineChatController {
  @TestVisible
  static final Integer DEFAULT_PAGE_SIZE = 30;
  @TestVisible
  static final Integer MAX_PAGE_SIZE = 100;
  // A poll returns only what arrived since the last one; this cap is a safety net, not a normal case.
  @TestVisible
  static final Integer MAX_NEW_MESSAGES = 200;
  // The last error turned into a generic message, so tests can show what really happened.
  @TestVisible
  static Exception lastUnexpectedError;

  /** One message, as shown in the chat panel. Never contains secrets. */
  public class MessageView {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String direction;
    @AuraEnabled
    public Boolean isOutbound;
    @AuraEnabled
    public String messageType;
    @AuraEnabled
    public String text;
    @AuraEnabled
    public Datetime sentAt;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String errorMessage;
    @AuraEnabled
    public Id senderId;
    @AuraEnabled
    public String senderName;
    @AuraEnabled
    public String fileName;
    @AuraEnabled
    public Decimal fileSize;
    @AuraEnabled
    public String publicUrl;
    @AuraEnabled
    public String contentDocumentId;
    @AuraEnabled
    public String stickerPackageId;
    @AuraEnabled
    public String stickerId;
    @AuraEnabled
    public String location;

    private MessageView(LINE_Message__c m) {
      this.id = m.Id;
      this.direction = m.Direction__c;
      this.isOutbound = m.Direction__c == 'Outbound';
      this.messageType = m.Message_Type__c;
      this.text = m.Text__c;
      this.sentAt = m.Sent_At__c;
      this.status = m.Status__c;
      this.errorMessage = m.Error__c;
      this.senderId = m.Sender__c;
      this.senderName = m.Sender__r?.Name;
      this.fileName = m.File_Name__c;
      this.fileSize = m.File_Size__c;
      this.publicUrl = m.Public_Url__c;
      this.contentDocumentId = m.Content_Document_Id__c;
      this.stickerPackageId = m.Sticker_Package_Id__c;
      this.stickerId = m.Sticker_Id__c;
      this.location = m.Location__c;
    }
  }

  /** One conversation of a Contact, for the chat panel's OA selector. */
  public class ConversationView {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String pictureUrl;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Decimal unreadCount;
    @AuraEnabled
    public Datetime lastMessageAt;
    @AuraEnabled
    public Id oaConfigurationId;
    @AuraEnabled
    public String oaName;
    @AuraEnabled
    public Boolean isPrimaryOa;

    private ConversationView(LINE_Conversation__c c, Id primaryOaId) {
      this.id = c.Id;
      this.name = c.Name;
      this.pictureUrl = c.Picture_Url__c;
      this.status = c.Status__c;
      this.unreadCount = c.Unread_Count__c == null ? 0 : c.Unread_Count__c;
      this.lastMessageAt = c.Last_Message_At__c;
      this.oaConfigurationId = c.LINE_OA_Configuration__c;
      this.oaName = c.LINE_OA_Configuration__r?.Name;
      this.isPrimaryOa =
        primaryOaId != null &&
        primaryOaId == c.LINE_OA_Configuration__c;
    }
  }

  /** One page of messages, oldest first. */
  public class MessagePage {
    @AuraEnabled
    public List<MessageView> messages = new List<MessageView>();
    /** True when older messages exist before this page. */
    @AuraEnabled
    public Boolean hasMore = false;
  }

  /**
   * Conversations of a Contact that the running user can see, the Contact's primary OA first, then most recent.
   *
   * @param contactId the Contact whose chat panel is open
   * @return the conversations, or an empty list when the Contact has none the user can see
   */
  @AuraEnabled
  public static List<ConversationView> getConversations(Id contactId) {
    try {
      if (contactId == null) {
        return new List<ConversationView>();
      }
      Id primaryOaId = primaryOaOf(contactId);
      List<ConversationView> result = new List<ConversationView>();
      for (LINE_Conversation__c c : [
        SELECT
          Id,
          Name,
          Picture_Url__c,
          Status__c,
          Unread_Count__c,
          Last_Message_At__c,
          LINE_OA_Configuration__c,
          LINE_OA_Configuration__r.Name
        FROM LINE_Conversation__c
        WHERE Contact__c = :contactId
        WITH USER_MODE
        ORDER BY Last_Message_At__c DESC NULLS LAST, Name
        LIMIT 50
      ]) {
        result.add(new ConversationView(c, primaryOaId));
      }
      // The Contact's primary OA opens first (03 §2); the rest keep their most-recent-first order.
      for (Integer i = 1; i < result.size(); i++) {
        if (result[i].isPrimaryOa) {
          List<ConversationView> reordered = new List<ConversationView>{
            result.remove(i)
          };
          reordered.addAll(result);
          return reordered;
        }
      }
      return result;
    } catch (Exception e) {
      throw handled(e, 'getConversations', contactId);
    }
  }

  /**
   * One page of older messages, oldest first. Pass the oldest message you already have to get the page before it.
   *
   * @param conversationId the open conversation
   * @param beforeSentAt `sentAt` of the oldest message held, or null for the newest page
   * @param beforeId Id of that same message, which breaks ties on equal timestamps
   * @param pageSize how many to return (default 30, maximum 100)
   * @return the page, plus whether older messages remain
   */
  @AuraEnabled
  public static MessagePage getMessages(
    Id conversationId,
    Datetime beforeSentAt,
    Id beforeId,
    Integer pageSize
  ) {
    try {
      assertCanRead(conversationId);
      Integer size = pageSize == null ||
        pageSize <= 0
        ? DEFAULT_PAGE_SIZE
        : Math.min(pageSize, MAX_PAGE_SIZE);
      // One extra row tells us whether an older page exists, without a COUNT().
      Integer queryLimit = size + 1;
      Datetime before = beforeSentAt == null
        ? Datetime.newInstance(4000, 1, 1)
        : beforeSentAt;
      Id beforeRecordId = beforeId == null
        ? (Id) '000000000000000AAA'
        : beforeId;

      List<LINE_Message__c> rows = [
        SELECT
          Id,
          Direction__c,
          Message_Type__c,
          Text__c,
          Sent_At__c,
          Status__c,
          Error__c,
          Sender__c,
          Sender__r.Name,
          File_Name__c,
          File_Size__c,
          Public_Url__c,
          Content_Document_Id__c,
          Sticker_Package_Id__c,
          Sticker_Id__c,
          Location__c
        FROM LINE_Message__c
        WHERE
          LINE_Conversation__c = :conversationId
          AND (Sent_At__c < :before
          OR (Sent_At__c = :before
          AND Id < :beforeRecordId))
        WITH USER_MODE
        ORDER BY Sent_At__c DESC, Id DESC
        LIMIT :queryLimit
      ];

      MessagePage page = new MessagePage();
      page.hasMore = rows.size() > size;
      if (page.hasMore) {
        rows.remove(rows.size() - 1);
      }
      // Queried newest first for the LIMIT; the panel wants oldest first.
      for (Integer i = rows.size() - 1; i >= 0; i--) {
        page.messages.add(new MessageView(rows[i]));
      }
      return page;
    } catch (Exception e) {
      throw handled(e, 'getMessages', conversationId);
    }
  }

  /**
   * Messages that arrived after the newest one the panel holds. Used by polling (D7).
   *
   * @param conversationId the open conversation
   * @param afterSentAt `sentAt` of the newest message held
   * @param afterId Id of that same message
   * @return the new messages, oldest first
   */
  @AuraEnabled
  public static List<MessageView> getMessagesSince(
    Id conversationId,
    Datetime afterSentAt,
    Id afterId
  ) {
    try {
      assertCanRead(conversationId);
      Datetime after = afterSentAt == null
        ? Datetime.newInstance(1970, 1, 1)
        : afterSentAt;
      Id afterRecordId = afterId == null ? (Id) '000000000000000AAA' : afterId;

      List<MessageView> result = new List<MessageView>();
      for (LINE_Message__c m : [
        SELECT
          Id,
          Direction__c,
          Message_Type__c,
          Text__c,
          Sent_At__c,
          Status__c,
          Error__c,
          Sender__c,
          Sender__r.Name,
          File_Name__c,
          File_Size__c,
          Public_Url__c,
          Content_Document_Id__c,
          Sticker_Package_Id__c,
          Sticker_Id__c,
          Location__c
        FROM LINE_Message__c
        WHERE
          LINE_Conversation__c = :conversationId
          AND (Sent_At__c > :after
          OR (Sent_At__c = :after
          AND Id > :afterRecordId))
        WITH USER_MODE
        ORDER BY Sent_At__c ASC, Id ASC
        LIMIT :MAX_NEW_MESSAGES
      ]) {
        result.add(new MessageView(m));
      }
      return result;
    } catch (Exception e) {
      throw handled(e, 'getMessagesSince', conversationId);
    }
  }

  /**
   * Clears the unread count of a conversation the rep is reading.
   *
   * @param conversationId the open conversation
   * @return the conversation's unread count afterwards (0)
   */
  @AuraEnabled
  public static Decimal markRead(Id conversationId) {
    try {
      assertCanRead(conversationId);
      update as user new LINE_Conversation__c(
        Id = conversationId,
        Unread_Count__c = 0
      );
      return 0;
    } catch (Exception e) {
      throw handled(e, 'markRead', conversationId);
    }
  }

  /**
   * @return how often the panel should poll, in seconds (`LINE_Settings__c`, default 5)
   */
  @AuraEnabled(cacheable=true)
  public static Integer getPollIntervalSeconds() {
    return LineSettings.pollIntervalSeconds();
  }

  /**
   * Sends a text message to the customer of a conversation, through that conversation's OA.
   *
   * @param conversationId the conversation the rep has open
   * @param text 1–5,000 characters
   * @return the stored message
   * @throws AuraHandledException if the rep can't access the conversation, the text is invalid, or LINE refuses
   */
  @AuraEnabled
  public static MessageView sendText(Id conversationId, String text) {
    try {
      assertCanSend(conversationId);
      return new MessageView(
        LineOutboundService.sendText(conversationId, text)
      );
    } catch (Exception e) {
      // LINE's own wording is the most useful thing for the rep (monthly limit, text too long, …).
      throw handled(e, 'sendText', conversationId);
    }
  }

  // The rep must see the conversation (sharing) and be able to create messages (object/field access), in user mode.
  private static void assertCanSend(Id conversationId) {
    if (conversationId == null) {
      throw asAuraException(System.Label.LINE_Error_No_Access);
    }
    List<LINE_Conversation__c> conversations = [
      SELECT Id, Status__c
      FROM LINE_Conversation__c
      WHERE Id = :conversationId
      WITH USER_MODE
      LIMIT 1
    ];
    if (conversations.isEmpty()) {
      throw asAuraException(System.Label.LINE_Error_No_Access);
    }
    // Object level only: the message is written in system mode by LineOutboundService, and the permission sets
    // deliberately keep message fields read-only for reps (03 §6), so a field-level create check would never pass.
    if (!Schema.SObjectType.LINE_Message__c.isCreateable()) {
      throw asAuraException(System.Label.LINE_Error_No_Access);
    }
    if (conversations[0].Status__c == 'Unfollowed') {
      throw asAuraException(System.Label.LINE_Error_Conversation_Inactive);
    }
  }

  // Sharing decides this: a rep only sees conversations they own (or their team's, through the role hierarchy).
  private static void assertCanRead(Id conversationId) {
    if (conversationId == null) {
      throw asAuraException(System.Label.LINE_Error_No_Access);
    }
    List<LINE_Conversation__c> found = [
      SELECT Id
      FROM LINE_Conversation__c
      WHERE Id = :conversationId
      WITH USER_MODE
      LIMIT 1
    ];
    if (found.isEmpty()) {
      throw asAuraException(System.Label.LINE_Error_No_Access);
    }
  }

  // Null when the Contact isn't readable or has no primary OA; only used for ordering.
  private static Id primaryOaOf(Id contactId) {
    List<Contact> contacts = [
      SELECT LINE_OA_Configuration__c
      FROM Contact
      WHERE Id = :contactId
      WITH USER_MODE
      LIMIT 1
    ];
    return contacts.isEmpty() ? null : contacts[0].LINE_OA_Configuration__c;
  }

  // One place to turn any failure into something the LWC can show, without leaking internals.
  private static AuraHandledException handled(
    Exception e,
    String method,
    Id recordId
  ) {
    if (e instanceof AuraHandledException) {
      return (AuraHandledException) e;
    }
    if (e instanceof LineApiException) {
      return asAuraException(((LineApiException) e).userMessage());
    }
    if (e instanceof IllegalArgumentException) {
      return asAuraException(e.getMessage());
    }
    if (e instanceof QueryException || e instanceof System.NoAccessException) {
      // WITH USER_MODE raises these when the user lacks object or field access.
      return asAuraException(System.Label.LINE_Error_No_Access);
    }
    lastUnexpectedError = e;
    LineLogger.error('LineChatController.' + method, e, null, recordId);
    LineLogger.flush();
    return asAuraException(System.Label.LINE_Error_Generic);
  }

  private static AuraHandledException asAuraException(String message) {
    AuraHandledException e = new AuraHandledException(message);
    // Without this, the LWC only sees "Script-thrown exception".
    e.setMessage(message);
    return e;
  }
}
