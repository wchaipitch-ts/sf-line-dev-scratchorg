/**
 * Package namespace at runtime. The source never contains the prefix, so the same code works in namespaced
 * scratch orgs, subscriber orgs and non-namespaced dev orgs (DECISIONS DEC-08).
 */
public inherited sharing class LineNamespace {
  private static String cachedPrefix;

  /**
   * @return the namespace prefix without separator (e.g. `lineconn`), or an empty string when not namespaced
   */
  public static String prefix() {
    if (cachedPrefix == null) {
      // Namespaced orgs report the class as '<ns>.LineNamespace'.
      String className = LineNamespace.class.getName();
      cachedPrefix = className.contains('.')
        ? className.substringBefore('.')
        : '';
    }
    return cachedPrefix;
  }

  /**
   * @return `<ns>__` for API names of package components, or an empty string when not namespaced
   */
  public static String apiPrefix() {
    return String.isEmpty(prefix()) ? '' : prefix() + '__';
  }

  /**
   * @return the path of the webhook REST resource, e.g. `/services/apexrest/<ns>/line/webhook` (D1)
   */
  public static String webhookPath() {
    return '/services/apexrest/' +
      (String.isEmpty(prefix()) ? '' : prefix() + '/') +
      'line/webhook';
  }
}
