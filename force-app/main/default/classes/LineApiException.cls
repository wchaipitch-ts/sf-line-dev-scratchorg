/**
 * A failed LINE API call: non-2xx response, callout failure or missing credentials.
 * `getMessage()` holds LINE's own message and never contains a secret or token.
 */
public inherited sharing class LineApiException extends Exception {
  /** HTTP status from LINE; 0 when no response was received (timeout, connection error). */
  public Integer statusCode { get; private set; }
  /** LINE's error message (`message`, or `error_description`/`error` for the token endpoint). */
  public String lineMessage { get; private set; }
  /** LINE's `details[].message` entries, if any. */
  public List<String> details { get; private set; }
  /** True when the failure came from issuing the channel access token. */
  public Boolean isTokenError { get; private set; }

  /**
   * @param statusCode HTTP status, or 0 when no response was received
   * @param lineMessage LINE's error message
   * @param details LINE's error details (may be null)
   * @param isTokenError whether the token request failed
   * @return the exception
   */
  public static LineApiException create(
    Integer statusCode,
    String lineMessage,
    List<String> details,
    Boolean isTokenError
  ) {
    LineApiException e = new LineApiException(
      'LINE API error ' +
        statusCode +
        (String.isBlank(lineMessage) ? '' : ': ' + lineMessage)
    );
    e.statusCode = statusCode;
    e.lineMessage = lineMessage;
    e.details = details == null ? new List<String>() : details;
    e.isTokenError = isTokenError == true;
    return e;
  }

  /**
   * @return true when the channel ID/secret are wrong or were reissued (401, or a rejected token request)
   */
  public Boolean isCredentialError() {
    return status() == 401 || (isTokenError == true && status() == 400);
  }

  /**
   * @return true when the OA has used its monthly message allowance (429 "You have reached your monthly limit.")
   */
  public Boolean isMonthlyLimit() {
    return status() == 429 &&
      lineMessage != null &&
      lineMessage.toLowerCase().contains('monthly limit');
  }

  /**
   * @return true when a retry key was already accepted: the original request succeeded (D8)
   */
  public Boolean isAlreadyAccepted() {
    return status() == 409;
  }

  /**
   * @return true for transient failures worth retrying: rate limit, LINE 5xx, or no response
   */
  public Boolean isRetryable() {
    return status() == 0 ||
      status() >= 500 ||
      (status() == 429 && !isMonthlyLimit());
  }

  private Integer status() {
    return statusCode == null ? 0 : statusCode;
  }

  /**
   * @return a message for users, from Custom Labels where the error is known (04 §3 "Errors to surface")
   */
  public String userMessage() {
    if (isCredentialError()) {
      return System.Label.LINE_Error_Credentials_Invalid;
    }
    if (isMonthlyLimit()) {
      return System.Label.LINE_Error_Monthly_Limit;
    }
    if (status() == 400 && String.isNotBlank(lineMessage)) {
      // LINE's validation message (e.g. text too long) is the most useful thing to show.
      List<String> parts = new List<String>{ lineMessage };
      if (details != null) {
        parts.addAll(details);
      }
      return String.join(parts, ' ');
    }
    return System.Label.LINE_Error_Generic;
  }
}
