/**
 * Platform event trigger for LINE webhook events. No logic here (CLAUDE.md): see LineWebhookEventTriggerHandler.
 */
trigger LineWebhookEventTrigger on LINE_Webhook_Event__e(after insert) {
  new LineWebhookEventTriggerHandler().run();
}
