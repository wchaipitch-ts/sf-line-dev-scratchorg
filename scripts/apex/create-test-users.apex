// Creates two test reps (Rep A: English, Rep B: Thai) in a scratch org and assigns LINE_Chat_User if it exists.
// Idempotent: users are found again by a stable, org-unique username.
// The profile is picked by permissions, never by name (profile names are localized in Thai orgs; see 07 §1).

String orgKey = UserInfo.getOrganizationId().substring(0, 15).toLowerCase();

// Scratch orgs have only 2 "Salesforce" seats (one is the admin), so "Salesforce Platform" is accepted too
// (it has Contact access). Licences are matched by their stable definition key, not by (localizable) name.
Integer seatsNeeded = 2;
Id profileId;
for (ObjectPermissions op : [
    SELECT Parent.ProfileId, Parent.Profile.UserLicense.TotalLicenses, Parent.Profile.UserLicense.UsedLicenses
    FROM ObjectPermissions
    WHERE
        SobjectType = 'Contact'
        AND PermissionsEdit = TRUE
        AND Parent.IsOwnedByProfile = TRUE
        AND Parent.Profile.UserType = 'Standard'
        AND Parent.Profile.UserLicense.LicenseDefinitionKey IN ('SFDC', 'AUL')
        AND Parent.PermissionsModifyAllData = FALSE
    ORDER BY Parent.Profile.UserLicense.LicenseDefinitionKey DESC, Parent.Profile.CreatedDate
]) {
    UserLicense lic = op.Parent.Profile.UserLicense;
    if (lic != null && lic.TotalLicenses - lic.UsedLicenses >= seatsNeeded) {
        profileId = op.Parent.ProfileId;
        break;
    }
}

Map<String, List<String>> reps = new Map<String, List<String>>{
    'repa' => new List<String>{ 'Rep', 'A', 'en_US', 'en_US' },
    'repb' => new List<String>{ 'Rep', 'B', 'th', 'th_TH' }
};

Map<String, User> byUsername = new Map<String, User>();
for (String key : reps.keySet()) {
    byUsername.put('line.' + key + '.' + orgKey + '@example.com', null);
}
for (User u : [SELECT Id, Username FROM User WHERE Username IN :byUsername.keySet()]) {
    byUsername.put(u.Username, u);
}

List<User> toInsert = new List<User>();
for (String key : reps.keySet()) {
    String username = 'line.' + key + '.' + orgKey + '@example.com';
    if (byUsername.get(username) != null) {
        continue;
    }
    List<String> r = reps.get(key);
    toInsert.add(
        new User(
            Username = username,
            Email = 'line.' + key + '@example.com',
            FirstName = r[0],
            LastName = r[1],
            Alias = 'line' + key.right(1),
            ProfileId = profileId,
            TimeZoneSidKey = 'Asia/Bangkok',
            LanguageLocaleKey = r[2],
            LocaleSidKey = r[3],
            EmailEncodingKey = 'UTF-8'
        )
    );
}
if (!toInsert.isEmpty() && profileId == null) {
    throw new IllegalArgumentException('No profile with Contact edit, without Modify All Data, and ' + seatsNeeded + ' free seats.');
}
insert toInsert;
for (User u : toInsert) {
    byUsername.put(u.Username, u);
}

List<PermissionSet> chatUser = [SELECT Id FROM PermissionSet WHERE Name = 'LINE_Chat_User' LIMIT 1];
if (!chatUser.isEmpty()) {
    Set<Id> userIds = new Set<Id>();
    for (User u : byUsername.values()) {
        userIds.add(u.Id);
    }
    Set<Id> assigned = new Set<Id>();
    for (PermissionSetAssignment psa : [
        SELECT AssigneeId
        FROM PermissionSetAssignment
        WHERE PermissionSetId = :chatUser[0].Id AND AssigneeId IN :userIds
    ]) {
        assigned.add(psa.AssigneeId);
    }
    List<PermissionSetAssignment> psas = new List<PermissionSetAssignment>();
    for (Id userId : userIds) {
        if (!assigned.contains(userId)) {
            psas.add(new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = chatUser[0].Id));
        }
    }
    insert psas;
}

System.debug(LoggingLevel.INFO, 'LINE test users: ' + byUsername.keySet());
