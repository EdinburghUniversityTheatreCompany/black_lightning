# Scoping the Graph app to its mailboxes (RBAC for Applications)

The app talks to Microsoft Graph with **app-only** (client-credentials) auth through one Entra app
registration, shared by two features:

| Feature | Mailbox | What it does |
|---|---|---|
| Reimbursements | `reimbursements@bedlamfringe.co.uk` | reads receipts, replies, marks read, moves, creates EUSA drafts, **uploads to SharePoint** |
| Climate | `climatesensors@bedlamtheatre.co.uk` | reads Govee CSV exports, marks read, moves |

Graph **application** permissions are tenant-wide by default — consenting `Mail.ReadWrite` lets the
app read every mailbox in the tenant. Something has to narrow that. Historically that was an
`ApplicationAccessPolicy`; Microsoft is retiring those in favour of
[RBAC for Applications](https://learn.microsoft.com/en-us/exchange/permissions-exo/application-rbac).

## Read this before you start

**RBAC and Entra permissions are a UNION, not an intersection.** A resource-scoped `Mail.ReadWrite`
in Exchange RBAC does nothing at all while the same permission is still consented tenant-wide in
Entra — the app keeps its unscoped access and the scoping is decorative. Removing the Entra mail
consent is not optional cleanup; it is the step that makes this work.

**RBAC for Applications covers Exchange only.** It has roles for mail, calendar, contacts and EWS —
nothing for SharePoint. The reimbursements BACS upload uses `/sites` and `/drives`, so its
`Sites.*`/`Files.*` consent must **stay** in Entra. Only remove the `Mail.*` ones.

**Nothing changes in the application.** No new secret, no new app registration, no config change
beyond `CLIMATE_MAILBOX`.

You need **Organization Management** in Exchange Online and **Exchange Administrator** in Entra.

## The two IDs, and the usual mistake

`New-ServicePrincipal` wants IDs from **Entra → Enterprise applications**, *not* App registrations —
the Object ID differs between the two pages and the App registrations one will not work.

- `-AppId` — the Application (client) ID
- `-ObjectId` — the **service principal** object ID from the Enterprise applications page

```powershell
Connect-ExchangeOnline
# Or, to read them without clicking about:
#   Get-MgServicePrincipal -Filter "AppId eq '<app-id>'" | Select-Object Id, AppId, DisplayName
```

## 1. Register the service principal pointer in Exchange

```powershell
New-ServicePrincipal -AppId <application-client-id> `
                     -ObjectId <service-principal-object-id> `
                     -DisplayName "Black Lightning"
```

## 2. Create a scope per mailbox

Least privilege: reimbursements needs to send, climate does not. Two scopes keeps that honest.

```powershell
New-ManagementScope -Name "BL Reimbursements Mailbox" `
  -RecipientRestrictionFilter "PrimarySmtpAddress -eq 'reimbursements@bedlamfringe.co.uk'"

New-ManagementScope -Name "BL Climate Mailbox" `
  -RecipientRestrictionFilter "PrimarySmtpAddress -eq 'climatesensors@bedlamtheatre.co.uk'"
```

If you would rather manage membership than edit filters as mailboxes are added, point a scope at a
mail-enabled security group instead — note it takes the group's **distinguished name**
(`Get-Group <name> | Select-Object DistinguishedName`), and **nested groups are not evaluated**:

```powershell
New-ManagementScope -Name "BL Graph Mailboxes" `
  -RecipientRestrictionFilter "MemberOfGroup -eq 'CN=…,OU=…,DC=…'"
```

## 3. Assign the roles

```powershell
# Reimbursements: read + write + send. "Application Mail Full Access" is
# Mail.ReadWrite + Mail.Send in one role.
New-ManagementRoleAssignment -Name "BL Reimbursements Mail" `
  -App <service-principal-object-id> `
  -Role "Application Mail Full Access" `
  -CustomResourceScope "BL Reimbursements Mailbox"

# Climate: read, mark read, move. No send.
New-ManagementRoleAssignment -Name "BL Climate Mail" `
  -App <service-principal-object-id> `
  -Role "Application Mail.ReadWrite" `
  -CustomResourceScope "BL Climate Mailbox"
```

## 4. Verify BEFORE removing anything

`Test-ServicePrincipalAuthorization` bypasses the permission cache, so it answers immediately.
`InScope` is the column that matters.

```powershell
Test-ServicePrincipalAuthorization -Identity "Black Lightning" `
  -Resource climatesensors@bedlamtheatre.co.uk | Format-Table

Test-ServicePrincipalAuthorization -Identity "Black Lightning" `
  -Resource reimbursements@bedlamfringe.co.uk | Format-Table

# And confirm the scoping actually bites — this should come back InScope False:
Test-ServicePrincipalAuthorization -Identity "Black Lightning" `
  -Resource <some-other-mailbox> | Format-Table
```

Until step 5, the app has both its old Entra grant and the new RBAC grant, and access is their
union — so **nothing breaks while you set this up**. That is why verification comes first.

## 5. Remove the tenant-wide mail consent in Entra

Entra → Enterprise applications → *Black Lightning* → Permissions. Revoke **only**:

- `Mail.ReadWrite`
- `Mail.Send`

**Keep** `Sites.*` / `Files.*` — the BACS upload needs them and RBAC cannot express them.

This is the step that makes the scoping real. Allow 30 minutes to 2 hours for the permission cache
to turn over (`Test-ServicePrincipalAuthorization` bypasses it; the running app does not).

## 6. Remove the old Application Access Policy

```powershell
Get-ApplicationAccessPolicy | Where-Object { $_.AppId -eq "<application-client-id>" }
Remove-ApplicationAccessPolicy -Identity <policy-identity>
```

## 7. Confirm both features still work

- **Reimbursements**: email a receipt to `reimbursements@bedlamfringe.co.uk` and check a Draft
  expense appears with the reply sent (`Reimbursements::MailboxPollJob`, every 5 minutes).
- **Climate**: send a Govee export to `climatesensors@bedlamtheatre.co.uk` and check the readings
  land (`Climate::MailboxPollJob`, every 15 minutes). Also confirm the BACS SharePoint upload still
  works, since that is the permission most easily revoked by accident.

## If it breaks

Symptom is `ErrorAccessDenied` / a Graph 403, surfacing in the app as
`GraphAuth::AuthError` → a Honeybadger alert and, for reimbursements, an email to the IT
subcommittee. Re-consenting `Mail.ReadWrite` + `Mail.Send` in Entra restores the old behaviour
immediately (unscoped, but working) while you re-check the RBAC assignment.
