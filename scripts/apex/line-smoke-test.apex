// Manual smoke test of LineApiClient against a real LINE channel (scratch org only).
//
// Before running:
//   1. Store the channel secret through Setup, never in this file:
//      Setup → Custom Settings → LINE OA Credential → Manage → New
//      Name = <Channel ID>, Channel Secret = <channel secret>
//      (Editable here because the org is unpackaged; in an installed package the setting is protected.)
//   2. Fill in CHANNEL_ID and MY_USER_ID below. Neither is a secret.
//      MY_USER_ID = LINE Developers Console → your channel → Basic settings → "Your user ID".
//      Add the OA as a friend on your phone first, or the push is refused.
//
// Run:  sf apex run --file scripts/apex/line-smoke-test.apex --target-org line-dev
// The token is never printed. The push uses one message from the OA's monthly quota; set SEND_PUSH = false to skip.

String CHANNEL_ID = 'REPLACE_WITH_CHANNEL_ID';
String MY_USER_ID = 'REPLACE_WITH_YOUR_USER_ID';
Boolean SEND_PUSH = true;

void out(String label, Object value) {
    System.debug(LoggingLevel.ERROR, 'LINE_SMOKE ' + label + ' = ' + value);
}

try {
    LineApiClient client = LineApiClient.forChannel(CHANNEL_ID);
    client.issueToken();
    out('token', 'issued OK (stateless, not shown)');

    LineApiModels.BotInfo bot = client.getBotInfo();
    out('bot.userId (webhook destination)', bot.userId);
    out('bot.basicId', bot.basicId);
    out('bot.displayName', bot.displayName);
    out('bot.chatMode', bot.chatMode);

    LineApiModels.Quota quota = client.getQuota();
    out('quota', quota.type + (quota.value == null ? '' : ' ' + quota.value));
    out('usage this month', client.getQuotaConsumption().totalUsage);

    if (SEND_PUSH) {
        LineApiModels.PushResult result = client.push(
            MY_USER_ID,
            new List<LineApiModels.Message>{
                LineApiModels.textMessage('LINE Connect smoke test ✅ ทดสอบการส่งข้อความจาก Salesforce')
            },
            null
        );
        out('push', 'sent, message id ' + result.sentMessages[0].id);
    }
} catch (LineApiException e) {
    out('ERROR', e.statusCode + ' ' + e.lineMessage + ' ' + e.details + ' | credentialError=' + e.isCredentialError());
}
