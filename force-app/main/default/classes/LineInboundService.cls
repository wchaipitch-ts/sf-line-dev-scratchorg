/**
 * Processes LINE webhook events (message, follow, unfollow) delivered as `LINE_Webhook_Event__e` (02 §4).
 * Bulk-safe for a full platform event batch: a fixed number of queries and DML statements per call.
 *
 * Steps: parse and filter → resolve owners → upsert conversations by `Unique_Key__c` → upsert messages by
 * `Webhook_Event_Id__c` (redeliveries are no-ops and don't touch unread counts) → notify owners → enqueue one
 * `LineCalloutQueueable` for follow-up callouts.
 * Linking to Contacts (auto-link, invite codes) is added in M6 by `LineLinkService`.
 *
 * `without sharing` (02 §2): runs as Automated Process from the platform event trigger and creates conversations
 * owned by reps, which no user context could do. Nothing here is exposed to users directly.
 */
public without sharing class LineInboundService {
  private static final Integer NAME_LENGTH = 80;
  private static final Integer PREVIEW_LENGTH = 255;
  private static final Integer TEXT_LENGTH = 5000;
  private static final Integer SHORT_TEXT_LENGTH = 255;
  private static final Set<String> HANDLED_EVENTS = new Set<String>{
    'message',
    'follow',
    'unfollow'
  };
  private static final Set<String> KNOWN_MESSAGE_TYPES = new Set<String>{
    'text',
    'image',
    'video',
    'audio',
    'file',
    'sticker',
    'location'
  };
  private static final String STATUS_FOLLOWING = 'Following';
  private static final String STATUS_UNFOLLOWED = 'Unfollowed';

  @TestVisible
  static final String NOTIFICATION_TYPE = 'LINE_New_Message';
  // Caps notifications per batch so a burst from many customers can't flood reps or burn CPU.
  @TestVisible
  static final Integer MAX_NOTIFICATIONS_PER_BATCH = 100;
  // Result of the last call, for tests (the trigger discards it).
  @TestVisible
  static Result lastResult;

  /** Result counts, for tests and diagnostics. */
  public class Result {
    public Integer eventsHandled = 0;
    public Integer messagesStored = 0;
    public Integer conversationsUpserted = 0;
    public Integer notificationsSent = 0;
    public Integer calloutItemsQueued = 0;
  }

  /**
   * Owner of an OA's new conversations (03 §3, D6): the assigned rep while the OA is active; otherwise the fallback
   * owner from LINE Settings. Only active users and queues that support LINE Conversation qualify. If neither fits,
   * the rep, then the OA record's owner is used, so a conversation never ends up owned by Automated Process.
   * Declared `without sharing` itself because inner classes don't inherit the outer class's sharing.
   */
  public without sharing class OwnerResolver {
    private List<LINE_OA_Configuration__c> oas = new List<LINE_OA_Configuration__c>();
    private Set<Id> activeUserIds = new Set<Id>();
    private Id fallbackOwnerId;

    /**
     * @param oa an OA whose owner will be asked for
     */
    public void add(LINE_OA_Configuration__c oa) {
      oas.add(oa);
    }

    /**
     * Loads the users and queue needed by `ownerFor` (two queries at most).
     */
    public void resolve() {
      Set<Id> userIds = new Set<Id>();
      for (LINE_OA_Configuration__c oa : oas) {
        if (oa.Assigned_Rep__c != null) {
          userIds.add(oa.Assigned_Rep__c);
        }
        userIds.add(oa.OwnerId);
      }
      Id fallback = LineSettings.fallbackOwnerId();
      if (fallback != null && fallback.getSObjectType() == User.SObjectType) {
        userIds.add(fallback);
      } else if (fallback != null && queueSupportsConversations(fallback)) {
        fallbackOwnerId = fallback;
      }
      for (User u : [
        SELECT Id
        FROM User
        WHERE Id IN :userIds AND IsActive = TRUE
        WITH SYSTEM_MODE
      ]) {
        activeUserIds.add(u.Id);
      }
      if (fallback != null && activeUserIds.contains(fallback)) {
        fallbackOwnerId = fallback;
      }
    }

    /**
     * @param oa the conversation's OA
     * @return the owner to use, or null if nothing qualifies
     */
    public Id ownerFor(LINE_OA_Configuration__c oa) {
      Boolean repActive = activeUserIds.contains(oa.Assigned_Rep__c);
      if (oa.Is_Active__c && repActive) {
        return oa.Assigned_Rep__c;
      }
      if (fallbackOwnerId != null) {
        return fallbackOwnerId;
      }
      if (repActive) {
        return oa.Assigned_Rep__c;
      }
      return activeUserIds.contains(oa.OwnerId) ? oa.OwnerId : null;
    }

    private Boolean queueSupportsConversations(Id queueId) {
      String sobjectType = LineNamespace.apiPrefix() + 'LINE_Conversation__c';
      return [
          SELECT COUNT()
          FROM QueueSobject
          WHERE QueueId = :queueId AND SobjectType = :sobjectType
          WITH SYSTEM_MODE
        ] > 0;
    }
  }

  // One parsed, accepted event with its OA.
  private class Incoming {
    LineWebhookModels.Event event;
    LINE_OA_Configuration__c oa;
    String key;
  }

  /**
   * @param platformEvents the trigger's events, in delivery order
   * @return what was processed
   */
  public static Result process(List<LINE_Webhook_Event__e> platformEvents) {
    Result result = new Result();
    List<Incoming> incoming = parseAndFilter(platformEvents);
    if (incoming.isEmpty()) {
      return result;
    }
    result.eventsHandled = incoming.size();

    Map<String, LINE_Conversation__c> existing = existingConversations(
      incoming
    );
    Set<String> alreadyStored = storedEventIds(incoming);

    Map<String, LINE_Conversation__c> conversations = buildConversations(
      incoming,
      existing,
      alreadyStored
    );
    Map<String, Id> conversationIdByKey = upsertConversations(conversations);
    result.conversationsUpserted = conversationIdByKey.size();

    List<LINE_Message__c> messages = buildMessages(
      incoming,
      conversationIdByKey,
      alreadyStored
    );
    result.messagesStored = upsertMessages(messages);

    result.notificationsSent = notifyOwners(
      messages,
      conversations,
      conversationIdByKey
    );
    result.calloutItemsQueued = enqueueFollowUps(
      incoming,
      existing,
      conversationIdByKey
    );
    lastResult = result;
    return result;
  }

  // ---------------------------------------------------------------------------------------------------------------

  private static List<Incoming> parseAndFilter(
    List<LINE_Webhook_Event__e> platformEvents
  ) {
    Set<Id> oaIds = new Set<Id>();
    for (LINE_Webhook_Event__e pe : platformEvents) {
      Id oaId = toId(pe.OA_Configuration_Id__c);
      if (oaId != null) {
        oaIds.add(oaId);
      }
    }
    Map<Id, LINE_OA_Configuration__c> oas = LineOAConfigSelector.byIds(oaIds);

    List<Incoming> result = new List<Incoming>();
    for (LINE_Webhook_Event__e pe : platformEvents) {
      LINE_OA_Configuration__c oa = oas.get(toId(pe.OA_Configuration_Id__c));
      LineWebhookModels.Event event = parseSafely(pe);
      if (oa == null || !isHandled(event)) {
        continue;
      }
      Incoming item = new Incoming();
      item.event = event;
      item.oa = oa;
      item.key = oa.Channel_Id__c + ':' + event.source.userId;
      result.add(item);
    }
    return result;
  }

  private static Id toId(String value) {
    try {
      return String.isBlank(value) ? null : Id.valueOf(value);
    } catch (StringException e) {
      return null;
    }
  }

  private static LineWebhookModels.Event parseSafely(LINE_Webhook_Event__e pe) {
    try {
      return LineWebhookModels.parse(pe.Event_Json__c);
    } catch (Exception e) {
      LineLogger.error(
        'LineInboundService.parse',
        e,
        toId(pe.OA_Configuration_Id__c),
        null
      );
      return null;
    }
  }

  // 1:1 chats only (L8). Standby mode means another channel owns the chat, so it's ignored.
  private static Boolean isHandled(LineWebhookModels.Event event) {
    return event != null &&
      HANDLED_EVENTS.contains(event.type) &&
      event.mode != 'standby' &&
      event.source != null &&
      event.source.type == 'user' &&
      String.isNotBlank(event.source.userId) &&
      String.isNotBlank(event.webhookEventId);
  }

  private static Map<String, LINE_Conversation__c> existingConversations(
    List<Incoming> incoming
  ) {
    Set<String> keys = new Set<String>();
    for (Incoming item : incoming) {
      keys.add(item.key);
    }
    Map<String, LINE_Conversation__c> result = new Map<String, LINE_Conversation__c>();
    for (LINE_Conversation__c c : [
      SELECT
        Id,
        Unique_Key__c,
        OwnerId,
        Name,
        Unread_Count__c,
        Last_Message_At__c,
        Status__c
      FROM LINE_Conversation__c
      WHERE Unique_Key__c IN :keys
      WITH SYSTEM_MODE
    ]) {
      result.put(c.Unique_Key__c, c);
    }
    return result;
  }

  private static Set<String> storedEventIds(List<Incoming> incoming) {
    Set<String> eventIds = new Set<String>();
    for (Incoming item : incoming) {
      if (item.event.type == 'message') {
        eventIds.add(item.event.webhookEventId);
      }
    }
    Set<String> result = new Set<String>();
    if (eventIds.isEmpty()) {
      return result;
    }
    for (LINE_Message__c m : [
      SELECT Webhook_Event_Id__c
      FROM LINE_Message__c
      WHERE Webhook_Event_Id__c IN :eventIds
      WITH SYSTEM_MODE
    ]) {
      result.add(m.Webhook_Event_Id__c);
    }
    return result;
  }

  private static Map<String, LINE_Conversation__c> buildConversations(
    List<Incoming> incoming,
    Map<String, LINE_Conversation__c> existing,
    Set<String> alreadyStored
  ) {
    OwnerResolver owners = new OwnerResolver();
    for (Incoming item : incoming) {
      owners.add(item.oa);
    }
    owners.resolve();

    Map<String, LINE_Conversation__c> result = new Map<String, LINE_Conversation__c>();
    Set<String> seenMessageIds = new Set<String>();
    for (Incoming item : incoming) {
      LINE_Conversation__c current = existing.get(item.key);
      LINE_Conversation__c c = result.get(item.key);
      if (c == null) {
        c = new LINE_Conversation__c(Unique_Key__c = item.key);
        if (current == null) {
          c.Name = item.event.source.userId.left(NAME_LENGTH);
          c.LINE_OA_Configuration__c = item.oa.Id;
          c.LINE_User_Id__c = item.event.source.userId;
          Id ownerId = owners.ownerFor(item.oa);
          if (ownerId != null) {
            c.OwnerId = ownerId;
          }
          c.Status__c = STATUS_FOLLOWING;
          c.Unread_Count__c = 0;
        } else {
          c.Unread_Count__c = current.Unread_Count__c == null
            ? 0
            : current.Unread_Count__c;
          c.Last_Message_At__c = current.Last_Message_At__c;
        }
        result.put(item.key, c);
      }
      applyEvent(c, item.event, alreadyStored, seenMessageIds);
    }
    return result;
  }

  private static void applyEvent(
    LINE_Conversation__c c,
    LineWebhookModels.Event event,
    Set<String> alreadyStored,
    Set<String> seenMessageIds
  ) {
    if (event.type == 'follow') {
      c.Status__c = STATUS_FOLLOWING;
      return;
    }
    if (event.type == 'unfollow') {
      c.Status__c = STATUS_UNFOLLOWED;
      return;
    }
    // message: count it once, and only if it isn't a redelivery of a stored message
    if (
      alreadyStored.contains(event.webhookEventId) ||
      !seenMessageIds.add(event.webhookEventId)
    ) {
      return;
    }
    c.Unread_Count__c = (c.Unread_Count__c == null ? 0 : c.Unread_Count__c) + 1;
    Datetime sentAt = sentAt(event);
    if (c.Last_Message_At__c == null || sentAt >= c.Last_Message_At__c) {
      c.Last_Message_At__c = sentAt;
      c.Last_Message_Preview__c = preview(event.message);
    }
  }

  private static Map<String, Id> upsertConversations(
    Map<String, LINE_Conversation__c> conversations
  ) {
    List<LINE_Conversation__c> records = conversations.values();
    List<Database.UpsertResult> results = Database.upsert(
      records,
      LINE_Conversation__c.Unique_Key__c,
      false,
      AccessLevel.SYSTEM_MODE
    );
    Map<String, Id> idByKey = new Map<String, Id>();
    for (Integer i = 0; i < results.size(); i++) {
      if (results[i].isSuccess()) {
        idByKey.put(records[i].Unique_Key__c, results[i].getId());
      } else {
        LineLogger.error(
          'LineInboundService.upsertConversations',
          records[i].Unique_Key__c + ': ' + describe(results[i].getErrors()),
          records[i].LINE_OA_Configuration__c,
          null
        );
      }
    }
    return idByKey;
  }

  private static List<LINE_Message__c> buildMessages(
    List<Incoming> incoming,
    Map<String, Id> conversationIdByKey,
    Set<String> alreadyStored
  ) {
    Map<String, LINE_Message__c> byEventId = new Map<String, LINE_Message__c>();
    for (Incoming item : incoming) {
      Id conversationId = conversationIdByKey.get(item.key);
      if (
        item.event.type != 'message' ||
        conversationId == null ||
        alreadyStored.contains(item.event.webhookEventId) ||
        byEventId.containsKey(item.event.webhookEventId)
      ) {
        continue;
      }
      byEventId.put(
        item.event.webhookEventId,
        toMessage(item.event, conversationId)
      );
    }
    return byEventId.values();
  }

  @TestVisible
  private static LINE_Message__c toMessage(
    LineWebhookModels.Event event,
    Id conversationId
  ) {
    LineWebhookModels.Message m = event.message == null
      ? new LineWebhookModels.Message()
      : event.message;
    String type = KNOWN_MESSAGE_TYPES.contains(m.type) ? m.type : 'unsupported';
    LINE_Message__c msg = new LINE_Message__c(
      LINE_Conversation__c = conversationId,
      Direction__c = 'Inbound',
      Message_Type__c = type,
      Sent_At__c = sentAt(event),
      Line_Message_Id__c = m.id,
      Webhook_Event_Id__c = event.webhookEventId,
      Status__c = 'Received'
    );
    switch on type {
      when 'text' {
        msg.Text__c = truncate(m.text, TEXT_LENGTH);
      }
      when 'file' {
        msg.File_Name__c = truncate(m.fileName, SHORT_TEXT_LENGTH);
        msg.File_Size__c = m.fileSize;
      }
      when 'sticker' {
        msg.Sticker_Package_Id__c = m.packageId;
        msg.Sticker_Id__c = m.stickerId;
      }
      when 'location' {
        msg.Location__c = truncate(locationText(m), SHORT_TEXT_LENGTH);
      }
    }
    // Media content is downloaded in M7; until then media messages are stored as placeholders.
    return msg;
  }

  private static Integer upsertMessages(List<LINE_Message__c> messages) {
    if (messages.isEmpty()) {
      return 0;
    }
    List<Database.UpsertResult> results = Database.upsert(
      messages,
      LINE_Message__c.Webhook_Event_Id__c,
      false,
      AccessLevel.SYSTEM_MODE
    );
    Integer stored = 0;
    for (Integer i = 0; i < results.size(); i++) {
      if (results[i].isSuccess()) {
        stored++;
      } else {
        LineLogger.error(
          'LineInboundService.upsertMessages',
          messages[i].Webhook_Event_Id__c +
            ': ' +
            describe(results[i].getErrors()),
          null,
          messages[i].LINE_Conversation__c
        );
      }
    }
    return stored;
  }

  // One notification per conversation per batch, only when the owner is a user (queues can't be notified).
  private static Integer notifyOwners(
    List<LINE_Message__c> messages,
    Map<String, LINE_Conversation__c> conversations,
    Map<String, Id> conversationIdByKey
  ) {
    Set<Id> conversationsWithNewMessages = new Set<Id>();
    for (LINE_Message__c m : messages) {
      if (m.Id != null) {
        conversationsWithNewMessages.add(m.LINE_Conversation__c);
      }
    }
    if (conversationsWithNewMessages.isEmpty()) {
      return 0;
    }
    Id typeId = notificationTypeId();
    if (typeId == null) {
      LineLogger.error(
        'LineInboundService.notifyOwners',
        'Notification type not found.',
        null,
        null
      );
      return 0;
    }
    Integer sent = 0;
    for (LINE_Conversation__c c : [
      SELECT Id, Name, OwnerId, Last_Message_Preview__c
      FROM LINE_Conversation__c
      WHERE Id IN :conversationsWithNewMessages
      WITH SYSTEM_MODE
    ]) {
      if (
        c.OwnerId.getSObjectType() != User.SObjectType ||
        sent >= MAX_NOTIFICATIONS_PER_BATCH
      ) {
        continue;
      }
      try {
        Messaging.CustomNotification n = new Messaging.CustomNotification();
        n.setNotificationTypeId(typeId);
        n.setTargetId(c.Id);
        n.setTitle(
          String.format(
            System.Label.LINE_Notification_New_Message_Title,
            new List<Object>{ c.Name }
          )
        );
        n.setBody(
          String.isBlank(c.Last_Message_Preview__c)
            ? c.Name
            : c.Last_Message_Preview__c
        );
        n.send(new Set<String>{ c.OwnerId });
        sent++;
      } catch (Exception e) {
        LineLogger.error('LineInboundService.notifyOwners', e, null, c.Id);
      }
    }
    return sent;
  }

  private static Id notificationTypeId() {
    String ns = LineNamespace.prefix();
    for (CustomNotificationType t : [
      SELECT Id, NamespacePrefix
      FROM CustomNotificationType
      WHERE DeveloperName = :NOTIFICATION_TYPE
      WITH SYSTEM_MODE
    ]) {
      // Prefer the package's own type if a subscriber created one with the same name.
      if (
        (String.isEmpty(ns) && t.NamespacePrefix == null) ||
        t.NamespacePrefix == ns
      ) {
        return t.Id;
      }
    }
    return null;
  }

  // Profile fetch for new conversations and for (re-)follows. One queueable per transaction (CLAUDE.md).
  private static Integer enqueueFollowUps(
    List<Incoming> incoming,
    Map<String, LINE_Conversation__c> existing,
    Map<String, Id> conversationIdByKey
  ) {
    Map<Id, LineCalloutQueueable.WorkItem> items = new Map<Id, LineCalloutQueueable.WorkItem>();
    for (Incoming item : incoming) {
      Id conversationId = conversationIdByKey.get(item.key);
      Boolean isNew = !existing.containsKey(item.key);
      if (
        conversationId == null ||
        items.containsKey(conversationId) ||
        !(isNew || item.event.type == 'follow')
      ) {
        continue;
      }
      items.put(
        conversationId,
        LineCalloutQueueable.profileItem(
          conversationId,
          item.oa.Id,
          item.oa.Channel_Id__c,
          item.event.source.userId
        )
      );
    }
    if (!items.isEmpty()) {
      LineCalloutQueueable.enqueue(items.values());
    }
    return items.size();
  }

  // ---------------------------------------------------------------------------------------------------------------

  private static Datetime sentAt(LineWebhookModels.Event event) {
    return event.timestamp == null
      ? Datetime.now()
      : Datetime.newInstance(event.timestamp);
  }

  @TestVisible
  private static String preview(LineWebhookModels.Message m) {
    if (m == null) {
      return System.Label.LINE_Preview_Unsupported;
    }
    String result;
    switch on m.type {
      when 'text' {
        result = m.text;
      }
      when 'image' {
        result = System.Label.LINE_Preview_Image;
      }
      when 'video' {
        result = System.Label.LINE_Preview_Video;
      }
      when 'audio' {
        result = System.Label.LINE_Preview_Audio;
      }
      when 'file' {
        result = String.format(
          System.Label.LINE_Preview_File,
          new List<Object>{ m.fileName == null ? '' : m.fileName }
        );
      }
      when 'sticker' {
        result = System.Label.LINE_Preview_Sticker;
      }
      when 'location' {
        result = String.format(
          System.Label.LINE_Preview_Location,
          new List<Object>{ m.title == null ? m.address : m.title }
        );
      }
      when else {
        result = System.Label.LINE_Preview_Unsupported;
      }
    }
    return truncate(result, PREVIEW_LENGTH);
  }

  private static String locationText(LineWebhookModels.Message m) {
    List<String> parts = new List<String>();
    for (String part : new List<String>{ m.title, m.address }) {
      if (String.isNotBlank(part)) {
        parts.add(part);
      }
    }
    String coords = m.latitude == null ||
      m.longitude == null
      ? ''
      : ' (' + m.latitude + ',' + m.longitude + ')';
    return String.join(parts, ', ') + coords;
  }

  private static String describe(List<Database.Error> errors) {
    List<String> parts = new List<String>();
    for (Database.Error err : errors) {
      parts.add(err.getStatusCode() + ': ' + err.getMessage());
    }
    return String.join(parts, '; ');
  }

  private static String truncate(String value, Integer maxLength) {
    return value == null ||
      value.length() <= maxLength
      ? value
      : value.left(maxLength);
  }
}
