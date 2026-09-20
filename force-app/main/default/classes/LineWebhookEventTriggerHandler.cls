/**
 * Handler for `LineWebhookEventTrigger` (after insert on `LINE_Webhook_Event__e`). Runs as Automated Process.
 *
 * Processing is bulk and idempotent (upserts by external IDs), so a whole batch can safely be retried.
 * Transient failures (row locks, LINE-side retryable errors) are retried up to 3 times with
 * `EventBus.RetryableException`; anything else is logged and the batch is acknowledged, so one bad event can't block
 * the event stream.
 *
 * `without sharing` (02 §2): platform event trigger entry point; delegates to system-mode services.
 */
public without sharing class LineWebhookEventTriggerHandler extends LineTriggerHandler {
  @TestVisible
  static final Integer MAX_RETRIES = 3;
  private static final Set<String> TRANSIENT_DML_ERRORS = new Set<String>{
    'UNABLE_TO_LOCK_ROW'
  };

  @TestVisible
  private List<LINE_Webhook_Event__e> events;
  @TestVisible
  private Integer retries;
  // Lets tests drive the error paths.
  @TestVisible
  static Exception testException;

  /**
   * Uses the trigger context.
   */
  public LineWebhookEventTriggerHandler() {
    this((List<LINE_Webhook_Event__e>) Trigger.new, null);
  }

  @TestVisible
  private LineWebhookEventTriggerHandler(
    List<LINE_Webhook_Event__e> events,
    Integer retries
  ) {
    this.events = events;
    this.retries = retries;
  }

  protected override void afterInsert() {
    try {
      if (testException != null) {
        throw testException;
      }
      LineInboundService.process(events);
    } catch (Exception e) {
      if (isTransient(e) && currentRetries() < MAX_RETRIES) {
        LineLogger.flush();
        throw new EventBus.RetryableException(e.getMessage());
      }
      LineLogger.error('LineWebhookEventTriggerHandler.afterInsert', e);
    } finally {
      LineLogger.flush();
    }
  }

  private Integer currentRetries() {
    if (retries != null) {
      return retries;
    }
    EventBus.TriggerContext context = EventBus.TriggerContext.currentContext();
    return context == null ? 0 : context.retries;
  }

  @TestVisible
  private static Boolean isTransient(Exception e) {
    if (e instanceof LineApiException) {
      return ((LineApiException) e).isRetryable();
    }
    // DML failures carry the status code in the message ("first error: UNABLE_TO_LOCK_ROW, ...").
    // getDmlType() isn't used: on an exception not raised by DML it throws an uncatchable UnexpectedException.
    String message = e.getMessage();
    if (message == null) {
      return false;
    }
    for (String code : TRANSIENT_DML_ERRORS) {
      if (message.contains(code)) {
        return true;
      }
    }
    return false;
  }
}
