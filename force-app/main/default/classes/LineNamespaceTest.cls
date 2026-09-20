@IsTest
private class LineNamespaceTest {
  @IsTest
  static void prefixMatchesClassName() {
    String className = LineNamespace.class.getName();
    String expected = className.contains('.')
      ? className.substringBefore('.')
      : '';

    Assert.areEqual(expected, LineNamespace.prefix());
    Assert.areEqual(
      String.isEmpty(expected) ? '' : expected + '__',
      LineNamespace.apiPrefix()
    );
  }

  @IsTest
  static void webhookPathIncludesNamespaceWhenPresent() {
    String ns = LineNamespace.prefix();
    String expected = String.isEmpty(ns)
      ? '/services/apexrest/line/webhook'
      : '/services/apexrest/' + ns + '/line/webhook';
    Assert.areEqual(expected, LineNamespace.webhookPath());
  }
}
