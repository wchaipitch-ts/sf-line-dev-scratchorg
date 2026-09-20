/**
 * Verifies `X-Line-Signature`: Base64(HMAC-SHA256(raw body, channel secret)) (D2, 04 §2).
 */
public inherited sharing class LineSignatureVerifier {
  /**
   * @param rawBody the request body exactly as received (never a re-serialized string)
   * @param signature the `X-Line-Signature` header value
   * @param secret the receiving channel's secret
   * @return true only if the signature matches
   */
  public static Boolean isValid(Blob rawBody, String signature, String secret) {
    if (
      rawBody == null ||
      String.isBlank(signature) ||
      String.isBlank(secret)
    ) {
      return false;
    }
    Blob mac = Crypto.generateMac('hmacSHA256', rawBody, Blob.valueOf(secret));
    return constantTimeEquals(EncodingUtil.base64Encode(mac), signature.trim());
  }

  // Apex `==` on Strings ignores case, which would accept a signature with flipped letter case.
  // Compare case-sensitively and without an early exit, so timing doesn't reveal how much matched.
  @TestVisible
  private static Boolean constantTimeEquals(String expected, String actual) {
    if (expected.length() != actual.length()) {
      return false;
    }
    List<Integer> a = expected.getChars();
    List<Integer> b = actual.getChars();
    Integer diff = 0;
    for (Integer i = 0; i < a.size(); i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
