@IsTest
private class LineChatControllerTest {
  @TestSetup
  static void setup() {
    User repA = LineTestFactory.createUser(
      new List<String>{ 'LINE_Chat_User' }
    );
    User repB = LineTestFactory.createUser(
      new List<String>{ 'LINE_Chat_User' }
    );
    LINE_OA_Configuration__c oa = LineTestFactory.createOA(
      LineTestFactory.CHANNEL_A,
      LineTestFactory.BOT_A,
      LineTestFactory.SECRET_A,
      repA.Id
    );
    insert new LINE_Conversation__c(
      Name = 'Somchai',
      LINE_OA_Configuration__c = oa.Id,
      LINE_User_Id__c = 'Ucustomer1',
      Unique_Key__c = LineTestFactory.CHANNEL_A + ':Ucustomer1',
      Status__c = 'Following',
      OwnerId = repA.Id
    );
    Assert.areNotEqual(null, repB.Id);
  }

  private static User repA() {
    return [
      SELECT Id
      FROM User
      WHERE Id IN (SELECT Assigned_Rep__c FROM LINE_OA_Configuration__c)
      LIMIT 1
    ];
  }

  private static User repB() {
    return [
      SELECT Id
      FROM User
      WHERE
        Username LIKE 'line.test.%'
        AND Id NOT IN (SELECT Assigned_Rep__c FROM LINE_OA_Configuration__c)
      LIMIT 1
    ];
  }

  private static Id conversationId() {
    return [SELECT Id FROM LINE_Conversation__c LIMIT 1].Id;
  }

  // Links the conversation to a Contact and gives the Contact a primary OA, as linking does in M6.
  private static Contact linkContact(Boolean withPrimaryOa) {
    LINE_Conversation__c c = [
      SELECT Id, Contact__c, LINE_OA_Configuration__c
      FROM LINE_Conversation__c
    ];
    // Owned by the rep: the panel only opens on a Contact the rep can already see.
    Contact contact = new Contact(LastName = 'Somchai', OwnerId = repA().Id);
    if (withPrimaryOa) {
      contact.LINE_OA_Configuration__c = c.LINE_OA_Configuration__c;
    }
    insert contact;
    c.Contact__c = contact.Id;
    update c;
    return contact;
  }

  private static List<LINE_Message__c> insertMessages(
    Id conversationId,
    Integer count
  ) {
    List<LINE_Message__c> messages = new List<LINE_Message__c>();
    Datetime base = Datetime.newInstance(2026, 9, 1, 8, 0, 0);
    for (Integer i = 0; i < count; i++) {
      messages.add(
        new LINE_Message__c(
          LINE_Conversation__c = conversationId,
          Direction__c = 'Inbound',
          Message_Type__c = 'text',
          Text__c = 'message ' + i,
          Status__c = 'Received',
          Webhook_Event_Id__c = 'evt' + i,
          Sent_At__c = base.addMinutes(i)
        )
      );
    }
    insert messages;
    return messages;
  }

  // ---------- getConversations ----------

  @IsTest
  static void conversationsOfAContactAreReturnedToItsRep() {
    Contact contact = linkContact(true);

    Test.startTest();
    List<LineChatController.ConversationView> views;
    System.runAs(repA()) {
      views = LineChatController.getConversations(contact.Id);
    }
    Test.stopTest();

    Assert.isNull(
      LineChatController.lastUnexpectedError,
      'Nothing should be swallowed as a generic error'
    );
    Assert.areEqual(1, views.size());
    LineChatController.ConversationView v = views[0];
    Assert.areEqual(conversationId(), v.id);
    Assert.areEqual('Somchai', v.name);
    Assert.areEqual('Following', v.status);
    Assert.areEqual(0, v.unreadCount);
    Assert.isTrue(v.isPrimaryOa, 'This OA is the Contact primary OA');
    Assert.isNotNull(v.oaName);
  }

