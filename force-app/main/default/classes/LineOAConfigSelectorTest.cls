@IsTest
private class LineOAConfigSelectorTest {
  @TestSetup
  static void setup() {
    LINE_OA_Configuration__c active = LineTestFactory.newOAConfig(
      LineTestFactory.CHANNEL_A,
      LineTestFactory.BOT_A,
      UserInfo.getUserId()
    );
    LINE_OA_Configuration__c inactive = LineTestFactory.newOAConfig(
      LineTestFactory.CHANNEL_B,
      LineTestFactory.BOT_B,
      UserInfo.getUserId()
    );
    inactive.Is_Active__c = false;
    insert new List<LINE_OA_Configuration__c>{ active, inactive };
  }

  @IsTest
  static void findsByBotUserIdChannelIdAndId() {
    Map<String, LINE_OA_Configuration__c> byBot = LineOAConfigSelector.byBotUserIds(
      new Set<String>{ LineTestFactory.BOT_A, 'Unknown' }
    );
    Assert.areEqual(1, byBot.size());
    LINE_OA_Configuration__c oa = byBot.get(LineTestFactory.BOT_A);
    Assert.areEqual(LineTestFactory.CHANNEL_A, oa.Channel_Id__c);

    Assert.areEqual(
      oa.Id,
      LineOAConfigSelector.byChannelIds(
          new Set<String>{ LineTestFactory.CHANNEL_A }
        )
        .get(LineTestFactory.CHANNEL_A)
        .Id
    );
    Assert.isTrue(
      LineOAConfigSelector.byIds(new Set<Id>{ oa.Id }).containsKey(oa.Id)
    );
  }

  @IsTest
  static void activeForUserSkipsInactiveOAs() {
    List<LINE_OA_Configuration__c> result = LineOAConfigSelector.activeForUser(
      UserInfo.getUserId()
    );
    Assert.areEqual(1, result.size());
    Assert.areEqual(LineTestFactory.CHANNEL_A, result[0].Channel_Id__c);
  }
}
