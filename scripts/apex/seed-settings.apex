// Seeds the org-level LINE_Settings__c record in a scratch org (03 §4). Run only after M1 deploys the setting.
// Fallback owner = the running admin; Site base URL = the LineWebhook Site's secure URL.
// Other fields stay blank so LineSettings' code defaults apply.

LINE_Settings__c s = LINE_Settings__c.getOrgDefaults();
if (s == null || s.Id == null) {
    s = new LINE_Settings__c(SetupOwnerId = UserInfo.getOrganizationId());
}
s.Fallback_Owner_Id__c = UserInfo.getUserId();

List<Site> sites = [SELECT Id FROM Site WHERE Name = 'LineWebhook' LIMIT 1];
if (!sites.isEmpty()) {
    List<SiteDetail> details = [SELECT SecureUrl FROM SiteDetail WHERE DurableId = :sites[0].Id LIMIT 1];
    if (!details.isEmpty() && String.isNotBlank(details[0].SecureUrl)) {
        s.Site_Base_Url__c = details[0].SecureUrl.removeEnd('/');
    }
}
upsert s;
System.debug(LoggingLevel.INFO, 'LINE_Settings__c seeded. Site base URL: ' + s.Site_Base_Url__c);