  @IsTest
  static void primaryOaConversationComesFirst() {
    Contact contact = linkContact(false);
    LINE_Conversation__c first = [
      SELECT Id, LINE_OA_Configuration__c
      FROM LINE_Conversation__c
    ];
    // A second OA, whose conversation is newer, but is the Contact's primary one.
    LINE_OA_Configuration__c oaB = LineTestFactory.createOA(
      LineTestFactory.CHANNEL_B,
      LineTestFactory.BOT_B,
      LineTestFactory.SECRET_B,
      repA().Id
    );
    insert new LINE_Conversation__c(
      Name = 'Somchai via B',
      LINE_OA_Configuration__c = oaB.Id,
      LINE_User_Id__c = 'Ucustomer1',
      Unique_Key__c = LineTestFactory.CHANNEL_B + ':Ucustomer1',
      Contact__c = contact.Id,
      OwnerId = repA().Id,
      Last_Message_At__c = Datetime.now()
    );
    update new Contact(
      Id = contact.Id,
      LINE_OA_Configuration__c = first.LINE_OA_Configuration__c
    );

    Test.startTest();
    List<LineChatController.ConversationView> views;
    System.runAs(repA()) {
      views = LineChatController.getConversations(contact.Id);
    }
    Test.stopTest();

    Assert.areEqual(2, views.size());
    Assert.isTrue(views[0].isPrimaryOa, 'Primary OA opens first');
    Assert.areEqual(first.Id, views[0].id);
  }

  @IsTest
  static void otherRepSeesNoConversations() {
    Contact contact = linkContact(true);

    Test.startTest();
    List<LineChatController.ConversationView> views;
    System.runAs(repB()) {
      views = LineChatController.getConversations(contact.Id);
    }
    Test.stopTest();

    Assert.isTrue(views.isEmpty(), 'Sharing hides Rep A conversations');
  }

  @IsTest
  static void nullContactReturnsEmptyList() {
    System.runAs(repA()) {
      Assert.isTrue(LineChatController.getConversations(null).isEmpty());
    }
  }

  // ---------- getMessages ----------

  @IsTest
  static void messagesComeBackOldestFirstWithPaging() {
    Id conversationId = conversationId();
    insertMessages(conversationId, 5);

    Test.startTest();
    LineChatController.MessagePage page;
    LineChatController.MessagePage older;
    System.runAs(repA()) {
      page = LineChatController.getMessages(conversationId, null, null, 3);
      older = LineChatController.getMessages(
        conversationId,
        page.messages[0].sentAt,
        page.messages[0].id,
        3
      );
    }
    Test.stopTest();

    Assert.areEqual(3, page.messages.size());
    Assert.isTrue(page.hasMore, 'Two older messages remain');
    Assert.areEqual(
      'message 2',
      page.messages[0].text,
      'Oldest of the page first'
    );
    Assert.areEqual('message 4', page.messages[2].text, 'Newest last');

    Assert.areEqual(2, older.messages.size());
    Assert.isFalse(older.hasMore);
    Assert.areEqual('message 0', older.messages[0].text);
    Assert.areEqual('message 1', older.messages[1].text);
  }

  @IsTest
  static void pageSizeIsCapped() {
    Id conversationId = conversationId();
    insertMessages(conversationId, 3);

    System.runAs(repA()) {
      Assert.areEqual(
        3,
        LineChatController.getMessages(conversationId, null, null, 999)
          .messages.size()
      );
      Assert.areEqual(
        3,
        LineChatController.getMessages(conversationId, null, null, null)
          .messages.size()
      );
    }
  }

  @IsTest
  static void messageViewCarriesDisplayFields() {
    Id conversationId = conversationId();
    insert new LINE_Message__c(
      LINE_Conversation__c = conversationId,
      Direction__c = 'Inbound',
      Message_Type__c = 'file',
      Status__c = 'Received',
      File_Name__c = 'quote.pdf',
      File_Size__c = 2048,
      Sent_At__c = Datetime.now()
    );

    LineChatController.MessageView view;
    System.runAs(repA()) {
      view = LineChatController.getMessages(conversationId, null, null, 10)
        .messages[0];
    }

    Assert.areEqual('file', view.messageType);
    Assert.areEqual('quote.pdf', view.fileName);
    Assert.areEqual(2048, view.fileSize);
    Assert.isFalse(view.isOutbound);
  }

