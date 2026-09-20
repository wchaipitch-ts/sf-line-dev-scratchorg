@IsTest
private class LineOAConfigAdminServiceTest {
  private static final String SITE = 'https://acme.my.salesforce-sites.com/linewebhook';

  @TestSetup
  static void setup() {
    insert new LINE_Settings__c(
      SetupOwnerId = UserInfo.getOrganizationId(),
      Site_Base_Url__c = SITE
    );
  }

  @IsTest
  static void registerFillsBotFieldsSetsWebhookAndStoresSecret() {
    LineHttpMock mock = new LineHttpMock();
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    LineOAConfigAdminService.RegistrationResult result = LineOAConfigAdminService.registerOA(
      ' ' + LineTestFactory.CHANNEL_A + ' ',
      LineTestFactory.SECRET_A,
      UserInfo.getUserId()
    );
    Test.stopTest();

    LINE_OA_Configuration__c oa = [
      SELECT
        Name,
        Channel_Id__c,
        Bot_User_Id__c,
        Basic_Id__c,
        Picture_Url__c,
        Assigned_Rep__c,
        Is_Active__c,
        Webhook_Status__c
      FROM LINE_OA_Configuration__c
    ];
    Assert.areEqual('OA A', oa.Name);
    Assert.areEqual(
      LineTestFactory.CHANNEL_A,
      oa.Channel_Id__c,
      'Channel ID is trimmed'
    );
    Assert.areEqual('Ubot_a', oa.Bot_User_Id__c);
    Assert.areEqual('@111aaaaa', oa.Basic_Id__c);
    Assert.areEqual('https://example.com/oa.png', oa.Picture_Url__c);
    Assert.areEqual(UserInfo.getUserId(), oa.Assigned_Rep__c);
    Assert.isTrue(oa.Is_Active__c);
    Assert.areEqual(
      'OK (200 OK)',
      oa.Webhook_Status__c,
      'Webhook test ran after the save'
    );
    Assert.areEqual(
      LineTestFactory.SECRET_A,
      LineCredentialStore.getSecret(LineTestFactory.CHANNEL_A)
    );

    String expectedUrl = SITE + LineNamespace.webhookPath();
    Assert.areEqual(expectedUrl, result.webhookUrl);
    Map<String, Object> putBody = (Map<String, Object>) JSON.deserializeUntyped(
      mock.requestsTo('/webhook/endpoint')[0].getBody()
    );
    Assert.areEqual(expectedUrl, putBody.get('endpoint'));
    Assert.areEqual(oa.Id, result.oaConfigId);
  }

  @IsTest
  static void resultNeverContainsTheSecret() {
    Test.setMock(HttpCalloutMock.class, new LineHttpMock());
    Test.startTest();
    LineOAConfigAdminService.RegistrationResult result = LineOAConfigAdminService.registerOA(
      LineTestFactory.CHANNEL_A,
      LineTestFactory.SECRET_A,
      UserInfo.getUserId()
    );
    Test.stopTest();

    String serialized = JSON.serialize(result);
    Assert.isFalse(serialized.contains(LineTestFactory.SECRET_A));
    Assert.isFalse(serialized.contains(LineHttpMock.FAKE_TOKEN));
  }

  @IsTest
  static void reRegisteringUpdatesTheSameRecord() {
    Test.setMock(HttpCalloutMock.class, new LineHttpMock());
    LineTestFactory.createOA(
      LineTestFactory.CHANNEL_A,
      'Uold',
      'old_fake_secret',
      UserInfo.getUserId()
    );

    Test.startTest();
    LineOAConfigAdminService.registerOA(
      LineTestFactory.CHANNEL_A,
      LineTestFactory.SECRET_A,
      UserInfo.getUserId()
    );
    Test.stopTest();

    Assert.areEqual(1, [SELECT COUNT() FROM LINE_OA_Configuration__c]);
    Assert.areEqual(
      'Ubot_a',
      [SELECT Bot_User_Id__c FROM LINE_OA_Configuration__c].Bot_User_Id__c
    );
    Assert.areEqual(
      LineTestFactory.SECRET_A,
      LineCredentialStore.getSecret(LineTestFactory.CHANNEL_A)
    );
  }

  @IsTest
  static void badCredentialsSaveNothing() {
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
      LineOAConfigAdminService.registerOA(
        LineTestFactory.CHANNEL_A,
        'wrong_fake_secret',
        UserInfo.getUserId()
      );
      Assert.fail('Expected LineApiException');
    } catch (LineApiException e) {
      Assert.isTrue(e.isCredentialError());
      Assert.isFalse(e.getMessage().contains('wrong_fake_secret'));
    }
    Test.stopTest();

    Assert.areEqual(0, [SELECT COUNT() FROM LINE_OA_Configuration__c]);
    Assert.isNull(LineCredentialStore.getSecret(LineTestFactory.CHANNEL_A));
    Assert.areEqual(0, mock.requestsTo('/webhook/endpoint').size());
  }

  @IsTest
  static void missingSiteUrlIsRefusedBeforeAnyCallout() {
    delete [SELECT Id FROM LINE_Settings__c];
    LineSettings.reset();
    LineHttpMock mock = new LineHttpMock();
    Test.setMock(HttpCalloutMock.class, mock);

    try {
      LineOAConfigAdminService.registerOA(
        LineTestFactory.CHANNEL_A,
        LineTestFactory.SECRET_A,
        UserInfo.getUserId()
      );
      Assert.fail('Expected AdminException');
    } catch (LineOAConfigAdminService.AdminException e) {
      Assert.areEqual(System.Label.LINE_Error_Site_Url_Missing, e.getMessage());
    }
    Assert.areEqual(0, mock.requests.size());
  }

  @IsTest
  static void inactiveOrMissingRepIsRefused() {
    Test.setMock(HttpCalloutMock.class, new LineHttpMock());
    try {
      LineOAConfigAdminService.registerOA(
        LineTestFactory.CHANNEL_A,
        LineTestFactory.SECRET_A,
        null
      );
      Assert.fail('Expected AdminException');
    } catch (LineOAConfigAdminService.AdminException e) {
      Assert.areEqual(System.Label.LINE_Error_Rep_Inactive, e.getMessage());
    }
    Assert.areEqual(0, [SELECT COUNT() FROM LINE_OA_Configuration__c]);
  }
}
