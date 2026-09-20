/**
 * The only class that reads or writes the protected custom setting `LINE_OA_Credential__c` (D4, hard rule 4).
 * Secrets returned here must never reach a DTO, LWC, log, debug statement or error message.
 *
 * `without sharing` (02 §2): the webhook runs as the Site guest user and processing runs as Automated Process;
 * neither has, nor should get, any access to the credential setting. Protected settings are reachable only from
 * package code, so system mode here is the access control.
 */
public without sharing class LineCredentialStore {
  // Custom setting Name is limited to 38 characters; LINE channel IDs are numeric.
  private static final Pattern CHANNEL_ID_PATTERN = Pattern.compile(
    '^[0-9]{1,38}$'
  );
  private static final Integer MAX_SECRET_LENGTH = 255;

  // Values written in this transaction, so reads right after a write don't depend on the settings cache.
  private static Map<String, String> writtenThisTransaction = new Map<String, String>();

  /**
   * @param channelId LINE channel ID
   * @return the channel secret, or null if none is stored
   */
  public static String getSecret(String channelId) {
    if (!isValidChannelId(channelId)) {
      return null;
    }
    if (writtenThisTransaction.containsKey(channelId)) {
      return writtenThisTransaction.get(channelId);
    }
    LINE_OA_Credential__c credential = LINE_OA_Credential__c.getInstance(
      channelId
    );
    return credential == null ? null : credential.Channel_Secret__c;
  }

  /**
   * Stores or replaces the secret of a channel. Does DML: call it only after all callouts of the transaction.
   * @param channelId LINE channel ID (digits)
   * @param secret channel secret (not blank, at most 255 characters)
   */
  public static void putSecret(String channelId, String secret) {
    if (!isValidChannelId(channelId)) {
      throw new IllegalArgumentException('Invalid channel ID.');
    }
    if (String.isBlank(secret) || secret.length() > MAX_SECRET_LENGTH) {
      // Deliberately doesn't echo the value.
      throw new IllegalArgumentException('Invalid channel secret.');
    }
    LINE_OA_Credential__c existing = LINE_OA_Credential__c.getInstance(
      channelId
    );
    LINE_OA_Credential__c credential = new LINE_OA_Credential__c(
      Id = existing?.Id,
      Name = channelId,
      Channel_Secret__c = secret
    );
    Database.upsert(credential, true, AccessLevel.SYSTEM_MODE);
    writtenThisTransaction.put(channelId, secret);
  }

  /**
   * Deletes the stored secret of a channel, if any. Does DML.
   * @param channelId LINE channel ID
   */
  public static void remove(String channelId) {
    if (!isValidChannelId(channelId)) {
      return;
    }
    LINE_OA_Credential__c existing = LINE_OA_Credential__c.getInstance(
      channelId
    );
    if (existing != null && existing.Id != null) {
      Database.delete(existing, true, AccessLevel.SYSTEM_MODE);
    }
    writtenThisTransaction.put(channelId, null);
  }

  private static Boolean isValidChannelId(String channelId) {
    return channelId != null && CHANNEL_ID_PATTERN.matcher(channelId).matches();
  }
}
