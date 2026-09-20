@IsTest
private class LineWebhookResourceTest {
  @TestSetup
  static void setup() {
    LineTestFactory.createOA(
      LineTestFactory.CHANNEL_A,
      LineTestFactory.BOT_A,
      LineTestFactory.SECRET_A,
      UserInfo.getUserId()
    );
  }

  private static String body() {
    return LineTestFactory.webhookBody(
      LineTestFactory.BOT_A,
      new List<String>{
        LineTestFactory.textEvent('Ucustomer1', 'hello', 'evt1')
      }
    );
  }

  private static Integer storedMessages() {
    return [SELECT COUNT() FROM LINE_Message__c];
  }

  @IsTest
  static void validSignaturePublishesAndStores() {
    Integer status = LineTestFactory.callWebhook(
      body(),
      LineTestFactory.SECRET_A
    );
    Test.getEventBus().deliver();

    Assert.areEqual(200, status);
    Assert.areEqual(1, storedMessages());
  }

  @IsTest
  static void wrongSignatureIs401AndStoresNothing() {
    Integer status = LineTestFactory.callWebhook(
      body(),
      LineTestFactory.SECRET_B
    );
    Test.getEventBus().deliver();

    Assert.areEqual(401, status);
    Assert.areEqual(0, storedMessages());
    Assert.areEqual(0, [SELECT COUNT() FROM LINE_Conversation__c]);
  }

  @IsTest
  static void missingSignatureIs401() {
    Integer status = LineTestFactory.callWebhook(body(), null);
    Test.getEventBus().deliver();

    Assert.areEqual(401, status);
    Assert.areEqual(0, storedMessages());
  }

  @IsTest
  static void lowercaseHeaderNameIsAccepted() {
    String raw = body();
    RestRequest req = new RestRequest();
    req.httpMethod = 'POST';
    req.requestBody = Blob.valueOf(raw);
    req.addHeader(
      'x-line-signature',
      LineTestFactory.sign(raw, LineTestFactory.SECRET_A)
    );
    RestContext.request = req;
    RestContext.response = new RestResponse();

    LineWebhookResource.handlePost();
    Test.getEventBus().deliver();

    Assert.areEqual(200, RestContext.response.statusCode);
    Assert.areEqual(1, storedMessages());
  }

  @IsTest
  static void unknownDestinationIs403() {
    String raw = LineTestFactory.webhookBody(
      'Uunknown',
      new List<String>{
        LineTestFactory.textEvent('Ucustomer1', 'hello', 'evt1')
      }
    );
    Assert.areEqual(
      403,
      LineTestFactory.callWebhook(raw, LineTestFactory.SECRET_A)
    );
  }

  @IsTest
  static void emptyEventsIs200() {
    String raw = LineTestFactory.webhookBody(
      LineTestFactory.BOT_A,
      new List<String>()
    );
    Assert.areEqual(
      200,
      LineTestFactory.callWebhook(raw, LineTestFactory.SECRET_A)
    );
  }

  @IsTest
  static void malformedOrMissingDestinationIs400() {
    Assert.areEqual(
      400,
      LineTestFactory.callWebhook('not json', LineTestFactory.SECRET_A)
    );
    Assert.areEqual(
      400,
      LineTestFactory.callWebhook('{"events":[]}', LineTestFactory.SECRET_A)
    );
    Assert.areEqual(
      400,
      LineTestFactory.callWebhook('[1,2]', LineTestFactory.SECRET_A)
    );
    Assert.areEqual(
      400,
      LineTestFactory.callWebhook(
        '{"destination":123}',
        LineTestFactory.SECRET_A
      )
    );
    Assert.areEqual(
      400,
      LineTestFactory.callWebhook('', LineTestFactory.SECRET_A)
    );
  }

  @IsTest
  static void destinationAfterNestedObjectsIsFound() {
    Assert.areEqual(
      'Ubot_a',
      LineWebhookResource.readDestination(
        '{"events":[{"a":{"destination":"nested"}}],"destination":"Ubot_a"}'
      )
    );
  }

  @IsTest
  static void manyEventsInOneBody() {
    List<String> events = new List<String>();
    for (Integer i = 0; i < 5; i++) {
      events.add(
        LineTestFactory.textEvent('Ucustomer' + i, 'hi ' + i, 'evt' + i)
      );
    }
    Integer status = LineTestFactory.deliver(
      LineTestFactory.BOT_A,
      LineTestFactory.SECRET_A,
      events
    );

    Assert.areEqual(200, status);
    Assert.areEqual(5, storedMessages());
    Assert.areEqual(5, [SELECT COUNT() FROM LINE_Conversation__c]);
  }

  @IsTest
  static void missingRequestIs400() {
    RestContext.request = null;
    RestContext.response = new RestResponse();
    LineWebhookResource.handlePost();
    Assert.areEqual(
      400,
      RestContext.response.statusCode,
      'No request body is rejected, not a crash'
    );
  }
}
