/**
 * Test data for LINE Connect (07 §1). Fake values only: no real secrets, tokens or IDs.
 * Users get a profile picked by permissions, never by name (profile names are localized in Thai orgs).
 */
@IsTest
public class LineTestFactory {
  public static final String CHANNEL_A = '1000000001';
  public static final String CHANNEL_B = '1000000002';
  public static final String BOT_A = 'Ubot_a';
  public static final String BOT_B = 'Ubot_b';
  public static final String SECRET_A = 'testsecret_a';
  public static final String SECRET_B = 'testsecret_b';

  private static Integer userCounter = 0;
  private static List<Id> cachedProfileIds;

  /**
   * Creates an active user with a standard (non-admin) profile that can edit Contacts, and assigns the given
   * package permission sets. Tries each suitable profile in turn, because orgs often have only one or two free
   * seats per licence (a scratch org has 2 "Salesforce" and 3 "Salesforce Platform").
   * @param permissionSetNames e.g. `LINE_Chat_User`; may be empty
   * @return the inserted user
   */
  public static User createUser(List<String> permissionSetNames) {
    userCounter++;
    String unique =
      String.valueOf(Crypto.getRandomInteger()).remove('-') + userCounter;
    User u = new User(
      Username = 'line.test.' + unique + '@example.com',
      Email = 'line.test.' + unique + '@example.com',
      LastName = 'Test' + userCounter,
      Alias = ('lt' + unique).left(8),
      TimeZoneSidKey = 'Asia/Bangkok',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8'
    );
    List<String> errors = new List<String>();
    // runAs isolates the setup-object DML (User, PermissionSetAssignment) from the test's business DML.
    System.runAs(new User(Id = UserInfo.getUserId())) {
      for (Id profileId : standardProfileIds()) {
        u.ProfileId = profileId;
        Database.SaveResult sr = Database.insert(u, false);
        if (sr.isSuccess()) {
          assignPermissionSets(u.Id, permissionSetNames);
          break;
        }
        errors.add(sr.getErrors()[0].getMessage());
      }
    }
    Assert.isNotNull(
      u.Id,
      'Could not create a test user: ' + String.join(errors, '; ')
    );
    return u;
  }

  /**
   * Assigns package permission sets to a user.
   * @param userId the user
   * @param permissionSetNames permission set API names
   */
  public static void assignPermissionSets(
    Id userId,
    List<String> permissionSetNames
  ) {
    if (permissionSetNames == null || permissionSetNames.isEmpty()) {
      return;
    }
    List<PermissionSetAssignment> psas = new List<PermissionSetAssignment>();
    for (PermissionSet ps : [
      SELECT Id
      FROM PermissionSet
      WHERE Name IN :permissionSetNames
    ]) {
      psas.add(
        new PermissionSetAssignment(
          AssigneeId = userId,
          PermissionSetId = ps.Id
        )
      );
    }
    insert psas;
  }

  /**
   * @return standard-user profiles with Contact edit and without Modify All Data, one per licence
   *         (Salesforce first, then Salesforce Platform; matched by licence key, not name)
   */
  public static List<Id> standardProfileIds() {
    if (cachedProfileIds == null) {
      cachedProfileIds = new List<Id>();
      Set<String> licences = new Set<String>();
      for (ObjectPermissions op : [
        SELECT Parent.ProfileId, Parent.Profile.UserLicense.LicenseDefinitionKey
        FROM ObjectPermissions
        WHERE
          SobjectType = 'Contact'
          AND PermissionsEdit = TRUE
          AND Parent.IsOwnedByProfile = TRUE
          AND Parent.Profile.UserType = 'Standard'
          AND Parent.Profile.UserLicense.LicenseDefinitionKey IN ('SFDC', 'AUL')
          AND Parent.PermissionsModifyAllData = FALSE
        ORDER BY
          Parent.Profile.UserLicense.LicenseDefinitionKey DESC,
          Parent.Profile.CreatedDate
      ]) {
        if (licences.add(op.Parent.Profile.UserLicense.LicenseDefinitionKey)) {
          cachedProfileIds.add(op.Parent.ProfileId);
        }
      }
      Assert.isFalse(
        cachedProfileIds.isEmpty(),
        'No suitable standard profile for test users.'
      );
    }
    return cachedProfileIds;
  }

  /**
   * Creates an active OA configuration and stores its fake secret.
   * @param channelId channel ID
   * @param botUserId bot user ID
   * @param secret fake secret
   * @param repId assigned rep
   * @return the inserted record
   */
  public static LINE_OA_Configuration__c createOA(
    String channelId,
    String botUserId,
    String secret,
    Id repId
  ) {
    LINE_OA_Configuration__c oa = newOAConfig(channelId, botUserId, repId);
    insert oa;
    LineCredentialStore.putSecret(channelId, secret);
    return oa;
  }

