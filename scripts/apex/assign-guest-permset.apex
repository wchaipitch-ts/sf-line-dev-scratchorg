// Assigns LINE_Webhook_Guest to the LineWebhook Site's guest user (05 Part C3). Idempotent.
// Skips quietly when the permission set is not deployed yet (before M1).

List<PermissionSet> guestPs = [SELECT Id FROM PermissionSet WHERE Name = 'LINE_Webhook_Guest' LIMIT 1];
List<Site> sites = [SELECT GuestUserId FROM Site WHERE Name = 'LineWebhook' LIMIT 1];
if (guestPs.isEmpty() || sites.isEmpty() || sites[0].GuestUserId == null) {
    System.debug(LoggingLevel.INFO, 'Guest permission set or LineWebhook site not found; skipped.');
} else {
    Integer existing = [
        SELECT COUNT()
        FROM PermissionSetAssignment
        WHERE PermissionSetId = :guestPs[0].Id AND AssigneeId = :sites[0].GuestUserId
    ];
    if (existing == 0) {
        insert new PermissionSetAssignment(AssigneeId = sites[0].GuestUserId, PermissionSetId = guestPs[0].Id);
    }
    System.debug(LoggingLevel.INFO, 'LINE_Webhook_Guest assigned to the LineWebhook guest user.');
}
