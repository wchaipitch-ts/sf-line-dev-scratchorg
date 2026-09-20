@IsTest
private class LineSignatureVerifierTest {
  private static final String BODY = '{"destination":"Ubot_a","events":[]}';

  @IsTest
  static void validSignatureIsAccepted() {
    String signature = LineTestFactory.sign(BODY, LineTestFactory.SECRET_A);
    Assert.isTrue(
      LineSignatureVerifier.isValid(
        Blob.valueOf(BODY),
        signature,
        LineTestFactory.SECRET_A
      )
    );
  }

  @IsTest
  static void wrongSecretOrBodyIsRejected() {
    String signature = LineTestFactory.sign(BODY, LineTestFactory.SECRET_A);
    Assert.isFalse(
      LineSignatureVerifier.isValid(
        Blob.valueOf(BODY),
        signature,
        LineTestFactory.SECRET_B
      )
    );
    Assert.isFalse(
      LineSignatureVerifier.isValid(
        Blob.valueOf(BODY + ' '),
        signature,
        LineTestFactory.SECRET_A
      )
    );
  }

  @IsTest
  static void letterCaseMatters() {
    String signature = LineTestFactory.sign(BODY, LineTestFactory.SECRET_A);
    String flipped = signature.equals(signature.toUpperCase())
      ? signature.toLowerCase()
      : signature.toUpperCase();
    Assert.isFalse(
      LineSignatureVerifier.isValid(
        Blob.valueOf(BODY),
        flipped,
        LineTestFactory.SECRET_A
      ),
      'Base64 is case-sensitive; Apex == on Strings is not'
    );
  }

  @IsTest
  static void missingInputsAreRejected() {
    String signature = LineTestFactory.sign(BODY, LineTestFactory.SECRET_A);
    Assert.isFalse(
      LineSignatureVerifier.isValid(null, signature, LineTestFactory.SECRET_A)
    );
    Assert.isFalse(
      LineSignatureVerifier.isValid(
        Blob.valueOf(BODY),
        null,
        LineTestFactory.SECRET_A
      )
    );
    Assert.isFalse(
      LineSignatureVerifier.isValid(
        Blob.valueOf(BODY),
        ' ',
        LineTestFactory.SECRET_A
      )
    );
    Assert.isFalse(
      LineSignatureVerifier.isValid(Blob.valueOf(BODY), signature, null)
    );
    Assert.isFalse(LineSignatureVerifier.constantTimeEquals('abc', 'abcd'));
  }
}
