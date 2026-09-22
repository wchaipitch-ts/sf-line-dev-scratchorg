/**
 * LWC API for reps (02 §2). Everything a rep can reach goes through here.
 *
 * `with sharing` and user-mode checks: the rep must be able to see the conversation (OWD Private, owner = the OA's rep)
 * and to create messages, before any callout is made. Errors reach the LWC as `AuraHandledException` carrying a
 * Custom Label message; LINE's own message is passed through where it helps the rep (e.g. the monthly limit).
 *
 * M4: sending text. M5 adds the conversation and message reads, polling and mark-as-read.
 */
public with sharing class LineChatController {
  /** One message, as shown in the chat panel. Never contains secrets. */
  public class MessageView {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String direction;
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

    private MessageView(LINE_Message__c m) {
      this.id = m.Id;
      this.direction = m.Direction__c;
      this.messageType = m.Message_Type__c;
      this.text = m.Text__c;
      this.sentAt = m.Sent_At__c;
      this.status = m.Status__c;
      this.errorMessage = m.Error__c;
      this.senderId = m.Sender__c;
    }
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
    } catch (LineApiException e) {
      // LINE's own wording is the most useful thing for the rep (monthly limit, text too long, …).
      throw asAuraException(e.userMessage());
    } catch (IllegalArgumentException e) {
      throw asAuraException(e.getMessage());
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      LineLogger.error('LineChatController.sendText', e, null, conversationId);
      LineLogger.flush();
      throw asAuraException(System.Label.LINE_Error_Generic);
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

  private static AuraHandledException asAuraException(String message) {
    AuraHandledException e = new AuraHandledException(message);
    // Without this, the LWC only sees "Script-thrown exception".
    e.setMessage(message);
    return e;
  }
}
