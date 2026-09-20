/**
 * Typed DTOs for one LINE webhook event (04 §2), as carried in `LINE_Webhook_Event__e.Event_Json__c`.
 * `JSON.deserialize` ignores fields not declared here, so new LINE fields don't break parsing.
 */
public inherited sharing class LineWebhookModels {
  /** One webhook event. */
  public class Event {
    public String type;
    public String mode;
    public Long timestamp;
    public String webhookEventId;
    public String replyToken;
    public Source source;
    public Message message;
    public Follow follow;
  }

  /** Where the event came from; only `type = user` is handled. */
  public class Source {
    public String type;
    public String userId;
  }

  /** `message` object of a message event. Fields are filled depending on `type`. */
  public class Message {
    public String id;
    public String type;
    public String text;
    public String fileName;
    public Long fileSize;
    public String packageId;
    public String stickerId;
    public String title;
    public String address;
    public Decimal latitude;
    public Decimal longitude;
    public Integer duration;
    public ContentProvider contentProvider;
  }

  /** Whether media is stored by LINE (`line`) or at an external URL (`external`). */
  public class ContentProvider {
    public String type;
    public String originalContentUrl;
  }

  /** `follow` object of a follow event. */
  public class Follow {
    public Boolean isUnblocked;
  }

  /**
   * @param eventJson one event object as JSON
   * @return the parsed event
   */
  public static Event parse(String eventJson) {
    return (Event) JSON.deserialize(eventJson, Event.class);
  }
}
