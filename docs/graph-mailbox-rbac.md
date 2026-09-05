# Scoping the Graph app to its mailboxes

One Entra app registration serves two features, with app-only (client-credentials) auth:

| Feature | Mailbox | Needs |
|---|---|---|
| Reimbursements | its cost centre's **receive** and **send** mailboxes, which are different addresses | read, reply, mark read, move, create and delete drafts, **and SharePoint upload** |
| Climate | `climatesensors@bedlamtheatre.co.uk` | read, mark read, move |

Graph **application** permissions are tenant-wide by default. Consenting `Mail.ReadWrite` lets the
app read every mailbox in the organisation, so something has to narrow that. It used to be an
`ApplicationAccessPolicy`. Microsoft is retiring those in favour of
[RBAC for Applications](https://learn.microsoft.com/en-us/exchange/permissions-exo/application-rbac).

Run [`graph-mailbox-rbac.ps1`](graph-mailbox-rbac.ps1). It takes everything as environment
variables or parameters and supports `-WhatIf`. Read the traps below first.

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

# From `bin/rails graph:mailboxes`. Do not type this from memory: the receive
# and send addresses differ. Listing a mailbox that does not exist yet costs
# nothing, since a scope is a filter that matches nothing until it appears.
$env:BL_SEND_RECEIVE_MAILBOXES = "reimbursements@bedlamfringe.co.uk,finance@bedlamfringe.co.uk,reimbursements@bedlamtheatre.co.uk"

# Climate only reads and files. No send.
$env:BL_READ_ONLY_MAILBOXES    = "climatesensors@bedlamtheatre.co.uk"

./docs/graph-mailbox-rbac.ps1 -WhatIf   # look at what it would do
./docs/graph-mailbox-rbac.ps1           # do it
```

It's idempotent: an existing scope gets its filter updated, an existing assignment is left alone.
Re-run it when you add a mailbox. You need **Organization Management** in Exchange Online.

### Trap 3: the scope filter is REPLACED, not appended

`Set-ManagementScope -RecipientRestrictionFilter` overwrites the whole filter with what you pass.
So "add a mailbox" means passing **every** mailbox the app uses, including the ones already
working. Hand it only the new address and you revoke the others, and nothing warns you: the
cmdlet succeeds, and the cost centres it just cut off keep working for up to two hours on the
cached permission before their email-in goes quiet.

Run `-WhatIf` first and read the filter it prints. It shows the complete new filter, so it is the
one place the mistake is visible before it lands.

### Get the mailbox list from the app, never from memory

**A cost centre's send address is a separate column from its receive address, and on the live
system they differ.** Scoping only the receive mailbox passes every check and then 403s on
`sendMail`, which is exactly what happened on 2026-08-06.

So don't type the list. Ask the app:

```
kamal app exec -i 'bin/rails graph:mailboxes'
```

It prints the `$env:` assignments to paste straight in. Both reimbursements mailboxes need
**Mail Full Access**, not `Mail.ReadWrite`: the receive mailbox replies (which needs `Mail.Send`)
and the send mailbox creates, reads back and deletes drafts (which needs `Mail.ReadWrite`).

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

**Status as of 2026-09-05: step 1 is done, step 2 is not.** The app-only token now comes back
carrying `Files.ReadWrite.All`, `Sites.ReadWrite.All` and `Sites.Selected`, and no `Mail.*` at
all, which is what proves the consent was revoked. Decode the `roles` claim of a
client-credentials token if you want to check that again; it is the only way to see this from
outside the tenant.

That has a consequence worth knowing before you debug a 403: **the old distribution group grants
nothing now.** It backed an `ApplicationAccessPolicy`, which constrains Entra-granted permissions,
and the app no longer has any. Adding a mailbox to `Reimbursements App Access` is a convincing
no-op, so authorise mailboxes by re-running this script instead.

That is measured, not reasoned. On 2026-09-05 the group held two members, both Fringe, while four
mailboxes were reading fine over Graph, so at least two were working from outside it. Repeat the
test the same way if you ever need to re-confirm, because it does not depend on knowing which
display name is which address:

```powershell
Get-DistributionGroupMember -Identity "Reimbursements App Access"
```

Compare the count against the mailboxes that actually answer. More working mailboxes than members
means the policy is inert, which makes step 2 below pure cleanup rather than a change in access.

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
