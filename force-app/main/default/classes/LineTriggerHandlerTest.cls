@IsTest
private class LineTriggerHandlerTest {
  private class RecordingHandler extends LineTriggerHandler {
    List<String> calls = new List<String>();

    protected override void beforeInsert() {
      calls.add('beforeInsert');
    }
    protected override void beforeUpdate() {
      calls.add('beforeUpdate');
    }
    protected override void beforeDelete() {
      calls.add('beforeDelete');
    }
    protected override void afterInsert() {
      calls.add('afterInsert');
    }
    protected override void afterUpdate() {
      calls.add('afterUpdate');
    }
    protected override void afterDelete() {
      calls.add('afterDelete');
    }
    protected override void afterUndelete() {
      calls.add('afterUndelete');
    }
  }

  @IsTest
  static void dispatchesEveryOperation() {
    Map<TriggerOperation, String> expected = new Map<TriggerOperation, String>{
      TriggerOperation.BEFORE_INSERT => 'beforeInsert',
      TriggerOperation.BEFORE_UPDATE => 'beforeUpdate',
      TriggerOperation.BEFORE_DELETE => 'beforeDelete',
      TriggerOperation.AFTER_INSERT => 'afterInsert',
      TriggerOperation.AFTER_UPDATE => 'afterUpdate',
      TriggerOperation.AFTER_DELETE => 'afterDelete',
      TriggerOperation.AFTER_UNDELETE => 'afterUndelete'
    };
    for (TriggerOperation op : TriggerOperation.values()) {
      RecordingHandler handler = new RecordingHandler();
      handler.operationOverride = op;
      handler.run();
      Assert.areEqual(
        new List<String>{ expected.get(op) },
        handler.calls,
        'Operation ' + op
      );
    }
  }

  @IsTest
  static void baseMethodsAreNoOps() {
    LineTriggerHandler handler = new LineTriggerHandler();
    for (TriggerOperation op : TriggerOperation.values()) {
      handler.operationOverride = op;
      handler.run();
    }
    Assert.areEqual('LineTriggerHandler', handler.handlerName());
  }

  @IsTest
  static void doesNothingOutsideTrigger() {
    RecordingHandler handler = new RecordingHandler();
    handler.run();
    Assert.isTrue(handler.calls.isEmpty());
  }

  @IsTest
  static void bypassSkipsHandler() {
    RecordingHandler handler = new RecordingHandler();
    handler.operationOverride = TriggerOperation.AFTER_INSERT;
    Assert.areEqual('RecordingHandler', handler.handlerName());

    LineTriggerHandler.bypass('RecordingHandler');
    Assert.isTrue(LineTriggerHandler.isBypassed('RecordingHandler'));
    handler.run();
    Assert.isTrue(handler.calls.isEmpty());

    LineTriggerHandler.clearBypass('RecordingHandler');
    handler.run();
    Assert.areEqual(new List<String>{ 'afterInsert' }, handler.calls);
  }
}
