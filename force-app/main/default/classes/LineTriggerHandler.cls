/**
 * Minimal trigger handler base. Triggers contain no logic: they call `new <Handler>().run()`.
 * Handlers override only the events they need. Any handler can be bypassed for the rest of the transaction.
 */
public virtual inherited sharing class LineTriggerHandler {
  private static Set<String> bypassedHandlers = new Set<String>();

  // Lets tests drive run() without a real trigger context.
  @TestVisible
  private TriggerOperation operationOverride;

  /**
   * Dispatches to the method for the current trigger operation, unless this handler is bypassed.
   */
  public void run() {
    TriggerOperation operation = operationOverride != null
      ? operationOverride
      : Trigger.operationType;
    if (operation == null || isBypassed(handlerName())) {
      return;
    }
    switch on operation {
      when BEFORE_INSERT {
        beforeInsert();
      }
      when BEFORE_UPDATE {
        beforeUpdate();
      }
      when BEFORE_DELETE {
        beforeDelete();
      }
      when AFTER_INSERT {
        afterInsert();
      }
      when AFTER_UPDATE {
        afterUpdate();
      }
      when AFTER_DELETE {
        afterDelete();
      }
      when AFTER_UNDELETE {
        afterUndelete();
      }
    }
  }

  /**
   * Skips the named handler for the rest of the transaction.
   * @param handlerName the handler class name, e.g. `LineOAConfigTriggerHandler`
   */
  public static void bypass(String handlerName) {
    bypassedHandlers.add(handlerName);
  }

  /**
   * Re-enables a bypassed handler.
   * @param handlerName the handler class name
   */
  public static void clearBypass(String handlerName) {
    bypassedHandlers.remove(handlerName);
  }

  /**
   * @param handlerName the handler class name
   * @return whether the handler is bypassed
   */
  public static Boolean isBypassed(String handlerName) {
    return bypassedHandlers.contains(handlerName);
  }

  @TestVisible
  private String handlerName() {
    // 'LineFooHandler:[...]' or, when namespaced, 'ns.LineFooHandler:[...]'; bypass uses the plain name.
    String name = String.valueOf(this).substringBefore(':');
    // substringAfterLast returns '' when there is no '.', so only strip a prefix that exists.
    return name.contains('.') ? name.substringAfterLast('.') : name;
  }

  protected virtual void beforeInsert() {
    return;
  }
  protected virtual void beforeUpdate() {
    return;
  }
  protected virtual void beforeDelete() {
    return;
  }
  protected virtual void afterInsert() {
    return;
  }
  protected virtual void afterUpdate() {
    return;
  }
  protected virtual void afterDelete() {
    return;
  }
  protected virtual void afterUndelete() {
    return;
  }
}
