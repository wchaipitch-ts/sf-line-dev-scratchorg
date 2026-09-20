@IsTest
private class LineApiClientTest {
  private static LineHttpMock mockHttp() {
    LineHttpMock mock = new LineHttpMock();
    Test.setMock(HttpCalloutMock.class, mock);
    return mock;
  }

  private static LineApiClient client() {
    return LineApiClient.withCredentials(
      LineTestFactory.CHANNEL_A,
      LineTestFactory.SECRET_A
    );
  }

  private static LineApiException expectError(
    LineHttpMock mock,
    Integer status,
    String body
  ) {
    mock.stub('GET', '/v2/bot/info', status, body);
    try {
      client().getBotInfo();
    } catch (LineApiException e) {
      return e;
    }
    Assert.fail('Expected LineApiException for HTTP ' + status);
    return null;
  }

  // ---------- token ----------

  @IsTest
  static void issueTokenPostsFormEncodedCredentials() {
    LineHttpMock mock = mockHttp();
    Test.startTest();
    String token = LineApiClient.withCredentials('1000000001', 'se&cret=x')
      .issueToken();
    Test.stopTest();

    Assert.areEqual(LineHttpMock.FAKE_TOKEN, token);
    HttpRequest req = mock.requestsTo('/oauth2/v3/token')[0];
    Assert.areEqual('POST', req.getMethod());
    Assert.areEqual('https://api.line.me/oauth2/v3/token', req.getEndpoint());
    Assert.areEqual(
      'application/x-www-form-urlencoded',
      req.getHeader('Content-Type')
    );
    Assert.areEqual(
      'grant_type=client_credentials&client_id=1000000001&client_secret=se%26cret%3Dx',
      req.getBody(),
      'Secret must be URL-encoded'
    );
  }

  @IsTest
  static void tokenIsCachedPerChannel() {
    LineHttpMock mock = mockHttp();
    Test.startTest();
    LineApiClient c = client();
    c.getBotInfo();
    c.getQuota();
    client().getQuotaConsumption();
    Test.stopTest();

    Assert.areEqual(
      1,
      mock.requestsTo('/oauth2/v3/token').size(),
      'One token per channel per transaction'
    );
    for (HttpRequest req : mock.requestsTo('/v2/bot/')) {
      Assert.areEqual(
        'Bearer ' + LineHttpMock.FAKE_TOKEN,
        req.getHeader('Authorization')
      );
    }
  }

  @IsTest
  static void clearTokenCacheIssuesNewToken() {
    LineHttpMock mock = mockHttp();
    Test.startTest();
    client().issueToken();
    LineApiClient.clearTokenCache();
    client().issueToken();
    Test.stopTest();
    Assert.areEqual(2, mock.requestsTo('/oauth2/v3/token').size());
  }

  @IsTest
  static void rejectedTokenIsCredentialErrorWithoutSecret() {
    LineHttpMock mock = mockHttp();
    mock.stub(
      'POST',
      '/oauth2/v3/token',
      400,
      '{"error":"invalid_client","error_description":"invalid client"}'
    );
    Test.startTest();
    try {
      client().getBotInfo();
      Assert.fail('Expected LineApiException');
    } catch (LineApiException e) {
      Assert.areEqual(400, e.statusCode);
      Assert.isTrue(e.isTokenError);
      Assert.isTrue(e.isCredentialError());
      Assert.areEqual('invalid client', e.lineMessage);
      Assert.areEqual(
        System.Label.LINE_Error_Credentials_Invalid,
        e.userMessage()
      );
      Assert.isFalse(
        e.getMessage().contains(LineTestFactory.SECRET_A),
        'Secret must not leak'
      );
    }
    Test.stopTest();
    Assert.areEqual(
      0,
      mock.requestsTo('/v2/bot/info').size(),
      'No API call without a token'
    );
  }

  @IsTest
  static void tokenErrorWithOnlyErrorCodeUsesIt() {
    LineHttpMock mock = mockHttp();
    mock.stub('POST', '/oauth2/v3/token', 400, '{"error":"invalid_request"}');
    Test.startTest();
    try {
      client().issueToken();
      Assert.fail('Expected LineApiException');
    } catch (LineApiException e) {
      Assert.areEqual('invalid_request', e.lineMessage);
    }
    Test.stopTest();
  }

  @IsTest
  static void tokenResponseWithoutAccessTokenFails() {
    LineHttpMock mock = mockHttp();
    mock.stub('POST', '/oauth2/v3/token', 200, '{"token_type":"Bearer"}');
    Test.startTest();
    try {
      client().issueToken();
      Assert.fail('Expected LineApiException');
    } catch (LineApiException e) {
      Assert.isTrue(e.isTokenError);
    }
    Test.stopTest();
  }

