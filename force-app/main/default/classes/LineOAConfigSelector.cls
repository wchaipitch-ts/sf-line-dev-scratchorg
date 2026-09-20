/**
 * Queries for `LINE_OA_Configuration__c`.
 *
 * `without sharing` (02 §2): used by the webhook (Site guest user, no object access by design) and the platform
 * event handler (Automated Process) to route events. Callers never return these records to users as-is.
 */
public without sharing class LineOAConfigSelector {
  /**
   * @param botUserIds webhook `destination` values
   * @return configurations keyed by `Bot_User_Id__c`
   */
  // System mode by design (02 §2, SECURITY_NOTES §2): the webhook (guest) routes by destination and the guest has
  // no object access; only routing fields are read and none are returned to the requester.
  // code-analyzer-suppress(sfge)
  public static Map<String, LINE_OA_Configuration__c> byBotUserIds(
    Set<String> botUserIds
  ) {
    Map<String, LINE_OA_Configuration__c> result = new Map<String, LINE_OA_Configuration__c>();
    for (LINE_OA_Configuration__c oa : [
      SELECT
        Id,
        Name,
        Channel_Id__c,
        Bot_User_Id__c,
        Basic_Id__c,
        Assigned_Rep__c,
        Is_Active__c,
        OwnerId
      FROM LINE_OA_Configuration__c
      WHERE Bot_User_Id__c IN :botUserIds
      WITH SYSTEM_MODE
    ]) {
      result.put(oa.Bot_User_Id__c, oa);
    }
    return result;
  }
  // code-analyzer-unsuppress(sfge)

  /**
   * @param ids configuration Ids
   * @return configurations keyed by Id
   */
  public static Map<Id, LINE_OA_Configuration__c> byIds(Set<Id> ids) {
    return new Map<Id, LINE_OA_Configuration__c>(
      [
        SELECT
          Id,
          Name,
          Channel_Id__c,
          Bot_User_Id__c,
          Basic_Id__c,
          Assigned_Rep__c,
          Is_Active__c,
          OwnerId
        FROM LINE_OA_Configuration__c
        WHERE Id IN :ids
        WITH SYSTEM_MODE
      ]
    );
  }

  /**
   * @param channelIds LINE channel IDs
   * @return configurations keyed by `Channel_Id__c`
   */
  public static Map<String, LINE_OA_Configuration__c> byChannelIds(
    Set<String> channelIds
  ) {
    Map<String, LINE_OA_Configuration__c> result = new Map<String, LINE_OA_Configuration__c>();
    for (LINE_OA_Configuration__c oa : [
      SELECT
        Id,
        Name,
        Channel_Id__c,
        Bot_User_Id__c,
        Basic_Id__c,
        Assigned_Rep__c,
        Is_Active__c,
        OwnerId
      FROM LINE_OA_Configuration__c
      WHERE Channel_Id__c IN :channelIds
      WITH SYSTEM_MODE
    ]) {
      result.put(oa.Channel_Id__c, oa);
    }
    return result;
  }

  /**
   * @param userId a rep
   * @return the active OAs assigned to the rep, by name
   */
  public static List<LINE_OA_Configuration__c> activeForUser(Id userId) {
    return [
      SELECT
        Id,
        Name,
        Channel_Id__c,
        Bot_User_Id__c,
        Basic_Id__c,
        Assigned_Rep__c,
        Is_Active__c,
        OwnerId
      FROM LINE_OA_Configuration__c
      WHERE Assigned_Rep__c = :userId AND Is_Active__c = TRUE
      WITH SYSTEM_MODE
      ORDER BY Name
      LIMIT 100
    ];
  }
}
