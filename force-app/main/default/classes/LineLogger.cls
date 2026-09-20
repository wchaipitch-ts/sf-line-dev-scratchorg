/**
 * Buffered error log writing `LINE_Error_Log__c`. Never throws.
 *
 * Entry points (webhook, platform event handler, queueables, batches, `@AuraEnabled` methods) catch, log, and call
 * `flush()` once at the end. `flush()` does DML, so it must come after the last callout of the transaction.
 *
 * Inserts run in system mode on purpose: reps and Automated Process have no access to the error log object,
 * but their failures must still be recorded for admins.
 */
public inherited sharing class LineLogger {
  @TestVisible
  static final Integer MAX_BUFFERED = 200;
  private static final Integer SOURCE_LENGTH = 100;
  private static final Integer LONG_TEXT_LENGTH = 32000;

  // Defence in depth: nothing should log a token or secret, but mask anything that looks like one.
  private static final List<Pattern> SECRET_PATTERNS = new List<Pattern>{
    Pattern.compile('(?i)(bearer\\s+)[A-Za-z0-9._~+/=-]+'),
    Pattern.compile('(?i)(client_secret=)[^&\\s]+'),
    Pattern.compile(
      '(?i)("?(?:access_token|client_secret|channel_?secret)"?\\s*[:=]\\s*"?)[^"&\\s,}]+'
    )
  };

  private static List<LINE_Error_Log__c> buffer = new List<LINE_Error_Log__c>();

  @TestVisible
  static Boolean forceFlushFailure = false;

  /**
   * Logs an exception. HTTP status is taken from a `LineApiException`.
   * @param source class and method, e.g. `LineCalloutQueueable.execute`
   * @param e the exception
   */
  public static void error(String source, Exception e) {
    error(source, e, null, null);
  }

  /**
   * Logs an exception with context.
   * @param source class and method
   * @param e the exception
   * @param oaConfigId related `LINE_OA_Configuration__c` Id, or null
   * @param relatedRecordId related record Id, or null
   */
  public static void error(
    String source,
    Exception e,
    Id oaConfigId,
    Id relatedRecordId
  ) {
    try {
      Integer httpStatus = e instanceof LineApiException
        ? ((LineApiException) e).statusCode
        : null;
      String message = e == null
        ? null
        : e.getTypeName() + ': ' + e.getMessage();
      add(
        source,
        message,
        e?.getStackTraceString(),
        oaConfigId,
        relatedRecordId,
        httpStatus
      );
    } catch (Exception ignored) {
      // Logging must never break the caller.
      return;
    }
  }

  /**
   * Logs a message without an exception (e.g. a partial-success DML failure).
   * @param source class and method
   * @param message what went wrong
   * @param oaConfigId related `LINE_OA_Configuration__c` Id, or null
   * @param relatedRecordId related record Id, or null
   */
  public static void error(
    String source,
    String message,
    Id oaConfigId,
    Id relatedRecordId
  ) {
    try {
      add(source, message, null, oaConfigId, relatedRecordId, null);
    } catch (Exception ignored) {
      return;
    }
  }

  /**
   * Logs the failed rows of a partial-success `Database.*(…, false)` call.
   * @param source class and method
   * @param results the save results
   * @param records the records passed to the DML call, in the same order
   */
  public static void saveErrors(
    String source,
    List<Database.SaveResult> results,
    List<SObject> records
  ) {
    try {
      for (Integer i = 0; i < results.size(); i++) {
        if (!results[i].isSuccess()) {
          Id recordId = records != null &&
            i < records.size()
            ? records[i].Id
            : null;
          add(
            source,
            describe(results[i].getErrors()),
            null,
            null,
            recordId,
            null
          );
        }
      }
    } catch (Exception ignored) {
      return;
    }
  }

  /**
   * @return number of entries waiting to be flushed
   */
  public static Integer pendingCount() {
    return buffer.size();
  }

  /**
   * Inserts the buffered entries (partial success) and clears the buffer. Never throws.
   */
  public static void flush() {
    if (buffer.isEmpty()) {
      return;
    }
    List<LINE_Error_Log__c> toInsert = buffer;
    buffer = new List<LINE_Error_Log__c>();
    try {
      if (forceFlushFailure) {
        throw new DmlException('Forced failure');
      }
      if (Limits.getDmlStatements() >= Limits.getLimitDmlStatements()) {
        return;
      }
      Database.insert(toInsert, false, AccessLevel.SYSTEM_MODE);
    } catch (Exception ignored) {
      // Nowhere left to report to; losing a log entry must not fail the business transaction.
      return;
    }
  }

  private static void add(
    String source,
    String message,
    String stackTrace,
    Id oaConfigId,
    Id relatedRecordId,
    Integer httpStatus
  ) {
    if (buffer.size() >= MAX_BUFFERED) {
      return;
    }
    buffer.add(
      new LINE_Error_Log__c(
        Source__c = truncate(source, SOURCE_LENGTH),
        Message__c = truncate(scrub(message), LONG_TEXT_LENGTH),
        Stack_Trace__c = truncate(stackTrace, LONG_TEXT_LENGTH),
        LINE_OA_Configuration__c = oaConfigId,
        Related_Record_Id__c = relatedRecordId,
        Http_Status__c = httpStatus
      )
    );
  }

  private static String describe(List<Database.Error> errors) {
    List<String> parts = new List<String>();
    for (Database.Error err : errors) {
      String fields = err.getFields() == null || err.getFields().isEmpty()
        ? ''
        : ' [' + String.join(err.getFields(), ', ') + ']';
      parts.add(err.getStatusCode() + ': ' + err.getMessage() + fields);
    }
    return String.join(parts, '; ');
  }

  @TestVisible
  private static String scrub(String value) {
    if (String.isBlank(value)) {
      return value;
    }
    String result = value;
    for (Pattern p : SECRET_PATTERNS) {
      result = p.matcher(result).replaceAll('$1***');
    }
    return result;
  }

  private static String truncate(String value, Integer maxLength) {
    return value == null ||
      value.length() <= maxLength
      ? value
      : value.left(maxLength);
  }
}