  @IsTest
  static void forChannelUsesStoredSecret() {
    LineHttpMock mock = mockHttp();
    LineCredentialStore.putSecret(
      LineTestFactory.CHANNEL_B,
      LineTestFactory.SECRET_B
    );
    Test.startTest();
    LineApiClient.forChannel(LineTestFactory.CHANNEL_B).issueToken();
    Test.stopTest();
    Assert.isTrue(
      mock.requestsTo('/oauth2/v3/token')[0]
        .getBody()
        .contains('client_secret=testsecret_b')
    );
  }

  @IsTest
  static void forChannelWithoutSecretIsCredentialError() {
    mockHttp();
    Test.startTest();
    try {
      LineApiClient.forChannel('1999999999');
      Assert.fail('Expected LineApiException');
    } catch (LineApiException e) {
      Assert.isTrue(e.isCredentialError());
    }
    Test.stopTest();
  }

  @IsTest
  static void withCredentialsRequiresBothValues() {
    try {
      LineApiClient.withCredentials(LineTestFactory.CHANNEL_A, ' ');
      Assert.fail('Expected LineApiException');
    } catch (LineApiException e) {
      Assert.isTrue(e.isCredentialError());
    }
  }

  // ---------- endpoints ----------

  @IsTest
  static void getBotInfoParsesResponse() {
    LineHttpMock mock = mockHttp();
    Test.startTest();
    LineApiModels.BotInfo info = client().getBotInfo();
    Test.stopTest();

    Assert.areEqual('Ubot_a', info.userId);
    Assert.areEqual('@111aaaaa', info.basicId);
    Assert.areEqual('OA A', info.displayName);
    Assert.areEqual('https://example.com/oa.png', info.pictureUrl);
    Assert.areEqual(
      'https://api.line.me/v2/bot/info',
      mock.requestsTo('/v2/bot/info')[0].getEndpoint()
    );
  }