  @IsTest
  static void otherRepCannotReadMessages() {
    Id conversationId = conversationId();
    insertMessages(conversationId, 2);

    System.runAs(repB()) {
      try {
        LineChatController.getMessages(conversationId, null, null, 10);
        Assert.fail('Expected AuraHandledException');
      } catch (AuraHandledException e) {
        Assert.areEqual(System.Label.LINE_Error_No_Access, e.getMessage());
      }
    }
  }

  // ---------- getMessagesSince ----------

  @IsTest
  static void pollReturnsOnlyNewerMessages() {
    Id conversationId = conversationId();
    List<LINE_Message__c> all = insertMessages(conversationId, 4);
    LINE_Message__c third = [
      SELECT Id, Sent_At__c
      FROM LINE_Message__c
      WHERE Webhook_Event_Id__c = 'evt2'
    ];

    Test.startTest();
    List<LineChatController.MessageView> since;
    List<LineChatController.MessageView> everything = new List<LineChatController.MessageView>();
    System.runAs(repA()) {
      since = LineChatController.getMessagesSince(
        conversationId,
        third.Sent_At__c,
        third.Id
      );
      everything = LineChatController.getMessagesSince(
        conversationId,
        null,
        null
      );
    }
    Test.stopTest();

    Assert.areEqual(1, since.size(), 'Only the message after the marker');
    Assert.areEqual('message 3', since[0].text);
    Assert.areEqual(4, everything.size(), 'No marker returns everything');
    Assert.areEqual('message 0', everything[0].text, 'Oldest first');
  }

  @IsTest
  static void pollOnAnotherRepConversationIsRefused() {
    Id conversationId = conversationId();
    System.runAs(repB()) {
      try {
        LineChatController.getMessagesSince(conversationId, null, null);
        Assert.fail('Expected AuraHandledException');
      } catch (AuraHandledException e) {
        Assert.areEqual(System.Label.LINE_Error_No_Access, e.getMessage());
      }
    }
  }

  // ---------- markRead and settings ----------

  @IsTest
  static void markReadClearsUnreadCount() {
    LINE_Conversation__c c = [
      SELECT Id, Unread_Count__c
      FROM LINE_Conversation__c
    ];
    c.Unread_Count__c = 4;
    update c;

    Test.startTest();
    System.runAs(repA()) {
      Assert.areEqual(0, LineChatController.markRead(c.Id));
    }
    Test.stopTest();

    Assert.areEqual(
      0,
      [SELECT Unread_Count__c FROM LINE_Conversation__c].Unread_Count__c
    );
  }

  @IsTest
  static void markReadOnAnotherRepConversationIsRefused() {
    Id conversationId = conversationId();
    System.runAs(repB()) {
      try {
        LineChatController.markRead(conversationId);
        Assert.fail('Expected AuraHandledException');
      } catch (AuraHandledException e) {
        Assert.areEqual(System.Label.LINE_Error_No_Access, e.getMessage());
      }
    }
    Assert.areEqual(
      0,
      [SELECT Unread_Count__c FROM LINE_Conversation__c].Unread_Count__c
    );
  }

  @IsTest
  static void pollIntervalComesFromSettings() {
    System.runAs(repA()) {
      Assert.areEqual(5, LineChatController.getPollIntervalSeconds());
    }
    insert new LINE_Settings__c(
      SetupOwnerId = UserInfo.getOrganizationId(),
      Poll_Interval_Seconds__c = 9
    );
    LineSettings.reset();
    System.runAs(repA()) {
      Assert.areEqual(9, LineChatController.getPollIntervalSeconds());
    }
  }

  @IsTest
  static void ownerCanSendAndGetsMessageBack() {
    Test.setMock(HttpCalloutMock.class, new LineHttpMock());
    Id conversationId = conversationId();

    Test.startTest();
    LineChatController.MessageView view;
    System.runAs(repA()) {
      view = LineChatController.sendText(
        conversationId,
        'Hello from Salesforce'
      );
    }
    Test.stopTest();

    Assert.areEqual('Outbound', view.direction);
    Assert.areEqual('text', view.messageType);
    Assert.areEqual('Hello from Salesforce', view.text);
    Assert.areEqual('Sent', view.status);
    Assert.areEqual(repA().Id, view.senderId);
    Assert.isNotNull(view.id);
    Assert.isNull(view.errorMessage);
    Assert.areEqual(1, [SELECT COUNT() FROM LINE_Message__c]);
  }

