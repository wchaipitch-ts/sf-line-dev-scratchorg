@IsTest
private class LineOutboundServiceTest {
  @TestSetup
  static void setup() {
    LINE_OA_Configuration__c oa = LineTestFactory.createOA(
      LineTestFactory.CHANNEL_A,
      LineTestFactory.BOT_A,
      LineTestFactory.SECRET_A,
      UserInfo.getUserId()
    );
    insert new LINE_Conversation__c(
      Name = 'Somchai',
      LINE_OA_Configuration__c = oa.Id,
      LINE_User_Id__c = 'Ucustomer1',
      Unique_Key__c = LineTestFactory.CHANNEL_A + ':Ucustomer1',
      Status__c = 'Following'
    );
  }

  private static Id conversationId() {
    return [SELECT Id FROM LINE_Conversation__c LIMIT 1].Id;
  }

  private static LINE_Message__c storedMessage() {
    return [
      SELECT
        Direction__c,
        Message_Type__c,
        Text__c,
        Status__c,
        Error__c,
        Sender__c,
        Line_Message_Id__c,
        Sent_At__c
      FROM LINE_Message__c
    ];
  }

  @IsTest
  static void sendStoresSentMessageAndUpdatesConversation() {
    LineHttpMock mock = new LineHttpMock();
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    LINE_Message__c result = LineOutboundService.sendText(
      conversationId(),
      'สวัสดีครับ'
    );
    Test.stopTest();

    LINE_Message__c m = storedMessage();
    Assert.areEqual(result.Id, m.Id);
    Assert.areEqual('Outbound', m.Direction__c);
    Assert.areEqual('text', m.Message_Type__c);
    Assert.areEqual('สวัสดีครับ', m.Text__c);
    Assert.areEqual('Sent', m.Status__c);
    Assert.areEqual(UserInfo.getUserId(), m.Sender__c, 'Sender is recorded');
    Assert.areEqual('461230966842064897', m.Line_Message_Id__c);
    Assert.isNull(m.Error__c);

    LINE_Conversation__c c = [
      SELECT Last_Message_At__c, Last_Message_Preview__c, Unread_Count__c
      FROM LINE_Conversation__c
    ];
    Assert.areEqual(m.Sent_At__c, c.Last_Message_At__c);
    Assert.areEqual('สวัสดีครับ', c.Last_Message_Preview__c);
    Assert.areEqual(
      0,
      c.Unread_Count__c,
      'Outbound never changes the unread count'
    );

    Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
      mock.requestsTo('/message/push')[0].getBody()
    );
    Assert.areEqual(
      'Ucustomer1',
      body.get('to'),
      'Sent to the conversation customer'
    );
  }

  @IsTest
  static void monthlyLimitStoresFailedMessageWithReadableError() {
    LineHttpMock mock = new LineHttpMock();
    mock.stub(
      'POST',
      '/v2/bot/message/push',
      429,
      '{"message":"You have reached your monthly limit."}'
    );
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    try {
      LineOutboundService.sendText(conversationId(), 'over quota');
      Assert.fail('Expected LineApiException');
    } catch (LineApiException e) {
      Assert.isTrue(e.isMonthlyLimit());
    }
    Test.stopTest();

    LINE_Message__c m = storedMessage();
    Assert.areEqual('Failed', m.Status__c, 'The attempt is still recorded');
    Assert.areEqual(System.Label.LINE_Error_Monthly_Limit, m.Error__c);
    Assert.areEqual('over quota', m.Text__c);

    Assert.isNull(
      [SELECT Last_Message_At__c FROM LINE_Conversation__c].Last_Message_At__c,
      'A failed send does not move the conversation'
    );
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM LINE_Error_Log__c
        WHERE Source__c = 'LineOutboundService.sendText'
      ]
    );
  }

  @IsTest
  static void retryKeyConflictCountsAsSent() {
    LineHttpMock mock = new LineHttpMock();
    mock.stub(
      'POST',
      '/v2/bot/message/push',
      409,
      '{"message":"The retry key is already accepted","sentMessages":[{"id":"999"}]}'
    );
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    LineOutboundService.sendText(conversationId(), 'duplicate send');
    Test.stopTest();

    LINE_Message__c m = storedMessage();
    Assert.areEqual('Sent', m.Status__c);
    Assert.areEqual('999', m.Line_Message_Id__c);
  }

  @IsTest
  static void badCredentialsStoreFailedMessage() {
    LineHttpMock mock = new LineHttpMock();
    mock.stub(
      'POST',
      '/oauth2/v3/token',
      400,
      '{"error":"invalid_client","error_description":"invalid client"}'
    );
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    try {
      LineOutboundService.sendText(conversationId(), 'no token');
      Assert.fail('Expected LineApiException');
    } catch (LineApiException e) {
      Assert.isTrue(e.isCredentialError());
    }
    Test.stopTest();

    Assert.areEqual(
      System.Label.LINE_Error_Credentials_Invalid,
      storedMessage().Error__c
    );
  }

  @IsTest
  static void textIsValidatedBeforeAnyCallout() {
    LineHttpMock mock = new LineHttpMock();
    Test.setMock(HttpCalloutMock.class, mock);
    Id conversationId = conversationId();

    for (String text : new List<String>{ null, '', '   ' }) {
      try {
        LineOutboundService.sendText(conversationId, text);
        Assert.fail('Expected IllegalArgumentException');
      } catch (IllegalArgumentException e) {
        Assert.areEqual(System.Label.LINE_Error_Message_Empty, e.getMessage());
      }
    }
    try {
      LineOutboundService.sendText(
        conversationId,
        'x'.repeat(LineOutboundService.MAX_TEXT_LENGTH + 1)
      );
      Assert.fail('Expected IllegalArgumentException');
    } catch (IllegalArgumentException e) {
      Assert.isTrue(e.getMessage().contains('5000'), e.getMessage());
    }

    Assert.areEqual(0, mock.requests.size(), 'No callout for invalid input');
    Assert.areEqual(0, [SELECT COUNT() FROM LINE_Message__c]);
  }

  @IsTest
  static void maximumLengthTextIsAccepted() {
    Test.setMock(HttpCalloutMock.class, new LineHttpMock());
    Test.startTest();
    LineOutboundService.sendText(
      conversationId(),
      'x'.repeat(LineOutboundService.MAX_TEXT_LENGTH)
    );
    Test.stopTest();

    Assert.areEqual(5000, storedMessage().Text__c.length());
  }

  @IsTest
  static void missingConversationIsRejected() {
    Test.setMock(HttpCalloutMock.class, new LineHttpMock());
    Id conversationId = conversationId();
    delete [SELECT Id FROM LINE_Conversation__c];

    try {
      LineOutboundService.sendText(conversationId, 'gone');
      Assert.fail('Expected IllegalArgumentException');
    } catch (IllegalArgumentException e) {
      Assert.areEqual(System.Label.LINE_Error_Generic, e.getMessage());
    }
  }
}
