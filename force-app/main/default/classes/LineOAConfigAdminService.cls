/**
 * OA administration (05 Part D). Callouts first, then DML (hard rule 6).
 * M3: `registerOA` (callable from anonymous Apex). M8 adds rotate, reassign and deactivate, and the
 * `LineAdminController` entry point that checks the `LINE_Admin` custom permission before calling this class.
 *
 * `without sharing` (02 §2): writes the protected credential setting and OA configurations on behalf of an admin
 * whose permission is checked by the caller.
 */
public without sharing class LineOAConfigAdminService {
  private static final Integer NAME_LENGTH = 80;
  private static final Integer URL_LENGTH = 255;

  /** Registration outcome. Never contains the secret or a token. */
  public class RegistrationResult {
    public Id oaConfigId;
    public String name;
    public String basicId;
    public String botUserId;
    public String webhookUrl;
    public String webhookStatus;
  }

  /** A validation problem the admin can fix; the message is a Custom Label. */
  public class AdminException extends Exception {
  }

  /**
   * Registers (or re-registers) a LINE OA:
   * 1. issues a token (checks ID + secret), 2. reads bot info, 3. sets the webhook URL — all callouts;
   * 4. upserts the OA configuration by Channel ID and stores the secret — DML;
   * 5. queues a webhook test, which needs the saved configuration to route LINE's test call.
   *
   * @param channelId LINE channel ID
   * @param channelSecret channel secret (stored only in the protected setting)
   * @param repId the rep who will own the OA's conversations (active user)
   * @return what was registered
   * @throws LineApiException when LINE rejects the credentials or a call (nothing is saved)
   * @throws AdminException when the input or settings are incomplete (nothing is called or saved)
   */
  public static RegistrationResult registerOA(
    String channelId,
    String channelSecret,
    Id repId
  ) {
    String webhookUrl = LineSettings.webhookUrl();
    if (webhookUrl == null) {
      throw new AdminException(System.Label.LINE_Error_Site_Url_Missing);
    }
    if (
      repId == null ||
      [
        SELECT COUNT()
        FROM User
        WHERE Id = :repId AND IsActive = TRUE
        WITH SYSTEM_MODE
      ] == 0
    ) {
      throw new AdminException(System.Label.LINE_Error_Rep_Inactive);
    }
    String cleanChannelId = channelId == null ? null : channelId.trim();

    // 1–3: callouts
    LineApiClient client = LineApiClient.withCredentials(
      cleanChannelId,
      channelSecret == null ? null : channelSecret.trim()
    );
    client.issueToken();
    LineApiModels.BotInfo bot = client.getBotInfo();
    client.setWebhookEndpoint(webhookUrl);

    // 4: DML
    LINE_OA_Configuration__c oa = new LINE_OA_Configuration__c(
      Channel_Id__c = cleanChannelId,
      Name = String.isBlank(bot.displayName)
        ? cleanChannelId
        : bot.displayName.left(NAME_LENGTH),
      Bot_User_Id__c = bot.userId,
      Basic_Id__c = bot.basicId,
      Picture_Url__c = bot.pictureUrl != null &&
        bot.pictureUrl.length() <= URL_LENGTH
        ? bot.pictureUrl
        : null,
      Assigned_Rep__c = repId,
      Is_Active__c = true,
      Webhook_Status__c = System.Label.LINE_Webhook_Test_Pending,
      Last_Verified_At__c = Datetime.now()
    );
    Database.upsert(
      oa,
      LINE_OA_Configuration__c.Channel_Id__c,
      true,
      AccessLevel.SYSTEM_MODE
    );
    LineCredentialStore.putSecret(cleanChannelId, channelSecret.trim());

    // 5: async webhook test
    LineCalloutQueueable.enqueue(
      new List<LineCalloutQueueable.WorkItem>{
        LineCalloutQueueable.webhookTestItem(oa.Id, cleanChannelId)
      }
    );

    RegistrationResult result = new RegistrationResult();
    result.oaConfigId = oa.Id;
    result.name = oa.Name;
    result.basicId = oa.Basic_Id__c;
    result.botUserId = oa.Bot_User_Id__c;
    result.webhookUrl = webhookUrl;
    result.webhookStatus = oa.Webhook_Status__c;
    return result;
  }
}
