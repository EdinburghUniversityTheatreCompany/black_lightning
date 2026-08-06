# Scoping the Graph app to its mailboxes

One Entra app registration serves two features, with app-only (client-credentials) auth:

| Feature | Mailbox | Needs |
|---|---|---|
| Reimbursements | `reimbursements@bedlamfringe.co.uk` (plus `@bedlamtheatre.co.uk` when termtime lands) | read, reply, mark read, move, create drafts, **and SharePoint upload** |
| Climate | `climatesensors@bedlamtheatre.co.uk` | read, mark read, move |

Graph **application** permissions are tenant-wide by default. Consenting `Mail.ReadWrite` lets the
app read every mailbox in the organisation, so something has to narrow that. It used to be an
`ApplicationAccessPolicy`. Microsoft is retiring those in favour of
[RBAC for Applications](https://learn.microsoft.com/en-us/exchange/permissions-exo/application-rbac).

Run [`graph-mailbox-rbac.ps1`](graph-mailbox-rbac.ps1). It takes everything as environment
variables or parameters and supports `-WhatIf`. Read the two traps below first.

## Trap 1: RBAC and Entra permissions are a UNION

A resource-scoped `Mail.ReadWrite` in Exchange does **nothing at all** while the same permission is
still consented tenant-wide in Entra. The app keeps its unscoped access and your careful scoping is
decorative.

So revoking the Entra mail consent isn't cleanup you do afterwards. **It's the step that makes the
whole thing work.** The script won't do it for you, deliberately: it's the one action worth taking
with the verification output in front of you.

## Trap 2: RBAC covers Exchange only

There are roles for mail, calendar, contacts and EWS. There's nothing for SharePoint, and the
reimbursements BACS upload uses `/sites` and `/drives`.

So when you revoke consent, take out **only** `Mail.ReadWrite` and `Mail.Send`. **Keep `Sites.*`
and `Files.*`.** Revoke those by accident and batch uploads break, which you won't notice until
someone builds a batch.

## Running it

Get the two IDs from **Entra, Enterprise applications**, not App registrations. The Object ID
differs between those pages, and the App registrations one will fail with
`AADServicePrincipalNotFound`.

```powershell
Connect-ExchangeOnline

$env:BL_GRAPH_APP_ID       = "<Application (client) ID>"
$env:BL_GRAPH_SP_OBJECT_ID = "<Object ID, from Enterprise applications>"

# Reimbursements replies to producers and creates EUSA drafts, so it needs send.
# Listing the termtime address now costs nothing: a scope is a filter, so it
# matches nothing until that mailbox exists, then starts working.
$env:BL_SEND_RECEIVE_MAILBOXES = "reimbursements@bedlamfringe.co.uk,reimbursements@bedlamtheatre.co.uk"

# Climate only reads and files. No send.
$env:BL_READ_ONLY_MAILBOXES    = "climatesensors@bedlamtheatre.co.uk"

./docs/graph-mailbox-rbac.ps1 -WhatIf   # look at what it would do
./docs/graph-mailbox-rbac.ps1           # do it
```

It's idempotent: an existing scope gets its filter updated, an existing assignment is left alone.
Re-run it when you add a mailbox. You need **Organization Management** in Exchange Online.

### Where the reimbursements addresses come from

They're a database value, not a constant: `Reimbursements::CostCentre#receive_mailbox` and
`#send_mailbox`, editable in the portal's Settings screen. To read what production actually uses:

```
kamal app exec -i 'bin/rails runner "Reimbursements::CostCentre.all.each { |c| puts [c.key, c.receive_mailbox, c.send_mailbox].join(%q( | )) }"'
```

## Verifying

The script does this at the end, but the check that matters is the negative one:

```powershell
# Should be InScope True
Test-ServicePrincipalAuthorization -Identity $env:BL_GRAPH_APP_ID `
  -Resource climatesensors@bedlamtheatre.co.uk | Format-Table

# Should be InScope False. This is what proves the scoping bites,
# rather than merely that the grant exists.
Test-ServicePrincipalAuthorization -Identity $env:BL_GRAPH_APP_ID `
  -Resource someone.else@bedlamtheatre.co.uk | Format-Table
```

`Test-ServicePrincipalAuthorization` bypasses the permission cache, so it answers immediately. The
running app doesn't, so allow **30 minutes to 2 hours** after any change.

Nothing breaks while you're setting this up. Until you revoke the Entra consent the app has both
the old grant and the new one, and access is their union. That's exactly why verification comes
before removal.

## Then, by hand

**Order matters.** An `ApplicationAccessPolicy` constrains only Entra-granted permissions, so if
you remove it first, the app gets tenant-wide mail access for as long as that window lasts. Revoke
the consent first and no such window exists.

1. **Entra, Enterprise applications, your app, Permissions.** Revoke `Mail.ReadWrite` and
   `Mail.Send` (the `...` at the end of each row). Keep `Sites.*` and `Files.*`.
2. Check reimbursements still works, then remove the old policy:
   ```powershell
   $policy = Get-ApplicationAccessPolicy | Where-Object { $_.AppId -eq $env:BL_GRAPH_APP_ID }
   Remove-ApplicationAccessPolicy -Identity $policy.Identity
   ```

## Confirming both features still work

- **Reimbursements**: email a receipt in and check a Draft expense appears with the reply sent
  (`Reimbursements::MailboxPollJob`, every 5 minutes). Then build a batch, to exercise the
  SharePoint upload you deliberately didn't revoke.
- **Climate**: send a Govee export to the climate mailbox and check the readings land
  (`Climate::MailboxPollJob`, every 15 minutes).

## If it breaks

A Graph 403 surfaces as `GraphAuth::AuthError`: a Honeybadger alert, plus an email to the IT
subcommittee on the reimbursements side. Re-consenting `Mail.ReadWrite` and `Mail.Send` in Entra
puts things back immediately, unscoped but working, while you re-check the assignment.

## Still outstanding

The app also holds `Sites.ReadWrite.All` and `Files.ReadWrite.All`, tenant-wide, alongside the
`Sites.Selected` it's configured with. Those two are read/write to every site and every file in the
tenant, which makes `Sites.Selected` redundant and is a bigger exposure than the mail permissions
above.

Don't revoke them casually. If the per-site grant behind `Sites.Selected` was never created, the
BACS upload is working *because* of `Sites.ReadWrite.All`. The sequence is: grant the reimbursements
site explicitly (`POST /sites/{id}/permissions` with role `write`), confirm a batch upload still
works, then revoke the two `.All` grants.
