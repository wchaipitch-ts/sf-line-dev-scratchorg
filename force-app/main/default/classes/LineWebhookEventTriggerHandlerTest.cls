@IsTest
private class LineWebhookEventTriggerHandlerTest {
  private static LineWebhookEventTriggerHandler handler(Integer retries) {
    LineWebhookEventTriggerHandler h = new LineWebhookEventTriggerHandler(
      new List<LINE_Webhook_Event__e>(),
      retries
    );
    h.operationOverride = TriggerOperation.AFTER_INSERT;
    return h;
  }

  @IsTest
  static void transientErrorIsRetried() {
    LineWebhookEventTriggerHandler.testException = LineApiException.create(
      503,
      'Unavailable',
      null,
      false
    );
    try {
      handler(0).run();
      Assert.fail('Expected RetryableException');
    } catch (EventBus.RetryableException e) {
      Assert.isTrue(e.getMessage().contains('503'));
    }
  }

  @IsTest
  static void transientErrorAfterMaxRetriesIsLogged() {
    LineWebhookEventTriggerHandler.testException = new DmlException(
      'UNABLE_TO_LOCK_ROW, unable to obtain exclusive access'
    );
    handler(LineWebhookEventTriggerHandler.MAX_RETRIES).run();

    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM LINE_Error_Log__c
        WHERE Source__c = 'LineWebhookEventTriggerHandler.afterInsert'
      ]
    );
  }

  @IsTest
  static void permanentErrorIsLoggedNotRetried() {
    LineWebhookEventTriggerHandler.testException = new NullPointerException();
    handler(0).run();

    Assert.areEqual(1, [SELECT COUNT() FROM LINE_Error_Log__c]);
  }

  @IsTest
  static void transientClassification() {
    Assert.isTrue(
      LineWebhookEventTriggerHandler.isTransient(
        LineApiException.create(429, 'Too many', null, false)
      )
    );
    Assert.isFalse(
      LineWebhookEventTriggerHandler.isTransient(
        LineApiException.create(400, 'Bad', null, false)
      )
    );
    Assert.isTrue(
      LineWebhookEventTriggerHandler.isTransient(
        new DmlException('UNABLE_TO_LOCK_ROW')
      )
    );
    Assert.isFalse(
      LineWebhookEventTriggerHandler.isTransient(
        new DmlException('REQUIRED_FIELD_MISSING')
      )
    );
  }

  @IsTest
  static void emptyBatchDoesNothing() {
    handler(0).run();
    Assert.areEqual(0, [SELECT COUNT() FROM LINE_Error_Log__c]);
  }
}
