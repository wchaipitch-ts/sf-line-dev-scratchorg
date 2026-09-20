@IsTest
private class LineLoggerTest {
  @IsTest
  static void bufferedUntilFlush() {
    LineLogger.error('LineLoggerTest.one', new DmlException('boom'));
    LineLogger.error('LineLoggerTest.two', 'plain message', null, null);

    Assert.areEqual(2, LineLogger.pendingCount());
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM LINE_Error_Log__c],
      'Nothing written before flush'
    );

    LineLogger.flush();

    Assert.areEqual(0, LineLogger.pendingCount());
    List<LINE_Error_Log__c> logs = [
      SELECT Source__c, Message__c
      FROM LINE_Error_Log__c
      ORDER BY Source__c
    ];
    Assert.areEqual(2, logs.size());
    Assert.areEqual('LineLoggerTest.one', logs[0].Source__c);
    Assert.isTrue(logs[0].Message__c.contains('boom'));
    Assert.areEqual('plain message', logs[1].Message__c);
  }

  @IsTest
  static void recordsHttpStatusAndContext() {
    LINE_OA_Configuration__c oa = LineTestFactory.newOAConfig(
      '1000000001',
      'Ubot_a',
      UserInfo.getUserId()
    );
    insert oa;

    LineLogger.error(
      'LineApiClient.push',
      LineApiException.create(
        429,
        'You have reached your monthly limit.',
        null,
        false
      ),
      oa.Id,
      oa.Id
    );
    LineLogger.flush();

    LINE_Error_Log__c log = [
      SELECT
        Http_Status__c,
        LINE_OA_Configuration__c,
        Related_Record_Id__c,
        Stack_Trace__c
      FROM LINE_Error_Log__c
    ];
    Assert.areEqual(429, log.Http_Status__c);
    Assert.areEqual(oa.Id, log.LINE_OA_Configuration__c);
    Assert.areEqual(oa.Id, log.Related_Record_Id__c);
  }

  @IsTest
  static void truncatesLongValues() {
    LineLogger.error('S'.repeat(150), 'M'.repeat(40000), null, null);
    LineLogger.flush();

    LINE_Error_Log__c log = [
      SELECT Source__c, Message__c
      FROM LINE_Error_Log__c
    ];
    Assert.areEqual(100, log.Source__c.length());
    Assert.areEqual(32000, log.Message__c.length());
  }

  @IsTest
  static void masksAnythingLookingLikeASecret() {
    String scrubbed = LineLogger.scrub(
      'Authorization: Bearer abc.def-123 body client_secret=s3cr3t&x=1 {"access_token":"tok123","channelSecret":"zzz"}'
    );
    Assert.isFalse(scrubbed.contains('abc.def-123'));
    Assert.isFalse(scrubbed.contains('s3cr3t'));
    Assert.isFalse(scrubbed.contains('tok123'));
    Assert.isFalse(scrubbed.contains('zzz'));
    Assert.isTrue(scrubbed.contains('Bearer ***'));
  }

  @IsTest
  static void logsPartialSaveFailures() {
    // Missing LastName always fails, whatever the subscriber's own rules are.
    List<Contact> contacts = new List<Contact>{ new Contact() };
    List<Database.SaveResult> results = Database.insert(contacts, false);

    LineLogger.saveErrors('LineLoggerTest.save', results, contacts);
    LineLogger.flush();

    LINE_Error_Log__c log = [
      SELECT Message__c, Source__c
      FROM LINE_Error_Log__c
    ];
    Assert.areEqual('LineLoggerTest.save', log.Source__c);
    Assert.isTrue(
      log.Message__c.contains('REQUIRED_FIELD_MISSING'),
      log.Message__c
    );
  }

  @IsTest
  static void bufferIsBounded() {
    for (Integer i = 0; i < LineLogger.MAX_BUFFERED + 10; i++) {
      LineLogger.error('LineLoggerTest.bounded', 'entry ' + i, null, null);
    }
    Assert.areEqual(LineLogger.MAX_BUFFERED, LineLogger.pendingCount());
  }

  @IsTest
  static void flushNeverThrows() {
    LineLogger.error('LineLoggerTest.fail', 'will not be saved', null, null);
    LineLogger.forceFlushFailure = true;

    LineLogger.flush();

    Assert.areEqual(0, LineLogger.pendingCount());
    Assert.areEqual(0, [SELECT COUNT() FROM LINE_Error_Log__c]);
    LineLogger.flush();
  }

  @IsTest
  static void nullExceptionIsSafe() {
    LineLogger.error('LineLoggerTest.null', (Exception) null);
    Assert.areEqual(1, LineLogger.pendingCount());
  }

  @IsTest
  static void repWithoutLogAccessCanStillLog() {
    User rep = LineTestFactory.createUser(new List<String>{ 'LINE_Chat_User' });

    System.runAs(rep) {
      Assert.isFalse(
        Schema.SObjectType.LINE_Error_Log__c.isCreateable(),
        'Reps have no access to the log'
      );
      LineLogger.error('LineLoggerTest.rep', 'from a rep', null, null);
      LineLogger.flush();
    }

    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM LINE_Error_Log__c
        WHERE Source__c = 'LineLoggerTest.rep'
      ]
    );
  }
}
