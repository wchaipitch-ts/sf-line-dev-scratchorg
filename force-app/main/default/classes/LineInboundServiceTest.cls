@IsTest
private class LineInboundServiceTest {
  private static final String CUSTOMER = 'Ucustomer1';

  @TestSetup
  static void setup() {
    User repA = LineTestFactory.createUser(
      new List<String>{ 'LINE_Chat_User' }
    );
    User repB = LineTestFactory.createUser(
      new List<String>{ 'LINE_Chat_User' }
    );
    LineTestFactory.createOA(
      LineTestFactory.CHANNEL_A,
      LineTestFactory.BOT_A,
      LineTestFactory.SECRET_A,
      repA.Id
    );
    LineTestFactory.createOA(
      LineTestFactory.CHANNEL_B,
      LineTestFactory.BOT_B,
      LineTestFactory.SECRET_B,
      repB.Id
    );
  }

  private static LINE_OA_Configuration__c oa(String channelId) {
    return [
      SELECT Id, Assigned_Rep__c, Is_Active__c
      FROM LINE_OA_Configuration__c
      WHERE Channel_Id__c = :channelId
    ];
  }

  private static Integer sendToA(List<String> events) {
    return LineTestFactory.deliver(
      LineTestFactory.BOT_A,
      LineTestFactory.SECRET_A,
      events
    );
  }

  private static LINE_Conversation__c conversation(
    String channelId,
    String userId
  ) {
    String key = channelId + ':' + userId;
    return [
      SELECT
        Id,
        Name,
        OwnerId,
        LINE_OA_Configuration__c,
        LINE_User_Id__c,
        Status__c,
        Unread_Count__c,
        Last_Message_At__c,
        Last_Message_Preview__c
      FROM LINE_Conversation__c
      WHERE Unique_Key__c = :key
    ];
  }

  // ---------- routing and storage ----------

  @IsTest
  static void textMessageCreatesConversationOwnedByRepAndStoresMessage() {
    LINE_OA_Configuration__c oaA = oa(LineTestFactory.CHANNEL_A);

    sendToA(
      new List<String>{
        LineTestFactory.textEvent(CUSTOMER, 'สวัสดีครับ', 'evt1')
      }
    );

    LINE_Conversation__c c = conversation(LineTestFactory.CHANNEL_A, CUSTOMER);
    Assert.areEqual(oaA.Assigned_Rep__c, c.OwnerId, 'Owner = the OA rep');
    Assert.areEqual(oaA.Id, c.LINE_OA_Configuration__c);
    Assert.areEqual(CUSTOMER, c.LINE_User_Id__c);
    Assert.areEqual(
      CUSTOMER,
      c.Name,
      'Name is the user ID until the profile is fetched'
    );
    Assert.areEqual('Following', c.Status__c);
    Assert.areEqual(1, c.Unread_Count__c);
    Assert.areEqual('สวัสดีครับ', c.Last_Message_Preview__c);

    LINE_Message__c m = [
      SELECT
        Direction__c,
        Message_Type__c,
        Text__c,
        Status__c,
        Webhook_Event_Id__c,
        Line_Message_Id__c,
        Sent_At__c
      FROM LINE_Message__c
      WHERE LINE_Conversation__c = :c.Id
    ];
    Assert.areEqual('Inbound', m.Direction__c);
    Assert.areEqual('text', m.Message_Type__c);
    Assert.areEqual('สวัสดีครับ', m.Text__c);
    Assert.areEqual('Received', m.Status__c);
    Assert.areEqual('evt1', m.Webhook_Event_Id__c);
    Assert.areEqual('evt1m', m.Line_Message_Id__c);
    Assert.isNotNull(m.Sent_At__c);
    Assert.areEqual(c.Last_Message_At__c, m.Sent_At__c);
  }

  @IsTest
  static void eventsRouteToTheReceivingOA() {
    sendToA(
      new List<String>{ LineTestFactory.textEvent(CUSTOMER, 'to A', 'evtA') }
    );
    LineTestFactory.deliver(
      LineTestFactory.BOT_B,
      LineTestFactory.SECRET_B,
      new List<String>{ LineTestFactory.textEvent(CUSTOMER, 'to B', 'evtB') }
    );

    LINE_Conversation__c a = conversation(LineTestFactory.CHANNEL_A, CUSTOMER);
    LINE_Conversation__c b = conversation(LineTestFactory.CHANNEL_B, CUSTOMER);
    Assert.areEqual(oa(LineTestFactory.CHANNEL_A).Assigned_Rep__c, a.OwnerId);
    Assert.areEqual(oa(LineTestFactory.CHANNEL_B).Assigned_Rep__c, b.OwnerId);
    Assert.areNotEqual(
      a.OwnerId,
      b.OwnerId,
      'Same customer, separate conversation per OA'
    );
  }