  @IsTest
  static void otherRepCannotSend() {
    Test.setMock(HttpCalloutMock.class, new LineHttpMock());
    Id conversationId = conversationId();

    Test.startTest();
    System.runAs(repB()) {
      try {
        LineChatController.sendText(conversationId, 'not my conversation');
        Assert.fail('Expected AuraHandledException');
      } catch (AuraHandledException e) {
        Assert.areEqual(System.Label.LINE_Error_No_Access, e.getMessage());
      }
    }
    Test.stopTest();

    Assert.areEqual(
      0,
      [SELECT COUNT() FROM LINE_Message__c],
      'Nothing sent or stored'
    );
  }

  @IsTest
  static void nullConversationIsRefused() {
    System.runAs(repA()) {
      try {
        LineChatController.sendText(null, 'nowhere');
        Assert.fail('Expected AuraHandledException');
      } catch (AuraHandledException e) {
        Assert.areEqual(System.Label.LINE_Error_No_Access, e.getMessage());
      }
    }
  }

  @IsTest
  static void unfollowedConversationIsRefusedBeforeSending() {
    LineHttpMock mock = new LineHttpMock();
    Test.setMock(HttpCalloutMock.class, mock);
    LINE_Conversation__c c = [SELECT Id, Status__c FROM LINE_Conversation__c];
    c.Status__c = 'Unfollowed';
    update c;

    System.runAs(repA()) {
      try {
        LineChatController.sendText(c.Id, 'are you there?');
        Assert.fail('Expected AuraHandledException');
      } catch (AuraHandledException e) {
        Assert.areEqual(
          System.Label.LINE_Error_Conversation_Inactive,
          e.getMessage()
        );
      }
    }
    Assert.areEqual(0, mock.requests.size(), 'No callout to LINE');
  }

  @IsTest
  static void invalidTextIsRefusedWithLabel() {
    Test.setMock(HttpCalloutMock.class, new LineHttpMock());
    Id conversationId = conversationId();

    System.runAs(repA()) {
      try {
        LineChatController.sendText(conversationId, '  ');
        Assert.fail('Expected AuraHandledException');
      } catch (AuraHandledException e) {
        Assert.areEqual(System.Label.LINE_Error_Message_Empty, e.getMessage());
      }
    }
  }

  @IsTest
  static void lineErrorReachesTheRepReadably() {
    LineHttpMock mock = new LineHttpMock();
    mock.stub(
      'POST',
      '/v2/bot/message/push',
      429,
      '{"message":"You have reached your monthly limit."}'
    );
    Test.setMock(HttpCalloutMock.class, mock);
    Id conversationId = conversationId();

    Test.startTest();
    System.runAs(repA()) {
      try {
        LineChatController.sendText(conversationId, 'over quota');
        Assert.fail('Expected AuraHandledException');
      } catch (AuraHandledException e) {
        Assert.areEqual(System.Label.LINE_Error_Monthly_Limit, e.getMessage());
      }
    }
    Test.stopTest();

    Assert.areEqual(
      'Failed',
      [SELECT Status__c FROM LINE_Message__c].Status__c,
      'The failed attempt is visible to the rep'
    );
  }

  @IsTest
  static void viewCarriesNoSecrets() {
    Test.setMock(HttpCalloutMock.class, new LineHttpMock());
    Id conversationId = conversationId();

    Test.startTest();
    LineChatController.MessageView view;
    System.runAs(repA()) {
      view = LineChatController.sendText(conversationId, 'hello');
    }
    Test.stopTest();

    String serialized = JSON.serialize(view);
    Assert.isFalse(serialized.contains(LineTestFactory.SECRET_A));
    Assert.isFalse(serialized.contains(LineHttpMock.FAKE_TOKEN));
    Assert.isFalse(serialized.contains(LineTestFactory.CHANNEL_A));
  }
}