  /**
   * Calls the webhook as LINE would: signed with the given secret. Doesn't deliver the platform events.
   * @param body raw webhook body
   * @param secret secret to sign with (null = no signature header)
   * @return the HTTP status returned by the webhook
   */
  public static Integer callWebhook(String body, String secret) {
    RestRequest req = new RestRequest();
    req.requestURI = '/services/apexrest/line/webhook';
    req.httpMethod = 'POST';
    req.requestBody = Blob.valueOf(body);
    if (secret != null) {
      req.addHeader('X-Line-Signature', sign(body, secret));
    }
    RestContext.request = req;
    RestContext.response = new RestResponse();
    LineWebhookResource.handlePost();
    return RestContext.response.statusCode;
  }

  /**
   * Signs and posts events to the webhook, then delivers the published platform events (runs the trigger).
   * @param destination bot user ID
   * @param secret channel secret
   * @param events event JSON objects
   * @return the HTTP status returned by the webhook
   */
  public static Integer deliver(
    String destination,
    String secret,
    List<String> events
  ) {
    Integer status = callWebhook(webhookBody(destination, events), secret);
    Test.getEventBus().deliver();
    return status;
  }

  /**
   * @param userId customer LINE user ID
   * @param eventId webhookEventId
   * @param messageJson the `message` object as JSON
   * @return a message event with any message object
   */
  public static String rawMessageEvent(
    String userId,
    String eventId,
    String messageJson
  ) {
    return messageEvent(userId, eventId, messageJson);
  }

  /**
   * @param event an event JSON object
   * @param sourceType `group` or `room`
   * @return the event with its source type replaced
   */
  public static String withSourceType(String event, String sourceType) {
    return event.replace(
      '"source":{"type":"user"',
      '"source":{"type":"' + sourceType + '"'
    );
  }

  /**
   * Builds (does not insert) an active OA configuration.
   * @param channelId channel ID
   * @param botUserId bot user ID (webhook destination)
   * @param repId assigned rep
   * @return the record
   */
  public static LINE_OA_Configuration__c newOAConfig(
    String channelId,
    String botUserId,
    Id repId
  ) {
    return new LINE_OA_Configuration__c(
      Name = 'OA ' + channelId,
      Channel_Id__c = channelId,
      Bot_User_Id__c = botUserId,
      Basic_Id__c = '@' + channelId.right(8),
      Assigned_Rep__c = repId,
      Is_Active__c = true
    );
  }

  /**
   * Stores the fake secrets of channels A and B.
   */
  public static void putTestSecrets() {
    LineCredentialStore.putSecret(CHANNEL_A, SECRET_A);
    LineCredentialStore.putSecret(CHANNEL_B, SECRET_B);
  }

  /**
   * @param body raw webhook body
   * @param secret channel secret
   * @return the `X-Line-Signature` value LINE would send
   */
  public static String sign(String body, String secret) {
    return EncodingUtil.base64Encode(
      Crypto.generateMac('hmacSHA256', Blob.valueOf(body), Blob.valueOf(secret))
    );
  }

  /**
   * @param destination bot user ID of the receiving OA
   * @param events event JSON objects
   * @return a webhook body
   */
  public static String webhookBody(String destination, List<String> events) {
    return '{"destination":' +
      JSON.serialize(destination) +
      ',"events":[' +
      String.join(events, ',') +
      ']}';
  }

  /**
   * @param userId customer LINE user ID
   * @param text message text
   * @param eventId webhookEventId
   * @return a text message event
   */
  public static String textEvent(String userId, String text, String eventId) {
    return messageEvent(
      userId,
      eventId,
      '{"id":"' +
        eventId +
        'm","type":"text","text":' +
        JSON.serialize(text) +
        '}'
    );
  }

  /**
   * @param userId customer LINE user ID
   * @param fileName file name
   * @param fileSize size in bytes
   * @param eventId webhookEventId
   * @return a file message event
   */
  public static String fileEvent(
    String userId,
    String fileName,
    Long fileSize,
    String eventId
  ) {
    return messageEvent(
      userId,
      eventId,
      '{"id":"' +
        eventId +
        'm","type":"file","fileName":' +
        JSON.serialize(fileName) +
        ',"fileSize":' +
        fileSize +
        '}'
    );
  }

  /**
   * @param userId customer LINE user ID
   * @param eventId webhookEventId
   * @return a follow event
   */
  public static String followEvent(String userId, String eventId) {
    return baseEvent('follow', userId, eventId, true) +
      ',"follow":{"isUnblocked":false}}';
  }

  /**
   * @param userId customer LINE user ID
   * @param eventId webhookEventId
   * @return an unfollow event (no reply token)
   */
  public static String unfollowEvent(String userId, String eventId) {
    return baseEvent('unfollow', userId, eventId, false) + '}';
  }

  private static String messageEvent(
    String userId,
    String eventId,
    String messageJson
  ) {
    return baseEvent('message', userId, eventId, true) +
      ',"message":' +
      messageJson +
      '}';
  }

  private static String baseEvent(
    String type,
    String userId,
    String eventId,
    Boolean withReplyToken
  ) {
    return '{"type":"' +
      type +
      '","mode":"active","timestamp":' +
      System.currentTimeMillis() +
      ',"webhookEventId":"' +
      eventId +
      '","deliveryContext":{"isRedelivery":false}' +
      ',"source":{"type":"user","userId":"' +
      userId +
      '"}' +
      (withReplyToken ? ',"replyToken":"reply-' + eventId + '"' : '');
  }
}
