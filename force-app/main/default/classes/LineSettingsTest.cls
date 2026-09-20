@IsTest
private class LineSettingsTest {
  @IsTest
  static void defaultsWhenNoRecord() {
    Assert.isNull(LineSettings.siteBaseUrl());
    Assert.isNull(LineSettings.webhookUrl());
    Assert.isNull(LineSettings.fallbackOwnerId());
    Assert.areEqual(5, LineSettings.pollIntervalSeconds());
    Assert.areEqual(10000000, LineSettings.maxDownloadBytes());
    Assert.areEqual(7, LineSettings.publicLinkExpiryDays());
    Assert.areEqual(7, LineSettings.inviteCodeExpiryDays());
    Assert.areEqual(0, LineSettings.messageRetentionMonths());
    Assert.isTrue(LineSettings.dailySyncEnabled());
    Assert.isFalse(LineSettings.updateContactOwnerOnReassign());
  }

  @IsTest
  static void valuesFromOrgRecord() {
    insert new LINE_Settings__c(
      SetupOwnerId = UserInfo.getOrganizationId(),
      Site_Base_Url__c = ' https://acme.my.salesforce-sites.com/linewebhook/ ',
      Fallback_Owner_Id__c = UserInfo.getUserId(),
      Poll_Interval_Seconds__c = 10,
      Max_Download_Bytes__c = 5000000,
      Public_Link_Expiry_Days__c = 3,
      Invite_Code_Expiry_Days__c = 2,
      Message_Retention_Months__c = 12,
      Daily_Sync_Enabled__c = false,
      Update_Contact_Owner_On_Reassign__c = true
    );
    LineSettings.reset();

    Assert.areEqual(
      'https://acme.my.salesforce-sites.com/linewebhook',
      LineSettings.siteBaseUrl()
    );
    Assert.areEqual(
      'https://acme.my.salesforce-sites.com/linewebhook' +
      LineNamespace.webhookPath(),
      LineSettings.webhookUrl()
    );
    Assert.areEqual(UserInfo.getUserId(), LineSettings.fallbackOwnerId());
    Assert.areEqual(10, LineSettings.pollIntervalSeconds());
    Assert.areEqual(5000000, LineSettings.maxDownloadBytes());
    Assert.areEqual(3, LineSettings.publicLinkExpiryDays());
    Assert.areEqual(2, LineSettings.inviteCodeExpiryDays());
    Assert.areEqual(12, LineSettings.messageRetentionMonths());
    Assert.isFalse(LineSettings.dailySyncEnabled());
    Assert.isTrue(LineSettings.updateContactOwnerOnReassign());
  }

  @IsTest
  static void invalidValuesFallBackToSafeValues() {
    insert new LINE_Settings__c(
      SetupOwnerId = UserInfo.getOrganizationId(),
      Fallback_Owner_Id__c = 'not-an-id',
      Poll_Interval_Seconds__c = 1,
      Max_Download_Bytes__c = 50000000,
      Public_Link_Expiry_Days__c = 0,
      Invite_Code_Expiry_Days__c = -1,
      Message_Retention_Months__c = -3
    );
    LineSettings.reset();

    Assert.isNull(LineSettings.fallbackOwnerId());
    Assert.areEqual(
      2,
      LineSettings.pollIntervalSeconds(),
      'Minimum poll interval'
    );
    Assert.areEqual(
      10000000,
      LineSettings.maxDownloadBytes(),
      'Capped by heap'
    );
    Assert.areEqual(7, LineSettings.publicLinkExpiryDays());
    Assert.areEqual(7, LineSettings.inviteCodeExpiryDays());
    Assert.areEqual(0, LineSettings.messageRetentionMonths());
  }

  @IsTest
  static void fallbackOwnerMustBeUserOrQueue() {
    // A valid Id that is neither a user nor a queue; no DML on subscriber objects needed.
    insert new LINE_Settings__c(
      SetupOwnerId = UserInfo.getOrganizationId(),
      Fallback_Owner_Id__c = UserInfo.getOrganizationId()
    );
    LineSettings.reset();

    Assert.isNull(LineSettings.fallbackOwnerId());
  }
}
