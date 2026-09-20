/**
 * HTTP mock for every LINE callout in tests (07 §1). Routes by method + path; the longest matching path wins,
 * so `/content/transcoding` beats `/content`. Every route answers with a realistic success body by default;
 * tests override status/body per route. All requests are recorded for assertions.
 */
@IsTest
public class LineHttpMock implements HttpCalloutMock {
  public static final String FAKE_TOKEN = 'fake-access-token';

  public List<HttpRequest> requests = new List<HttpRequest>();
  private List<Route> routes = new List<Route>();

  private class Route {
    String method;
    String path;
    Integer status;
    String body;
    Blob bodyBlob;
    Map<String, String> headers = new Map<String, String>();
    Boolean throwCallout = false;
  }

  public LineHttpMock() {
    stub(
      'POST',
      '/oauth2/v3/token',
      200,
      '{"token_type":"Bearer","access_token":"' +
        FAKE_TOKEN +
        '","expires_in":899}'
    );
    stub(
      'GET',
      '/v2/bot/info',
      200,
      '{"userId":"Ubot_a","basicId":"@111aaaaa","displayName":"OA A","pictureUrl":"https://example.com/oa.png","chatMode":"bot","markAsReadMode":"auto"}'
    );
    stub('PUT', '/v2/bot/channel/webhook/endpoint', 200, '{}');
    stub(
      'POST',
      '/v2/bot/channel/webhook/test',
      200,
      '{"success":true,"timestamp":"2026-09-19T05:38:20.031Z","statusCode":200,"reason":"OK","detail":"200"}'
    );
    stub(
      'GET',
      '/v2/bot/profile/',
      200,
      '{"userId":"Ucustomer1","displayName":"Somchai","pictureUrl":"https://example.com/u.png","language":"th"}'
    );
    stub(
      'POST',
      '/v2/bot/message/push',
      200,
      '{"sentMessages":[{"id":"461230966842064897","quoteToken":"q1"}]}'
    );
    stub(
      'POST',
      '/v2/bot/message/reply',
      200,
      '{"sentMessages":[{"id":"461230966842064898"}]}'
    );
    stubBlob('GET', '/content', 200, Blob.valueOf('fake-binary'), 'image/jpeg');
    stub('GET', '/content/transcoding', 200, '{"status":"succeeded"}');
    stub(
      'GET',
      '/v2/bot/message/quota',
      200,
      '{"type":"limited","value":1000}'
    );
    stub('GET', '/v2/bot/message/quota/consumption', 200, '{"totalUsage":42}');
  }

  /**
   * Sets (or replaces) the response of a route.
   * @param method HTTP method
   * @param path path fragment to match
   * @param status HTTP status
   * @param body JSON body
   * @return this mock
   */
  public LineHttpMock stub(
    String method,
    String path,
    Integer status,
    String body
  ) {
    Route r = route(method, path);
    r.status = status;
    r.body = body;
    r.bodyBlob = null;
    r.throwCallout = false;
    return this;
  }

  /**
   * Sets a binary response (content download).
   * @param method HTTP method
   * @param path path fragment to match
   * @param status HTTP status
   * @param body binary body
   * @param contentType Content-Type header
   * @return this mock
   */
  public LineHttpMock stubBlob(
    String method,
    String path,
    Integer status,
    Blob body,
    String contentType
  ) {
    Route r = route(method, path);
    r.status = status;
    r.body = null;
    r.bodyBlob = body;
    r.headers.put('Content-Type', contentType);
    r.throwCallout = false;
    return this;
  }

  /**
   * Makes a route throw a CalloutException (timeout / no response).
   * @param method HTTP method
   * @param path path fragment to match
   * @return this mock
   */
  public LineHttpMock stubCalloutException(String method, String path) {
    route(method, path).throwCallout = true;
    return this;
  }

  /**
   * @param path path fragment
   * @return the recorded requests whose endpoint contains the fragment
   */
  public List<HttpRequest> requestsTo(String path) {
    List<HttpRequest> result = new List<HttpRequest>();
    for (HttpRequest req : requests) {
      if (req.getEndpoint().contains(path)) {
        result.add(req);
      }
    }
    return result;
  }

  public HttpResponse respond(HttpRequest req) {
    requests.add(req);
    Route match;
    for (Route r : routes) {
      if (
        r.method == req.getMethod() &&
        pathOf(req.getEndpoint()).contains(r.path)
      ) {
        if (match == null || r.path.length() > match.path.length()) {
          match = r;
        }
      }
    }
    HttpResponse res = new HttpResponse();
    if (match == null) {
      res.setStatusCode(404);
      res.setStatus('Not Found');
      res.setBody(
        '{"message":"No mock route for ' +
          req.getMethod() +
          ' ' +
          req.getEndpoint() +
          '"}'
      );
      return res;
    }
    if (match.throwCallout) {
      throw new CalloutException('Read timed out');
    }
    res.setStatusCode(match.status);
    res.setStatus(match.status >= 200 && match.status < 300 ? 'OK' : 'Error');
    for (String header : match.headers.keySet()) {
      res.setHeader(header, match.headers.get(header));
    }
    if (match.bodyBlob != null) {
      res.setBodyAsBlob(match.bodyBlob);
    } else if (match.body != null) {
      res.setHeader('Content-Type', 'application/json');
      res.setBody(match.body);
    }
    return res;
  }

  private Route route(String method, String path) {
    for (Route r : routes) {
      if (r.method == method && r.path == path) {
        return r;
      }
    }
    Route r = new Route();
    r.method = method;
    r.path = path;
    routes.add(r);
    return r;
  }

  private static String pathOf(String endpoint) {
    String withoutHost = endpoint.substringAfter('://').substringAfter('/');
    return '/' + withoutHost.substringBefore('?');
  }
}