  @IsTest
  static void redeliveryDoesNotDuplicateOrRecount() {
    String event = LineTestFactory.textEvent(CUSTOMER, 'once', 'evt1');
    sendToA(new List<String>{ event });
    sendToA(new List<String>{ event });
    sendToA(new List<String>{ event, event });

    Assert.areEqual(1, [SELECT COUNT() FROM LINE_Message__c]);
    Assert.areEqual(
      1,
      conversation(LineTestFactory.CHANNEL_A, CUSTOMER).Unread_Count__c
    );
  }

  @IsTest
  static void unreadCountAccumulates() {
    sendToA(
      new List<String>{ LineTestFactory.textEvent(CUSTOMER, 'one', 'evt1') }
    );
    sendToA(
      new List<String>{
        LineTestFactory.textEvent(CUSTOMER, 'two', 'evt2'),
        LineTestFactory.textEvent(CUSTOMER, 'three', 'evt3')
      }
    );

    LINE_Conversation__c c = conversation(LineTestFactory.CHANNEL_A, CUSTOMER);
    Assert.areEqual(3, c.Unread_Count__c);
    Assert.areEqual('three', c.Last_Message_Preview__c);
  }

  @IsTest
  static void groupRoomAndStandbyEventsAreIgnored() {
    sendToA(
      new List<String>{
        LineTestFactory.withSourceType(
          LineTestFactory.textEvent(CUSTOMER, 'group', 'evtG'),
          'group'
        ),
        LineTestFactory.withSourceType(
          LineTestFactory.textEvent(CUSTOMER, 'room', 'evtR'),
          'room'
        ),
        LineTestFactory.textEvent(CUSTOMER, 'standby', 'evtS')
          .replace('"mode":"active"', '"mode":"standby"'),
        '{"type":"postback","mode":"active","webhookEventId":"evtP","source":{"type":"user","userId":"U1"}}'
      }
    );
    Assert.areEqual(0, [SELECT COUNT() FROM LINE_Conversation__c]);
    Assert.areEqual(0, [SELECT COUNT() FROM LINE_Message__c]);
  }

  @IsTest
  static void nonTextMessagesAreStoredAsPlaceholders() {
    sendToA(
      new List<String>{
        LineTestFactory.rawMessageEvent(
          CUSTOMER,
          'evtImg',
          '{"id":"m1","type":"image","contentProvider":{"type":"line"}}'
        ),
        LineTestFactory.fileEvent(CUSTOMER, 'quote.pdf', 12345, 'evtFile'),
        LineTestFactory.rawMessageEvent(
          CUSTOMER,
          'evtStk',
          '{"id":"m3","type":"sticker","packageId":"446","stickerId":"1988"}'
        ),
        LineTestFactory.rawMessageEvent(
          CUSTOMER,
          'evtLoc',
          '{"id":"m4","type":"location","title":"Office","address":"Bangkok","latitude":13.75,"longitude":100.5}'
        ),
        LineTestFactory.rawMessageEvent(
          CUSTOMER,
          'evtX',
          '{"id":"m5","type":"somethingNew"}'
        )
      }
    );

    Map<String, LINE_Message__c> byEvent = new Map<String, LINE_Message__c>();
    for (LINE_Message__c m : [
      SELECT
        Webhook_Event_Id__c,
        Message_Type__c,
        File_Name__c,
        File_Size__c,
        Sticker_Package_Id__c,
        Sticker_Id__c,
        Location__c
      FROM LINE_Message__c
    ]) {
      byEvent.put(m.Webhook_Event_Id__c, m);
    }
    Assert.areEqual('image', byEvent.get('evtImg').Message_Type__c);
    Assert.areEqual('quote.pdf', byEvent.get('evtFile').File_Name__c);
    Assert.areEqual(12345, byEvent.get('evtFile').File_Size__c);
    Assert.areEqual('446', byEvent.get('evtStk').Sticker_Package_Id__c);
    Assert.areEqual('1988', byEvent.get('evtStk').Sticker_Id__c);
    Assert.areEqual(
      'Office, Bangkok (13.75,100.5)',
      byEvent.get('evtLoc').Location__c
    );
    Assert.areEqual('unsupported', byEvent.get('evtX').Message_Type__c);
    Assert.areEqual(
      5,
      conversation(LineTestFactory.CHANNEL_A, CUSTOMER).Unread_Count__c
    );
  }

