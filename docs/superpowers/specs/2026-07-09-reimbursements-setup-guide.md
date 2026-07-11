# Reimbursements Portal — Manual Setup Guide (Mick)

Everything the app can't do itself. Companion to
`2026-07-09-reimbursements-portal-design.md`. Nothing here contains secrets; put all
secret *values* in Bitwarden Secrets Manager / Kamal secrets, never in this repo.

## 1. Shared mailbox (~3 min)

Microsoft 365 admin center → **Teams & groups → Shared mailboxes → Add a shared mailbox**:

- Name: `Reimbursements`
- Email: `reimbursements@bedlamfringe.co.uk`

No licence needed (shared mailboxes < 50 GB are free). No DNS changes — the domain's
mail already routes to M365.

You do **not** need to create the `Processed` / `Rejected` folders — the poll job
creates them on first run if missing.

## 2. Entra app registration (~5 min)

[entra.microsoft.com](https://entra.microsoft.com) → **App registrations → New registration**:

- Name: `BlackLightning Reimbursements Mailbox`
- Supported account types: **single tenant**
- Redirect URI: none (this is a daemon app)

Then, in the new app:

1. **API permissions → Add a permission → Microsoft Graph → Application permissions**:
   add `Mail.ReadWrite` and `Mail.Send`. Remove the default delegated `User.Read` if you
   like. Click **Grant admin consent**.
2. **Certificates & secrets → New client secret** (pick 24 months). Copy the secret
   **Value** immediately — it's shown once.
3. From **Overview**, note the **Application (client) ID** and **Directory (tenant) ID**.

## 3. Scope the app to only that mailbox (~5 min, important)

Application permissions are tenant-wide by default — this app could read *every*
mailbox until you restrict it. In Exchange Online PowerShell:

```powershell
Install-Module ExchangeOnlineManagement   # once
Connect-ExchangeOnline

# Mail-enabled security group containing just the shared mailbox
New-DistributionGroup -Name "Reimbursements App Access" -Type Security `
  -PrimarySmtpAddress reimbursements-app-access@bedlamfringe.co.uk
Add-DistributionGroupMember -Identity "Reimbursements App Access" `
  -Member reimbursements@bedlamfringe.co.uk

New-ApplicationAccessPolicy -AppId b874d491-4edf-4b76-839d-84e534c7f7c0 `
  -PolicyScopeGroupId reimbursements-app-access@bedlamfringe.co.uk `
  -AccessRight RestrictAccess `
  -Description "Reimbursements app may only touch its own mailbox"

# Verify (policy can take ~30-60 min to propagate)
Test-ApplicationAccessPolicy -Identity reimbursements@bedlamfringe.co.uk -AppId b874d491-4edf-4b76-839d-84e534c7f7c0  # → Granted
Test-ApplicationAccessPolicy -Identity mick.zijdel@bedlamtheatre.co.uk -AppId b874d491-4edf-4b76-839d-84e534c7f7c0                 # → Denied
```

## 4. Airtable PAT (~2 min)

Create a **new** personal access token at
[airtable.com/create/tokens](https://airtable.com/create/tokens) — separate from
bedlam-bacs' so either can be revoked independently:

- Scopes: `data.records:read`, `data.records:write`
- Access: only the Bedlam Fringe 2026 base

## 5. Gemini key (~0 min)

Reuse the bedlam-bacs `GEMINI_API_KEY`, or mint a fresh one in Google AI Studio if you
want separate quota/revocation.

## 6. Hand the values over — Rails credentials

Black Lightning keeps secrets in per-environment encrypted credentials (no dotenv).
Add the block below to **both** environments:

```bash
cd ~/Stack/Programmeren/BlackLightning
bin/rails credentials:edit --environment development
bin/rails credentials:edit --environment production
```

```yaml
reimbursements:
  azure_tenant_id: "..."            # step 2.3 (Directory ID)
  azure_client_id: "..."            # step 2.3 (Client ID)
  azure_client_secret: "..."        # step 2.2
  azure_secret_expires_on: "2028-07-01"  # expiry you picked in step 2.2 — drives the IT-subcommittee warning email
  airtable_pat: "..."               # step 4
  gemini_api_key: "..."             # step 5
  alert_email: "..."                # IT subcommittee address for secret-expiry / auth-failure alerts
```

`REIMBURSEMENTS_*` environment variables with matching names override credentials if
you ever want to inject via Kamal env instead. A daily job warns `alert_email` from 30
days before `azure_secret_expires_on`, and a Graph "invalid client secret" auth failure
alerts immediately — so rotation shouldn't ever be a surprise.

The mailbox address and all Airtable base/table/field IDs are configuration, not
secrets — they live in Rails credentials (field IDs copied from bedlam-bacs'
`config/field_ids.toml`; already handled in the implementation, nothing for you to do).

## 7. Nothing else (for the producer portal)

MX/DNS: no changes. Airtable schema: no changes. bedlam-bacs: no changes.

---

# Operator tooling (Review / Build Batch / Reconcile / Settings) — extra setup

The finance operator tooling reuses the **same Entra app** as the mailbox poll, but needs
more Graph permission and, per cost centre, SharePoint folders + a send mailbox.

## 8. Expand the Entra app's Graph permissions (~10 min)

Build Batch creates the EUSA email as a **draft in the send mailbox** and uploads receipts +
the BACS xlsx to **SharePoint**. In the existing `BlackLightning Reimbursements Mailbox` app →
**API permissions → Add a permission → Microsoft Graph → Application permissions**, add:

- `Mail.Send` — send/draft from the shared mailbox (already added in step 2 if you followed it).
- **`Sites.Selected`** — SharePoint access, granted **per site** below (NOT tenant-wide). Do
  **not** add `Sites.ReadWrite.All`/`Files.ReadWrite.All` (those would let the app touch every
  site in the tenant). With `Sites.Selected`, file access follows the per-site grant.

**Grant admin consent** for `Sites.Selected`.

### Scope the app to just the Bedlam Fringe + Business Manager SharePoint sites

`Sites.Selected` grants nothing until you explicitly grant the app write access to each site
(same least-privilege idea as the mailbox `ApplicationAccessPolicy` in step 3). Do it once per
site via Microsoft Graph — easiest in **Graph Explorer** (graph.microsoft.com signed in as an
admin) or a script. For **each** of the two sites (Bedlam Fringe, Business Manager):

```http
# 1. Get the site id (host + server-relative path):
GET https://graph.microsoft.com/v1.0/sites/{tenant}.sharepoint.com:/sites/{SiteName}
#    → copy the "id" (looks like {tenant}.sharepoint.com,<guid>,<guid>)

# 2. Grant THIS app write access to THAT site only:
POST https://graph.microsoft.com/v1.0/sites/{site-id}/permissions
Content-Type: application/json
{
  "roles": ["write"],
  "grantedToIdentities": [
    { "application": { "id": "b874d491-4edf-4b76-839d-84e534c7f7c0",
                       "displayName": "BlackLightning Reimbursements Mailbox" } }
  ]
}
```

Repeat step 2 for the Business Manager site. To review/revoke later:
`GET /sites/{site-id}/permissions` and `DELETE /sites/{site-id}/permissions/{perm-id}`.
(Equivalent PnP PowerShell: `Grant-PnPAzureADAppSitePermission -AppId <id> -Site <url> -Permissions Write`.)

**⚠️ When you point a cost centre's SharePoint folders at a NEW site** in Settings, that site
must also get a `Sites.Selected` write grant (repeat step 2 for it) — otherwise uploads 403.

## 9. ⚠️ WARNING — adding a NEW reimbursement mailbox (per cost centre, or a separate send address)

Each cost centre has its own **receive** mailbox (email-in) and **send** mailbox (Build Batch
drafts from it), set in the app at **Settings → the cost centre**. The Azure app can only
touch mailboxes inside the `Reimbursements App Access` security group from step 3 — so
**adding a mailbox in Settings is NOT enough**. If you don't also add it to that group, every
Graph call for it (poll, draft, send) fails with **403 AccessDenied** and that cost centre's
email-in + batch drafting silently break.

When you add ANY new reimbursement mailbox, also run (Exchange Online PowerShell):

```powershell
Connect-ExchangeOnline
# 1. Create the shared mailbox (M365 admin center) as in step 1, e.g. termtime-reimbursements@bedlamfringe.co.uk
# 2. Add it to the group the ApplicationAccessPolicy already scopes to:
Add-DistributionGroupMember -Identity "Reimbursements App Access" -Member <new-mailbox>@bedlamfringe.co.uk
# 3. Verify (policy propagation can take ~30-60 min):
Test-ApplicationAccessPolicy -Identity <new-mailbox>@bedlamfringe.co.uk `
  -AppId b874d491-4edf-4b76-839d-84e534c7f7c0   # → Granted
```

No new `ApplicationAccessPolicy` is needed — one policy scopes the app to the whole group;
you just add members. (The Settings screen shows this warning inline next to the mailbox fields.)

## 10. Where operator emails are sent FROM (deliverability)

Producer + operator emails (rejection / "you've been paid" / batch producer-notifications /
nightly operator alerts) currently go through **ActionMailer → MailerSend** and inherit
`ApplicationMailer`'s default `from:` — `website-noreply@notify.bedlamtheatre.co.uk`. They do
**not** currently send from `@bedlamfringe.co.uk`.

To send them from a Bedlam Fringe address, pick one:

- **(Recommended) Graph send from the shared mailbox** — switch these mailers to
  `GraphClient#send_mail` (already built for Build Batch) from the cost centre's `send_mailbox`.
  Genuinely sends *as* `reimbursements@bedlamfringe.co.uk`, lands in its Sent Items, needs the
  `Mail.Send` perm above (already there) and the mailbox in the access group (§9) — **no DNS/DKIM
  work**. This is what bedlam-bacs did. *(A code change; ask Claude to do it.)*
- **ActionMailer with a Fringe from-address** — verify `bedlamfringe.co.uk` (or a
  `notify.bedlamfringe.co.uk` subdomain) as a **sending domain in MailerSend** (add their
  SPF/DKIM/DMARC DNS records), then set the reimbursements mailers' `from:` to a Fringe address.
  Deliverable, but the mail won't appear in the M365 mailbox's Sent Items.

The EUSA batch email is unaffected — it's a Graph **draft** in the send mailbox (finance reviews
+ sends it manually), so it already goes out from `@bedlamfringe.co.uk`.
