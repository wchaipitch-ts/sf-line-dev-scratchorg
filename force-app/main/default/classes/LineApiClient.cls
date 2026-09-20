/**
 * All HTTP calls to LINE (02 §2, 04). One instance per channel.
 *
 * Authentication uses stateless channel access tokens (D4): issued from the channel ID + secret on demand and cached
 * per channel for the rest of the transaction (at most 10 minutes; they are valid for ~15). Non-2xx responses throw
 * `LineApiException`. Callers must make all callouts before any DML in the transaction (hard rule 6).
 */
public inherited sharing class LineApiClient {
  // The only hard-coded URLs in the package (CLAUDE.md "Config").
  @TestVisible
  static final String API_BASE = 'https://api.line.me';
  @TestVisible
  static final String DATA_BASE = 'https://api-data.line.me';

  private static final Integer TIMEOUT_MS = 20000;
  private static final Integer CONTENT_TIMEOUT_MS = 120000;
  private static final Long TOKEN_CACHE_MS = 10 * 60 * 1000;

  private static Map<String, CachedToken> tokenCache = new Map<String, CachedToken>();

  private final String channelId;
  // Held only for issuing tokens; never exposed, logged or serialized.
  private transient String channelSecret;
  // Sent messages from the last 409 push response (the original accepted request).
  private List<LineApiModels.SentMessage> lastConflictSentMessages = new List<LineApiModels.SentMessage>();

  private class CachedToken {
    String accessToken;
    Long issuedAtMs;
  }

  private LineApiClient(String channelId, String channelSecret) {
    this.channelId = channelId;
    this.channelSecret = channelSecret;
  }

  /**
   * Client for a registered channel; the secret comes from `LineCredentialStore`.
   * @param channelId LINE channel ID
   * @return the client
   * @throws LineApiException (401) when no secret is stored for the channel
   */
  public static LineApiClient forChannel(String channelId) {
    String secret = LineCredentialStore.getSecret(channelId);
    if (String.isBlank(secret)) {
      throw LineApiException.create(
        401,
        'No channel secret stored for this channel.',
        null,
        true
      );
    }
    return new LineApiClient(channelId, secret);
  }

  /**
   * Client with credentials that aren't stored yet (OA registration, secret rotation).
   * @param channelId LINE channel ID
   * @param channelSecret channel secret
   * @return the client
   */
  public static LineApiClient withCredentials(
    String channelId,
    String channelSecret
  ) {
    if (String.isBlank(channelId) || String.isBlank(channelSecret)) {
      throw LineApiException.create(
        401,
        'Channel ID and secret are required.',
        null,
        true
      );
    }
    return new LineApiClient(channelId, channelSecret);
  }

  /**
   * Issues (or reuses) a stateless channel access token. Also used to check a channel ID + secret.
   * @return the access token; callers must not store, log or return it
   */
  public String issueToken() {
    CachedToken cached = tokenCache.get(channelId);
    if (
      cached != null &&
      System.currentTimeMillis() - cached.issuedAtMs < TOKEN_CACHE_MS
    ) {
      return cached.accessToken;
    }
    HttpRequest req = new HttpRequest();
    req.setMethod('POST');
    req.setEndpoint(API_BASE + '/oauth2/v3/token');
    req.setTimeout(TIMEOUT_MS);
    req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
    req.setBody(
      'grant_type=client_credentials&client_id=' +
        EncodingUtil.urlEncode(channelId, 'UTF-8') +
        '&client_secret=' +
        EncodingUtil.urlEncode(channelSecret, 'UTF-8')
    );
    HttpResponse res = send(req, true);
    LineApiModels.TokenResponse token = (LineApiModels.TokenResponse) parse(
      res,
      LineApiModels.TokenResponse.class
    );
    if (token == null || String.isBlank(token.access_token)) {
      throw LineApiException.create(
        res.getStatusCode(),
        'Token response had no access token.',
        null,
        true
      );
    }
    CachedToken entry = new CachedToken();
    entry.accessToken = token.access_token;
    entry.issuedAtMs = System.currentTimeMillis();
    tokenCache.put(channelId, entry);
    return token.access_token;
  }

  /**
   * GET /v2/bot/info
   * @return the OA's bot user ID (webhook destination), basic ID, name and picture
   */
  public LineApiModels.BotInfo getBotInfo() {
    return (LineApiModels.BotInfo) parse(
      send(authorized('GET', API_BASE + '/v2/bot/info', null)),
      LineApiModels.BotInfo.class
    );
  }

  /**
   * PUT /v2/bot/channel/webhook/endpoint. "Use webhook" must still be switched on in the LINE console.
   * @param endpoint HTTPS webhook URL (max 500 characters)
   */
  public void setWebhookEndpoint(String endpoint) {
    LineApiModels.WebhookEndpointRequest body = new LineApiModels.WebhookEndpointRequest();
    body.endpoint = endpoint;
    send(
      authorized(
        'PUT',
        API_BASE + '/v2/bot/channel/webhook/endpoint',
        JSON.serialize(body, true)
      )
    );
  }

  /**
   * POST /v2/bot/channel/webhook/test
   * @param endpoint URL to test, or null for the URL registered with LINE
   * @return LINE's result of calling the webhook
   */
  public LineApiModels.WebhookTestResult testWebhookEndpoint(String endpoint) {
    LineApiModels.WebhookEndpointRequest body = new LineApiModels.WebhookEndpointRequest();
    body.endpoint = endpoint;
    HttpResponse res = send(
      authorized(
        'POST',
        API_BASE + '/v2/bot/channel/webhook/test',
        JSON.serialize(body, true)
      )
    );
    return (LineApiModels.WebhookTestResult) parse(
      res,
      LineApiModels.WebhookTestResult.class
    );
  }

  /**
   * GET /v2/bot/profile/{userId}. Works for users who have added the OA.
   * @param userId the customer's LINE user ID
   * @return display name, picture, status message and language
   */
  public LineApiModels.Profile getProfile(String userId) {
    HttpResponse res = send(
      authorized('GET', API_BASE + '/v2/bot/profile/' + encode(userId), null)
    );
    return (LineApiModels.Profile) parse(res, LineApiModels.Profile.class);
  }

  /**
   * POST /v2/bot/message/push with `X-Line-Retry-Key` (D8). A 409 (key already accepted) counts as success.
   * @param to the customer's LINE user ID
   * @param messages 1–5 message objects
   * @param retryKey UUID to reuse when retrying the same send; null generates a new one
   * @return the sent message IDs and the retry key used
   */
  public LineApiModels.PushResult push(
    String to,
    List<LineApiModels.Message> messages,
    String retryKey
  ) {
    LineApiModels.PushRequest body = new LineApiModels.PushRequest();
    body.to = to;
    body.messages = messages;
    HttpRequest req = authorized(
      'POST',
      API_BASE + '/v2/bot/message/push',
      JSON.serialize(body, true)
    );
    String key = String.isBlank(retryKey)
      ? UUID.randomUUID().toString()
      : retryKey;
    req.setHeader('X-Line-Retry-Key', key);

    LineApiModels.PushResult result = new LineApiModels.PushResult();
    result.retryKey = key;
    try {
      HttpResponse res = send(req);
      LineApiModels.PushResult parsed = (LineApiModels.PushResult) parse(
        res,
        LineApiModels.PushResult.class
      );
      if (parsed != null && parsed.sentMessages != null) {
        result.sentMessages = parsed.sentMessages;
      }
    } catch (LineApiException e) {
      if (!e.isAlreadyAccepted()) {
        throw e;
      }
      result.alreadyAccepted = true;
      result.sentMessages = lastConflictSentMessages;
    }
    return result;
  }

  /**
   * POST /v2/bot/message/reply. Free, but the reply token is single-use and expires quickly.
   * @param replyToken reply token from the webhook event
   * @param messages 1–5 message objects
   */
  public void reply(String replyToken, List<LineApiModels.Message> messages) {
    LineApiModels.ReplyRequest body = new LineApiModels.ReplyRequest();
    body.replyToken = replyToken;
    body.messages = messages;
    send(
      authorized(
        'POST',
        API_BASE + '/v2/bot/message/reply',
        JSON.serialize(body, true)
      )
    );
  }

  /**
   * GET https://api-data.line.me/v2/bot/message/{messageId}/content. Call only from async code (heap).
   * @param messageId LINE message ID
   * @return the binary content with its type and length
   */
  public LineApiModels.Content getContent(String messageId) {
    HttpRequest req = authorized(
      'GET',
      DATA_BASE + '/v2/bot/message/' + encode(messageId) + '/content',
      null
    );
    req.setTimeout(CONTENT_TIMEOUT_MS);
    HttpResponse res = send(req);
    LineApiModels.Content content = new LineApiModels.Content();
    content.body = res.getBodyAsBlob();
    content.contentType = res.getHeader('Content-Type');
    content.contentLength = content.body == null ? 0 : content.body.size();
    return content;
  }

  /**
   * GET https://api-data.line.me/v2/bot/message/{messageId}/content/transcoding (video/audio readiness).
   * @param messageId LINE message ID
   * @return `processing`, `succeeded` or `failed`
   */
  public String getContentTranscodingStatus(String messageId) {
    HttpResponse res = send(
      authorized(
        'GET',
        DATA_BASE +
          '/v2/bot/message/' +
          encode(messageId) +
          '/content/transcoding',
        null
      )
    );
    LineApiModels.TranscodingStatus status = (LineApiModels.TranscodingStatus) parse(
      res,
      LineApiModels.TranscodingStatus.class
    );
    return status?.status;
  }

  /**
   * GET /v2/bot/message/quota
   * @return the monthly limit (`type` none/limited, `value`)
   */
  public LineApiModels.Quota getQuota() {
    return (LineApiModels.Quota) parse(
      send(authorized('GET', API_BASE + '/v2/bot/message/quota', null)),
      LineApiModels.Quota.class
    );
  }

  /**
   * GET /v2/bot/message/quota/consumption
   * @return messages sent this month that count against the quota
   */
  public LineApiModels.QuotaConsumption getQuotaConsumption() {
    return (LineApiModels.QuotaConsumption) parse(
      send(
        authorized('GET', API_BASE + '/v2/bot/message/quota/consumption', null)
      ),
      LineApiModels.QuotaConsumption.class
    );
  }

  /**
   * Forgets cached tokens, e.g. after a secret rotation in the same transaction.
   */
  public static void clearTokenCache() {
    tokenCache.clear();
  }

  // ---------------------------------------------------------------------------------------------------------------

  private HttpRequest authorized(
    String method,
    String endpoint,
    String jsonBody
  ) {
    HttpRequest req = new HttpRequest();
    req.setMethod(method);
    req.setEndpoint(endpoint);
    req.setTimeout(TIMEOUT_MS);
    // Named Credentials aren't used by design (D4): one per OA would need subscriber setup for every OA.
    req.setHeader('Authorization', 'Bearer ' + issueToken()); // NOPMD ApexSuggestUsingNamedCred - see D4
    if (jsonBody != null) {
      req.setHeader('Content-Type', 'application/json; charset=UTF-8');
      req.setBody(jsonBody);
    }
    return req;
  }

  private HttpResponse send(HttpRequest req) {
    return send(req, false);
  }

  private HttpResponse send(HttpRequest req, Boolean isTokenRequest) {
    HttpResponse res;
    try {
      res = new Http().send(req);
    } catch (CalloutException e) {
      // No response: timeout or connection failure. The request (with its credentials) is never included.
      throw LineApiException.create(0, e.getMessage(), null, isTokenRequest);
    }
    Integer status = res.getStatusCode();
    if (status >= 200 && status < 300) {
      return res;
    }
    throw toException(res, isTokenRequest);
  }

  private LineApiException toException(
    HttpResponse res,
    Boolean isTokenRequest
  ) {
    lastConflictSentMessages = new List<LineApiModels.SentMessage>();
    LineApiModels.ErrorResponse err = parseError(res);
    if (err == null) {
      // Non-JSON error body (e.g. a proxy page): keep the HTTP status text.
      return LineApiException.create(
        res.getStatusCode(),
        res.getStatus(),
        null,
        isTokenRequest
      );
    }
    if (err.sentMessages != null) {
      lastConflictSentMessages = err.sentMessages;
    }
    return LineApiException.create(
      res.getStatusCode(),
      firstNonBlank(
        new List<String>{
          err.message,
          err.error_description,
          err.error,
          res.getStatus()
        }
      ),
      detailMessages(err.details),
      isTokenRequest
    );
  }

  private static LineApiModels.ErrorResponse parseError(HttpResponse res) {
    try {
      return (LineApiModels.ErrorResponse) JSON.deserialize(
        res.getBody(),
        LineApiModels.ErrorResponse.class
      );
    } catch (Exception e) {
      return null;
    }
  }

  private static List<String> detailMessages(
    List<LineApiModels.ErrorDetail> details
  ) {
    List<String> result = new List<String>();
    for (
      LineApiModels.ErrorDetail d : details == null
        ? new List<LineApiModels.ErrorDetail>()
        : details
    ) {
      if (String.isNotBlank(d.message)) {
        result.add(
          String.isBlank(d.property) ? d.message : d.property + ': ' + d.message
        );
      }
    }
    return result;
  }

  private static String firstNonBlank(List<String> values) {
    for (String value : values) {
      if (String.isNotBlank(value)) {
        return value;
      }
    }
    return null;
  }

  private static Object parse(HttpResponse res, System.Type apexType) {
    String body = res.getBody();
    if (String.isBlank(body)) {
      return null;
    }
    try {
      return JSON.deserialize(body, apexType);
    } catch (JSONException e) {
      throw LineApiException.create(
        res.getStatusCode(),
        'Unexpected response from LINE.',
        null,
        false
      );
    }
  }

  private static String encode(String value) {
    return EncodingUtil.urlEncode(value == null ? '' : value, 'UTF-8');
  }
}