  @IsTest
  static void previewsUseLabels() {
    LineWebhookModels.Message m = new LineWebhookModels.Message();
    for (
      String type : new List<String>{
        'image',
        'video',
        'audio',
        'sticker',
        'other'
      }
    ) {
      m.type = type;
      Assert.isTrue(LineInboundService.preview(m).startsWith('['), type);
    }
    m.type = 'file';
    m.fileName = 'a.pdf';
    Assert.isTrue(LineInboundService.preview(m).contains('a.pdf'));
    m.type = 'location';
    m.title = 'Office';
    Assert.isTrue(LineInboundService.preview(m).contains('Office'));
    Assert.areEqual(
      System.Label.LINE_Preview_Unsupported,
      LineInboundService.preview(null)
    );
    m.type = 'text';
    m.text = 'x'.repeat(300);
    Assert.areEqual(255, LineInboundService.preview(m).length());
  }

  // ---------- follow / unfollow ----------

  @IsTest
  static void followCreatesConversationAndQueuesProfile() {
    Test.setMock(HttpCalloutMock.class, new LineHttpMock());
    Test.startTest();
    sendToA(new List<String>{ LineTestFactory.followEvent(CUSTOMER, 'evtF') });
    Assert.areEqual(1, LineInboundService.lastResult.calloutItemsQueued);
    Test.stopTest();

    LINE_Conversation__c c = conversation(LineTestFactory.CHANNEL_A, CUSTOMER);
    Assert.areEqual('Following', c.Status__c);
    Assert.areEqual(0, c.Unread_Count__c);
    Assert.areEqual('Somchai', c.Name, 'Profile fetched by the queueable');
  }

