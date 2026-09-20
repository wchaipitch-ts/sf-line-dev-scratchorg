/**
 * LINE webhook endpoint: POST /services/apexrest/<ns>/line/webhook (D1–D3).
 *
 * Runs as the Site guest user, whose only access is this class and Create on `LINE_Webhook_Event__e`.
 * Order: resolve the OA by `destination` (403 if unknown) → verify `X-Line-Signature` over the raw body (401 if bad
 * or missing) → publish one platform event per LINE event → 200. No business DML, no callouts, and no logging
 * (junk traffic must not be able to write records).
 *
 * `global` is required by @RestResource in a managed package; it is the only global class (hard rule 2).
 * `without sharing` (02 §2): the guest user has no access to OA configurations; system mode lets it look up the
 * receiving OA and its secret without granting the guest any record access.
 */
@RestResource(urlMapping='/line/webhook')
global without sharing class LineWebhookResource {
  // LINE webhook bodies are small; anything much larger is not LINE.
  @TestVisible
  private static final Integer MAX_BODY_BYTES = 1000000;
  // The header's name, not a credential.
  private static final String SIGNATURE_HEADER = 'x-line-signature'; // code-analyzer-suppress(AvoidHardcodedCredentialsInFieldDecls)
  // code-analyzer-unsuppress(AvoidHardcodedCredentialsInFieldDecls)

  /**
   * Receives a LINE webhook. The HTTP status is the only output.
   *
   * System-mode read of LINE_OA_Configuration__c (routing fields only) is intentional (D2, SECURITY_NOTES §2):
   * the guest user has no object access by design, nothing read is returned to the caller, and every request
   * is authenticated by the signature before anything is published.
   */
  @HttpPost
  global static void handlePost() {
    RestRequest req = RestContext.request;
    RestResponse res = RestContext.response == null
      ? new RestResponse()
      : RestContext.response;
    RestContext.response = res;
    try {
      res.statusCode = process(req);
    } catch (Exception e) {
      // Unexpected: let LINE redeliver (redelivery is idempotent thanks to Webhook_Event_Id__c).
      res.statusCode = 500;
    }
  }

  private static Integer process(RestRequest req) {
    Blob body = req?.requestBody;
    if (body == null || body.size() == 0 || body.size() > MAX_BODY_BYTES) {
      return 400;
    }
    String destination = readDestination(body.toString());
    if (String.isBlank(destination)) {
      return 400;
    }
    LINE_OA_Configuration__c oa = LineOAConfigSelector.byBotUserIds(
        new Set<String>{ destination }
      )
      .get(destination);
    if (oa == null) {
      return 403;
    }
    String secret = LineCredentialStore.getSecret(oa.Channel_Id__c);
    if (
      !LineSignatureVerifier.isValid(
        body,
        header(req, SIGNATURE_HEADER),
        secret
      )
    ) {
      return 401;
    }

    // Authenticated from here on.
    List<LINE_Webhook_Event__e> events = toPlatformEvents(
      oa.Id,
      body.toString()
    );
    if (events.isEmpty()) {
      // e.g. the console "Verify" button sends "events": []
      return 200;
    }
    for (Database.SaveResult sr : EventBus.publish(events)) {
      if (!sr.isSuccess()) {
        return 500;
      }
    }
    return 200;
  }

  // Reads only the top-level "destination" before the signature is checked, without building the whole object.
  @TestVisible
  private static String readDestination(String rawJson) {
    try {
      JSONParser parser = JSON.createParser(rawJson);
      if (parser.nextToken() != JSONToken.START_OBJECT) {
        return null;
      }
      while (parser.nextToken() != null) {
        if (
          parser.getCurrentToken() == JSONToken.FIELD_NAME &&
          'destination'.equals(parser.getText())
        ) {
          parser.nextToken();
          return parser.getCurrentToken() == JSONToken.VALUE_STRING
            ? parser.getText()
            : null;
        }
        if (
          parser.getCurrentToken() == JSONToken.START_OBJECT ||
          parser.getCurrentToken() == JSONToken.START_ARRAY
        ) {
          parser.skipChildren();
        }
      }
    } catch (JSONException e) {
      return null;
    }
    return null;
  }

  private static List<LINE_Webhook_Event__e> toPlatformEvents(
    Id oaConfigId,
    String rawJson
  ) {
    List<LINE_Webhook_Event__e> result = new List<LINE_Webhook_Event__e>();
    Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(
      rawJson
    );
    List<Object> events = root.get('events') instanceof List<Object>
      ? (List<Object>) root.get('events')
      : new List<Object>();
    for (Object item : events) {
      if (!(item instanceof Map<String, Object>)) {
        continue;
      }
      Map<String, Object> event = (Map<String, Object>) item;
      result.add(
        new LINE_Webhook_Event__e(
          OA_Configuration_Id__c = oaConfigId,
          Webhook_Event_Id__c = event.get('webhookEventId') == null
            ? null
            : String.valueOf(event.get('webhookEventId')).left(40),
          Event_Json__c = JSON.serialize(event)
        )
      );
    }
    return result;
  }

  // Header names can arrive in any case.
  private static String header(RestRequest req, String name) {
    if (req.headers == null) {
      return null;
    }
    for (String key : req.headers.keySet()) {
      if (key != null && key.equalsIgnoreCase(name)) {
        return req.headers.get(key);
      }
    }
    return null;
  }
}
