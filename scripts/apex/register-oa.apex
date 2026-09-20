// Registers a LINE OA in a scratch org (M3; the LINE Admin UI replaces this in M8).
//
// Before running:
//   1. The channel secret is stored through Setup (never in this file):
//      Setup → Custom Settings → LINE OA Credential → Manage → New: Name = <Channel ID>, Channel Secret = <secret>
//   2. LINE_Settings__c has the Site base URL (setup-scratch.sh seeds it).
//   3. In the LINE Developers Console → Messaging API: "Use webhook" ON, "Webhook redelivery" ON.
//
// Effect: sets THIS OA's webhook URL to this org's Site (replacing any existing URL), saves the OA configuration
// assigned to the running user, and queues LINE's webhook test (result in Webhook_Status__c a few seconds later).
//
// Run:  sf apex run --file scripts/apex/register-oa.apex --target-org line-dev | grep LINE_REG

String CHANNEL_ID = 'REPLACE_WITH_CHANNEL_ID';

try {
    LineOAConfigAdminService.RegistrationResult r = LineOAConfigAdminService.registerOA(
        CHANNEL_ID,
        LineCredentialStore.getSecret(CHANNEL_ID),
        UserInfo.getUserId()
    );
    System.debug(LoggingLevel.ERROR, 'LINE_REG ok name=' + r.name + ' basicId=' + r.basicId + ' botUserId=' + r.botUserId);
    System.debug(LoggingLevel.ERROR, 'LINE_REG webhookUrl=' + r.webhookUrl + ' status=' + r.webhookStatus);
} catch (LineApiException e) {
    System.debug(LoggingLevel.ERROR, 'LINE_REG LINE error ' + e.statusCode + ' ' + e.lineMessage + ' ' + e.details);
} catch (LineOAConfigAdminService.AdminException e) {
    System.debug(LoggingLevel.ERROR, 'LINE_REG setup problem: ' + e.getMessage());
}
