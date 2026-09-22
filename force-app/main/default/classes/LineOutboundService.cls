/**
 * Sends messages to LINE and records them (02 §4 "Outbound", D8).
 *
 * Callout first, then DML (hard rule 6): the push is made before any record is written, so a failed transaction can
 * never leave a "Sent" row for a message LINE never received. Every attempt is recorded, successful or not, so the rep
 * sees what happened. Pushes carry `X-Line-Retry-Key`, and a 409 ("already accepted") counts as success.
 *
 * `without sharing` (02 §2): callers check the user's access to the conversation in user mode first (see
 * `LineChatController`); this class then writes the message and updates the conversation, which the rep may not own.
 */
// Whole class: the graph engine flags every read and write here as missing sharing/FLS enforcement. That is the
// design (02 §2, SECURITY_NOTES §4): LineChatController checks the rep's access to the conversation and their Create
// on LINE_Message__c in user mode first, then this class records the message and touches the conversation the rep may
// not own. Message fields are deliberately read-only for reps, so a user-mode insert could never work here.
// code-analyzer-suppress(sfge)
public without sharing class LineOutboundService {
  /** LINE's own limit for a text message (04 §3). */
  public static final Integer MAX_TEXT_LENGTH = 5000;
  private static final Integer ERROR_LENGTH = 255;
  private static final Integer PREVIEW_LENGTH = 255;

  /**
   * Sends a text message to the conversation's customer through that conversation's OA.
   *
   * @param conversationId the conversation to reply to
   * @param text 1–5,000 characters
   * @return the stored message (Status `Sent`), with its Id
   * @throws LineApiException when LINE rejects the send; a message with Status `Failed` is stored first
   * @throws IllegalArgumentException when the text or conversation is unusable
   */
  public static LINE_Message__c sendText(Id conversationId, String text) {
    if (String.isBlank(text)) {
      throw new IllegalArgumentException(System.Label.LINE_Error_Message_Empty);
    }
    if (text.length() > MAX_TEXT_LENGTH) {
      throw new IllegalArgumentException(
        String.format(
          System.Label.LINE_Error_Message_Too_Long,
          new List<Object>{ String.valueOf(MAX_TEXT_LENGTH) }
        )
      );
    }
    LINE_Conversation__c conversation = load(conversationId);

    LINE_Message__c message = new LINE_Message__c(
      LINE_Conversation__c = conversation.Id,
      Direction__c = 'Outbound',
      Message_Type__c = 'text',
      Text__c = text,
      Sent_At__c = Datetime.now(),
      Sender__c = UserInfo.getUserId()
    );
    try {
      // 1. Callout
      LineApiModels.PushResult result = LineApiClient.forChannel(
          conversation.LINE_OA_Configuration__r.Channel_Id__c
        )
        .push(
          conversation.LINE_User_Id__c,
          new List<LineApiModels.Message>{ LineApiModels.textMessage(text) },
          null
        );
      // 2. DML
      message.Status__c = 'Sent';
      if (!result.sentMessages.isEmpty()) {
        message.Line_Message_Id__c = result.sentMessages[0].id;
      }
      insert as system message;
      touchConversation(conversation, message);
      return message;
    } catch (LineApiException e) {
      message.Status__c = 'Failed';
      message.Error__c = truncate(e.userMessage(), ERROR_LENGTH);
      insert as system message;
      LineLogger.error(
        'LineOutboundService.sendText',
        e,
        conversation.LINE_OA_Configuration__c,
        conversation.Id
      );
      LineLogger.flush();
      throw e;
    }
  }

  // The caller has already checked the user's access; this read is by Id and in system mode.
  private static LINE_Conversation__c load(Id conversationId) {
    List<LINE_Conversation__c> found = [
      SELECT
        Id,
        LINE_User_Id__c,
        Status__c,
        LINE_OA_Configuration__c,
        LINE_OA_Configuration__r.Channel_Id__c,
        Last_Message_At__c
      FROM LINE_Conversation__c
      WHERE Id = :conversationId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (found.isEmpty()) {
      throw new IllegalArgumentException(System.Label.LINE_Error_Generic);
    }
    if (String.isBlank(found[0].LINE_OA_Configuration__r?.Channel_Id__c)) {
      throw new IllegalArgumentException(System.Label.LINE_Error_Generic);
    }
    return found[0];
  }

  // Keeps the inbox ordering and preview in step with what the rep just sent.
  private static void touchConversation(
    LINE_Conversation__c conversation,
    LINE_Message__c message
  ) {
    Database.SaveResult result = Database.update(
      new LINE_Conversation__c(
        Id = conversation.Id,
        Last_Message_At__c = message.Sent_At__c,
        Last_Message_Preview__c = truncate(message.Text__c, PREVIEW_LENGTH)
      ),
      false,
      AccessLevel.SYSTEM_MODE
    );
    if (!result.isSuccess()) {
      // The message is sent and stored; a stale preview must not fail the send.
      LineLogger.error(
        'LineOutboundService.touchConversation',
        String.valueOf(result.getErrors()),
        conversation.LINE_OA_Configuration__c,
        conversation.Id
      );
      LineLogger.flush();
    }
  }

  private static String truncate(String value, Integer maxLength) {
    return value == null ||
      value.length() <= maxLength
      ? value
      : value.left(maxLength);
  }
}
// code-analyzer-unsuppress(sfge)
