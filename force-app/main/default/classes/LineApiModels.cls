/**
 * Typed DTOs for LINE Messaging API JSON (04 §3; checked against line/line-openapi, see DECISIONS).
 * No DTO here ever carries a channel secret or access token, except `TokenResponse`, which never leaves `LineApiClient`.
 */
public inherited sharing class LineApiModels {
  /** POST /oauth2/v3/token response. Internal to LineApiClient. */
  public class TokenResponse {
    public String access_token;
    public Integer expires_in;
    public String token_type;
  }

  /** GET /v2/bot/info */
  public class BotInfo {
    public String userId;
    public String basicId;
    public String premiumId;
    public String displayName;
    public String pictureUrl;
    public String chatMode;
    public String markAsReadMode;
  }

  /** GET /v2/bot/profile/{userId} */
  public class Profile {
    public String userId;
    public String displayName;
    public String pictureUrl;
    public String statusMessage;
    public String language;
  }

  /** POST /v2/bot/channel/webhook/test */
  public class WebhookTestResult {
    public Boolean success;
    public String timestamp;
    public Integer statusCode;
    public String reason;
    public String detail;
  }

  /** GET /v2/bot/message/quota. `type` is `none` (no limit) or `limited` (then `value` is the monthly limit). */
  public class Quota {
    public String type;
    public Long value;
  }

  /** GET /v2/bot/message/quota/consumption */
  public class QuotaConsumption {
    public Long totalUsage;
  }

  /** GET /v2/bot/message/{messageId}/content/transcoding. `status`: processing, succeeded or failed. */
  public class TranscodingStatus {
    public String status;
  }

  /** A sent message returned by push/reply. */
  public class SentMessage {
    public String id;
    public String quoteToken;
  }

  /** Result of a push. `alreadyAccepted` is true when LINE answered 409 for a reused retry key. */
  public class PushResult {
    public List<SentMessage> sentMessages = new List<SentMessage>();
    public Boolean alreadyAccepted = false;
    public String retryKey;
  }

  /** Downloaded message content. */
  public class Content {
    public Blob body;
    public String contentType;
    public Long contentLength;
  }

  /** A message object for push/reply. Serialized with nulls suppressed, so one class covers every type used. */
  public class Message {
    public String type;
    public String text;
    public String originalContentUrl;
    public String previewImageUrl;
    public Integer duration;
  }

  /**
   * @param text message text (1–5,000 characters)
   * @return a text message
   */
  public static Message textMessage(String text) {
    Message m = new Message();
    m.type = 'text';
    m.text = text;
    return m;
  }

  /**
   * @param originalContentUrl public HTTPS URL of the image (JPEG/PNG)
   * @param previewImageUrl public HTTPS URL of the preview image
   * @return an image message
   */
  public static Message imageMessage(
    String originalContentUrl,
    String previewImageUrl
  ) {
    Message m = new Message();
    m.type = 'image';
    m.originalContentUrl = originalContentUrl;
    m.previewImageUrl = previewImageUrl;
    return m;
  }

  /**
   * @param originalContentUrl public HTTPS URL of the mp4
   * @param previewImageUrl public HTTPS URL of the preview image
   * @return a video message
   */
  public static Message videoMessage(
    String originalContentUrl,
    String previewImageUrl
  ) {
    Message m = imageMessage(originalContentUrl, previewImageUrl);
    m.type = 'video';
    return m;
  }

  /**
   * @param originalContentUrl public HTTPS URL of the audio file
   * @param durationMs length in milliseconds
   * @return an audio message
   */
  public static Message audioMessage(
    String originalContentUrl,
    Integer durationMs
  ) {
    Message m = new Message();
    m.type = 'audio';
    m.originalContentUrl = originalContentUrl;
    m.duration = durationMs;
    return m;
  }

  /** Request body of push. */
  public class PushRequest {
    public String to;
    public List<Message> messages;
  }

  /** Request body of reply. */
  public class ReplyRequest {
    public String replyToken;
    public List<Message> messages;
  }

  /** Request body of set/test webhook endpoint. */
  public class WebhookEndpointRequest {
    public String endpoint;
  }

  /** Error body of the Messaging API. On a 409 push it also lists the originally sent messages. */
  public class ErrorResponse {
    public String message;
    public List<ErrorDetail> details;
    public List<SentMessage> sentMessages;
    // Token endpoint (OAuth style)
    public String error;
    public String error_description;
  }

  /** One entry of `ErrorResponse.details`. */
  public class ErrorDetail {
    public String message;
    public String property;
  }
}
