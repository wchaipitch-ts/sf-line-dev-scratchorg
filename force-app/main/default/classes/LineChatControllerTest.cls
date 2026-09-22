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