  @IsTest
  static void setWebhookEndpointSendsPut() {
    LineHttpMock mock = mockHttp();
    Test.startTest();
    client()
      .setWebhookEndpoint(
        'https://example.my.salesforce-sites.com/linewebhook/services/apexrest/line/webhook'
      );
    Test.stopTest();

    HttpRequest req = mock.requestsTo('/webhook/endpoint')[0];
    Assert.areEqual('PUT', req.getMethod());
    Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
      req.getBody()
    );
    Assert.areEqual(
      'https://example.my.salesforce-sites.com/linewebhook/services/apexrest/line/webhook',
      body.get('endpoint')
    );
    Assert.isTrue(req.getHeader('Content-Type').startsWith('application/json'));
  }

  @IsTest
  static void testWebhookEndpointReturnsResult() {
    LineHttpMock mock = mockHttp();
    Test.startTest();
    LineApiModels.WebhookTestResult result = client().testWebhookEndpoint(null);
    Test.stopTest();

    Assert.isTrue(result.success);
    Assert.areEqual(200, result.statusCode);
    Assert.areEqual('OK', result.reason);
    Assert.areEqual(
      '{}',
      mock.requestsTo('/webhook/test')[0].getBody(),
      'Null endpoint is omitted'
    );
  }

  @IsTest
  static void getProfileEncodesUserId() {
    LineHttpMock mock = mockHttp();
    Test.startTest();
    LineApiModels.Profile profile = client().getProfile('Ucustomer1');
    Test.stopTest();

    Assert.areEqual('Somchai', profile.displayName);
    Assert.areEqual('th', profile.language);
    Assert.areEqual(
      'https://api.line.me/v2/bot/profile/Ucustomer1',
      mock.requestsTo('/v2/bot/profile/')[0].getEndpoint()
    );
  }

  @IsTest
  static void pushSendsRetryKeyAndMessages() {
    LineHttpMock mock = mockHttp();
    Test.startTest();
    LineApiModels.PushResult result = client()
      .push(
        'Ucustomer1',
        new List<LineApiModels.Message>{
          LineApiModels.textMessage('สวัสดีครับ'),
          LineApiModels.imageMessage(
            'https://example.com/a.jpg',
            'https://example.com/p.jpg'
          )
        },
        null
      );
    Test.stopTest();

    HttpRequest req = mock.requestsTo('/v2/bot/message/push')[0];
    String retryKey = req.getHeader('X-Line-Retry-Key');
    Assert.isTrue(
      Pattern.matches(
        '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
        retryKey
      ),
      'Retry key must be a UUID: ' + retryKey
    );
    Assert.areEqual(retryKey, result.retryKey);
    Assert.isFalse(result.alreadyAccepted);
    Assert.areEqual('461230966842064897', result.sentMessages[0].id);

    Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
      req.getBody()
    );
    Assert.areEqual('Ucustomer1', body.get('to'));
    List<Object> messages = (List<Object>) body.get('messages');
    Map<String, Object> text = (Map<String, Object>) messages[0];
    Assert.areEqual('text', text.get('type'));
    Assert.areEqual('สวัสดีครับ', text.get('text'));
    Assert.isFalse(
      text.containsKey('originalContentUrl'),
      'Nulls are suppressed'
    );
    Assert.areEqual('image', ((Map<String, Object>) messages[1]).get('type'));
  }

  @IsTest
  static void pushReusesGivenRetryKey() {
    LineHttpMock mock = mockHttp();
    String key = '123e4567-e89b-12d3-a456-426614174000';
    Test.startTest();
    client()
      .push(
        'Ucustomer1',
        new List<LineApiModels.Message>{ LineApiModels.textMessage('hi') },
        key
      );
    Test.stopTest();
    Assert.areEqual(
      key,
      mock.requestsTo('/message/push')[0].getHeader('X-Line-Retry-Key')
    );
  }

  @IsTest
  static void push409IsTreatedAsAccepted() {
    LineHttpMock mock = mockHttp();
    mock.stub(
      'POST',
      '/v2/bot/message/push',
      409,
      '{"message":"The retry key is already accepted","sentMessages":[{"id":"461230966842064897"}]}'
    );
    Test.startTest();
    LineApiModels.PushResult result = client()
      .push(
        'Ucustomer1',
        new List<LineApiModels.Message>{ LineApiModels.textMessage('hi') },
        null
      );
    Test.stopTest();

    Assert.isTrue(result.alreadyAccepted);
    Assert.areEqual('461230966842064897', result.sentMessages[0].id);
  }

  @IsTest
  static void push429MonthlyLimitIsReadable() {
    LineHttpMock mock = mockHttp();
    mock.stub(
      'POST',
      '/v2/bot/message/push',
      429,
      '{"message":"You have reached your monthly limit."}'
    );
    Test.startTest();
    try {
      client()
        .push(
          'Ucustomer1',
          new List<LineApiModels.Message>{ LineApiModels.textMessage('hi') },
          null
        );
      Assert.fail('Expected LineApiException');
    } catch (LineApiException e) {
      Assert.isTrue(e.isMonthlyLimit());
      Assert.isFalse(e.isRetryable(), 'Monthly limit is not transient');
      Assert.areEqual(System.Label.LINE_Error_Monthly_Limit, e.userMessage());
    }
    Test.stopTest();
  }

  @IsTest
  static void replySendsTokenAndMessages() {
    LineHttpMock mock = mockHttp();
    Test.startTest();
    client()
      .reply(
        'reply-token-1',
        new List<LineApiModels.Message>{ LineApiModels.textMessage('Linked') }
      );
    Test.stopTest();

    HttpRequest req = mock.requestsTo('/v2/bot/message/reply')[0];
    Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
      req.getBody()
    );
    Assert.areEqual('reply-token-1', body.get('replyToken'));
    Assert.isNull(req.getHeader('X-Line-Retry-Key'), 'Reply has no retry key');
  }

  @IsTest
  static void getContentUsesDataHost() {
    LineHttpMock mock = mockHttp();
    Test.startTest();
    LineApiModels.Content content = client().getContent('4680000000000');
    Test.stopTest();

    Assert.areEqual('fake-binary', content.body.toString());
    Assert.areEqual('image/jpeg', content.contentType);
    Assert.areEqual(11, content.contentLength);
    HttpRequest req = mock.requestsTo('/content')[0];
    Assert.areEqual(
      'https://api-data.line.me/v2/bot/message/4680000000000/content',
      req.getEndpoint()
    );
  }

  @IsTest
  static void getContentTranscodingStatus() {
    LineHttpMock mock = mockHttp();
    mock.stub('GET', '/content/transcoding', 200, '{"status":"processing"}');
    Test.startTest();
    String status = client().getContentTranscodingStatus('4680000000000');
    Test.stopTest();

    Assert.areEqual('processing', status);
    Assert.areEqual(
      'https://api-data.line.me/v2/bot/message/4680000000000/content/transcoding',
      mock.requestsTo('/transcoding')[0].getEndpoint()
    );
  }

  @IsTest
  static void getQuotaAndConsumption() {
    mockHttp();
    Test.startTest();
    LineApiClient c = client();
    LineApiModels.Quota quota = c.getQuota();
    LineApiModels.QuotaConsumption usage = c.getQuotaConsumption();
    Test.stopTest();

    Assert.areEqual('limited', quota.type);
    Assert.areEqual(1000, quota.value);
    Assert.areEqual(42, usage.totalUsage);
  }

  // ---------- error mapping (04 §3) ----------

  @IsTest
  static void error400ShowsLineMessageAndDetails() {
    LineHttpMock mock = mockHttp();
    Test.startTest();
    LineApiException e = expectError(
      mock,
      400,
      '{"message":"The request body has 1 error(s)","details":[{"message":"Length must be between 0 and 5000","property":"messages[0].text"}]}'
    );
    Test.stopTest();

    Assert.areEqual(400, e.statusCode);
    Assert.areEqual('The request body has 1 error(s)', e.lineMessage);
    Assert.areEqual(
      'messages[0].text: Length must be between 0 and 5000',
      e.details[0]
    );
    Assert.isFalse(e.isRetryable());
    Assert.isFalse(e.isCredentialError());
    Assert.isTrue(
      e.userMessage().contains('Length must be between 0 and 5000')
    );
  }

  @IsTest
  static void error401IsCredentialError() {
    LineHttpMock mock = mockHttp();
    Test.startTest();
    LineApiException e = expectError(
      mock,
      401,
      '{"message":"Authentication failed."}'
    );
    Test.stopTest();

    Assert.isTrue(e.isCredentialError());
    Assert.isFalse(e.isTokenError);
    Assert.areEqual(
      System.Label.LINE_Error_Credentials_Invalid,
      e.userMessage()
    );
  }

  @IsTest
  static void error403IsGeneric() {
    LineHttpMock mock = mockHttp();
    Test.startTest();
    LineApiException e = expectError(
      mock,
      403,
      '{"message":"Access to this API is not available for your account"}'
    );
    Test.stopTest();

    Assert.areEqual(403, e.statusCode);
    Assert.isFalse(e.isRetryable());
    Assert.isFalse(e.isCredentialError());
    Assert.areEqual(System.Label.LINE_Error_Generic, e.userMessage());
    Assert.areEqual(
      'Access to this API is not available for your account',
      e.lineMessage
    );
  }

  @IsTest
  static void error409OutsidePushIsAlreadyAccepted() {
    LineHttpMock mock = mockHttp();
    Test.startTest();
    LineApiException e = expectError(mock, 409, '{"message":"Conflict"}');
    Test.stopTest();
    Assert.isTrue(e.isAlreadyAccepted());
  }

  @IsTest
  static void error429RateLimitIsRetryable() {
    LineHttpMock mock = mockHttp();
    Test.startTest();
    LineApiException e = expectError(
      mock,
      429,
      '{"message":"Too many requests"}'
    );
    Test.stopTest();

    Assert.isFalse(e.isMonthlyLimit());
    Assert.isTrue(e.isRetryable());
    Assert.areEqual(System.Label.LINE_Error_Generic, e.userMessage());
  }

  @IsTest
  static void error5xxIsRetryable() {
    LineHttpMock mock = mockHttp();
    Test.startTest();
    LineApiException e = expectError(
      mock,
      503,
      '<html>Service Unavailable</html>'
    );
    Test.stopTest();

    Assert.areEqual(503, e.statusCode);
    Assert.isTrue(e.isRetryable());
    Assert.areEqual(
      'Error',
      e.lineMessage,
      'Non-JSON body falls back to the HTTP status text'
    );
  }

  @IsTest
  static void calloutExceptionIsRetryableStatusZero() {
    LineHttpMock mock = mockHttp();
    mock.stubCalloutException('GET', '/v2/bot/info');
    Test.startTest();
    try {
      client().getBotInfo();
      Assert.fail('Expected LineApiException');
    } catch (LineApiException e) {
      Assert.areEqual(0, e.statusCode);
      Assert.isTrue(e.isRetryable());
    }
    Test.stopTest();
  }

  @IsTest
  static void malformedSuccessBodyThrows() {
    LineHttpMock mock = mockHttp();
    mock.stub('GET', '/v2/bot/info', 200, 'not json');
    Test.startTest();
    try {
      client().getBotInfo();
      Assert.fail('Expected LineApiException');
    } catch (LineApiException e) {
      Assert.areEqual(200, e.statusCode);
    }
    Test.stopTest();
  }

  @IsTest
  static void mediaMessageFactories() {
    LineApiModels.Message video = LineApiModels.videoMessage(
      'https://e.com/v.mp4',
      'https://e.com/v.jpg'
    );
    LineApiModels.Message audio = LineApiModels.audioMessage(
      'https://e.com/a.m4a',
      60000
    );
    Assert.areEqual('video', video.type);
    Assert.areEqual('https://e.com/v.jpg', video.previewImageUrl);
    Assert.areEqual('audio', audio.type);
    Assert.areEqual(60000, audio.duration);
    Assert.isFalse(JSON.serialize(audio, true).contains('previewImageUrl'));
  }
}
