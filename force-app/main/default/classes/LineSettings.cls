/**
 * Read access to the org-level `LINE_Settings__c` record, with code defaults for blank or invalid values (03 §4).
 * All other code reads settings only through this class.
 */
public inherited sharing class LineSettings {
  @TestVisible
  static final Integer DEFAULT_POLL_INTERVAL_SECONDS = 5;
  @TestVisible
  static final Integer MIN_POLL_INTERVAL_SECONDS = 2;
  @TestVisible
  static final Long DEFAULT_MAX_DOWNLOAD_BYTES = 10000000;
  // Async heap is 12 MB and the file is held as a Blob plus a ContentVersion copy, so larger values can't work.
  @TestVisible
  static final Long MAX_DOWNLOAD_BYTES_CEILING = 10000000;
  @TestVisible
  static final Integer DEFAULT_PUBLIC_LINK_EXPIRY_DAYS = 7;
  @TestVisible
  static final Integer DEFAULT_INVITE_CODE_EXPIRY_DAYS = 7;
  @TestVisible
  static final Integer DEFAULT_MESSAGE_RETENTION_MONTHS = 0;

  private static LINE_Settings__c cached;

  @TestVisible
  private static LINE_Settings__c record() {
    if (cached == null) {
      cached = LINE_Settings__c.getOrgDefaults();
      if (cached == null) {
        cached = new LINE_Settings__c();
      }
    }
    return cached;
  }

  /**
   * Drops the per-transaction cache, e.g. after the admin page saves settings.
   */
  public static void reset() {
    cached = null;
  }

  /**
   * @return the public Site base URL without a trailing slash (includes any path prefix), or null if not set
   */
  public static String siteBaseUrl() {
    String url = record().Site_Base_Url__c;
    return String.isBlank(url) ? null : url.trim().removeEnd('/');
  }

  /**
   * @return the full webhook URL to register with LINE, or null while the Site base URL isn't set
   */
  public static String webhookUrl() {
    String base = siteBaseUrl();
    return base == null ? null : base + LineNamespace.webhookPath();
  }

  /**
   * @return the fallback owner (User or Queue Id), or null if blank or not a valid Id
   */
  public static Id fallbackOwnerId() {
    String value = record().Fallback_Owner_Id__c;
    if (String.isBlank(value)) {
      return null;
    }
    try {
      Id ownerId = Id.valueOf(value.trim());
      // Only users (005) and queues (00G) can own conversations.
      String keyPrefix = String.valueOf(ownerId).left(3);
      return keyPrefix == '005' || keyPrefix == '00G' ? ownerId : null;
    } catch (StringException e) {
      return null;
    }
  }

  /**
   * @return seconds between chat panel polls (default 5, minimum 2)
   */
  public static Integer pollIntervalSeconds() {
    Decimal value = record().Poll_Interval_Seconds__c;
    if (value == null || value <= 0) {
      return DEFAULT_POLL_INTERVAL_SECONDS;
    }
    return Math.max(value.intValue(), MIN_POLL_INTERVAL_SECONDS);
  }

  /**
   * @return the largest inbound file (bytes) downloaded into Salesforce Files (default and ceiling 10,000,000)
   */
  public static Long maxDownloadBytes() {
    Decimal value = record().Max_Download_Bytes__c;
    if (value == null || value <= 0) {
      return DEFAULT_MAX_DOWNLOAD_BYTES;
    }
    return Math.min(value.longValue(), MAX_DOWNLOAD_BYTES_CEILING);
  }

  /**
   * @return days before outbound public links expire (default 7)
   */
  public static Integer publicLinkExpiryDays() {
    return positiveOrDefault(
      record().Public_Link_Expiry_Days__c,
      DEFAULT_PUBLIC_LINK_EXPIRY_DAYS
    );
  }

  /**
   * @return days before a QR invite code expires (default 7)
   */
  public static Integer inviteCodeExpiryDays() {
    return positiveOrDefault(
      record().Invite_Code_Expiry_Days__c,
      DEFAULT_INVITE_CODE_EXPIRY_DAYS
    );
  }

  /**
   * @return months to keep messages; 0 = keep forever (default)
   */
  public static Integer messageRetentionMonths() {
    Decimal value = record().Message_Retention_Months__c;
    return value == null ||
      value < 0
      ? DEFAULT_MESSAGE_RETENTION_MONTHS
      : value.intValue();
  }

  /**
   * @return whether the nightly daily-Event sync runs (default true)
   */
  public static Boolean dailySyncEnabled() {
    // A missing org record means the admin never changed it, so the spec default (on) applies.
    return record().Id == null ? true : record().Daily_Sync_Enabled__c == true;
  }

  /**
   * @return whether reassigning an OA also moves the owner of its linked Contacts (default false)
   */
  public static Boolean updateContactOwnerOnReassign() {
    return record().Update_Contact_Owner_On_Reassign__c == true;
  }

  private static Integer positiveOrDefault(
    Decimal value,
    Integer defaultValue
  ) {
    return value == null || value <= 0 ? defaultValue : value.intValue();
  }
}