  @IsTest
  static void unfollowThenRefollow() {
    sendToA(new List<String>{ LineTestFactory.followEvent(CUSTOMER, 'evt1') });
    sendToA(
      new List<String>{ LineTestFactory.unfollowEvent(CUSTOMER, 'evt2') }
    );
    Assert.areEqual(
      'Unfollowed',
      conversation(LineTestFactory.CHANNEL_A, CUSTOMER).Status__c
    );

    sendToA(new List<String>{ LineTestFactory.followEvent(CUSTOMER, 'evt3') });
    Assert.areEqual(
      'Following',
      conversation(LineTestFactory.CHANNEL_A, CUSTOMER).Status__c
    );
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM LINE_Conversation__c],
      'Same conversation throughout'
    );
  }

  @IsTest
  static void existingConversationMessageQueuesNoProfile() {
    sendToA(
      new List<String>{ LineTestFactory.textEvent(CUSTOMER, 'first', 'evt1') }
    );
    Assert.areEqual(
      1,
      LineInboundService.lastResult.calloutItemsQueued,
      'New conversation → profile'
    );

    sendToA(
      new List<String>{ LineTestFactory.textEvent(CUSTOMER, 'second', 'evt2') }
    );
    Assert.areEqual(
      0,
      LineInboundService.lastResult.calloutItemsQueued,
      'Known conversation → none'
    );
  }

  // ---------- owners and notifications ----------

  @IsTest
  static void notificationGoesToUserOwner() {
    sendToA(
      new List<String>{ LineTestFactory.textEvent(CUSTOMER, 'hi', 'evt1') }
    );
    Assert.areEqual(1, LineInboundService.lastResult.notificationsSent);

    sendToA(new List<String>{ LineTestFactory.followEvent('Uother', 'evtF') });
    Assert.areEqual(
      0,
      LineInboundService.lastResult.notificationsSent,
      'No message, no notification'
    );
  }

  @IsTest
  static void inactiveOAUsesFallbackUser() {
    LINE_OA_Configuration__c oaA = oa(LineTestFactory.CHANNEL_A);
    oaA.Is_Active__c = false;
    update oaA;
    insert new LINE_Settings__c(
      SetupOwnerId = UserInfo.getOrganizationId(),
      Fallback_Owner_Id__c = UserInfo.getUserId()
    );

    sendToA(
      new List<String>{ LineTestFactory.textEvent(CUSTOMER, 'hi', 'evt1') }
    );

    Assert.areEqual(
      UserInfo.getUserId(),
      conversation(LineTestFactory.CHANNEL_A, CUSTOMER).OwnerId
    );
  }

  @IsTest
  static void inactiveOAWithQueueFallbackSendsNoNotification() {
    Group queue = new Group(Name = 'LINE Fallback Test', Type = 'Queue');
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert queue;
      insert new QueueSobject(
        QueueId = queue.Id,
        SobjectType = LineNamespace.apiPrefix() + 'LINE_Conversation__c'
      );
    }
    LINE_OA_Configuration__c oaA = oa(LineTestFactory.CHANNEL_A);
    oaA.Is_Active__c = false;
    update oaA;
    insert new LINE_Settings__c(
      SetupOwnerId = UserInfo.getOrganizationId(),
      Fallback_Owner_Id__c = queue.Id
    );

    sendToA(
      new List<String>{ LineTestFactory.textEvent(CUSTOMER, 'hi', 'evt1') }
    );

    Assert.areEqual(
      queue.Id,
      conversation(LineTestFactory.CHANNEL_A, CUSTOMER).OwnerId
    );
    Assert.areEqual(
      0,
      LineInboundService.lastResult.notificationsSent,
      'Queues are not notified'
    );
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM LINE_Message__c],
      'Message still stored'
    );
  }

  @IsTest
  static void inactiveOAWithoutFallbackKeepsRep() {
    LINE_OA_Configuration__c oaA = oa(LineTestFactory.CHANNEL_A);
    oaA.Is_Active__c = false;
    update oaA;

    sendToA(
      new List<String>{ LineTestFactory.textEvent(CUSTOMER, 'hi', 'evt1') }
    );

    Assert.areEqual(
      oaA.Assigned_Rep__c,
      conversation(LineTestFactory.CHANNEL_A, CUSTOMER).OwnerId
    );
  }

  // ---------- visibility (acceptance criteria 1 and 4) ----------

  @IsTest
  static void repBCannotSeeRepAConversations() {
    sendToA(
      new List<String>{
        LineTestFactory.textEvent(CUSTOMER, 'private to A', 'evt1')
      }
    );
    User repA = new User(Id = oa(LineTestFactory.CHANNEL_A).Assigned_Rep__c);
    User repB = new User(Id = oa(LineTestFactory.CHANNEL_B).Assigned_Rep__c);

    System.runAs(repB) {
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM LINE_Conversation__c WITH USER_MODE]
      );
      Assert.areEqual(0, [SELECT COUNT() FROM LINE_Message__c WITH USER_MODE]);
    }
    System.runAs(repA) {
      Assert.areEqual(
        1,
        [SELECT COUNT() FROM LINE_Conversation__c WITH USER_MODE]
      );
      Assert.areEqual(1, [SELECT COUNT() FROM LINE_Message__c WITH USER_MODE]);
    }
  }

  // ---------- bulk ----------

  @IsTest
  static void twoHundredEventsInOneBatch() {
    List<String> events = new List<String>();
    for (Integer i = 0; i < 200; i++) {
      events.add(
        LineTestFactory.textEvent('Ubulk' + i, 'message ' + i, 'bulk' + i)
      );
    }
    Test.setMock(HttpCalloutMock.class, new LineHttpMock());

    Test.startTest();
    Integer status = sendToA(events);
    Test.stopTest();

    Assert.areEqual(200, status);
    Assert.areEqual(200, [SELECT COUNT() FROM LINE_Conversation__c]);
    Assert.areEqual(200, [SELECT COUNT() FROM LINE_Message__c]);
    Assert.areEqual(
      LineInboundService.MAX_NOTIFICATIONS_PER_BATCH,
      LineInboundService.lastResult.notificationsSent
    );
  }

  @IsTest
  static void unparsableEventIsLoggedAndSkipped() {
    LINE_OA_Configuration__c oaA = oa(LineTestFactory.CHANNEL_A);
    LineInboundService.Result result = LineInboundService.process(
      new List<LINE_Webhook_Event__e>{
        new LINE_Webhook_Event__e(
          OA_Configuration_Id__c = oaA.Id,
          Webhook_Event_Id__c = 'bad',
          Event_Json__c = '{not json'
        ),
        new LINE_Webhook_Event__e(
          OA_Configuration_Id__c = 'not-an-id',
          Webhook_Event_Id__c = 'x',
          Event_Json__c = '{}'
        )
      }
    );
    LineLogger.flush();

    Assert.areEqual(0, result.eventsHandled);
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM LINE_Error_Log__c
        WHERE Source__c = 'LineInboundService.parse'
      ]
    );
  }
}
