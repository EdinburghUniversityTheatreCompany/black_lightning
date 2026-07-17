# Reimbursements Portal: Manual Setup Guide (Mick)

Everything the app can't do itself. Companion to
`2026-07-09-reimbursements-portal-design.md`. Nothing here contains secrets; put all
secret *values* in Bitwarden Secrets Manager / Kamal secrets, never in this repo.

## 1. Shared mailbox (~3 min)

Microsoft 365 admin center → **Teams & groups → Shared mailboxes → Add a shared mailbox**:

- Name: `Reimbursements`
- Email: `reimbursements@bedlamfringe.co.uk`

No licence needed (shared mailboxes < 50 GB are free). No DNS changes. The domain's
mail already routes to M365.

You do **not** need to create the `Processed` / `Rejected` folders; the poll job
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
   **Value** immediately; it's shown once.
3. From **Overview**, note the **Application (client) ID** and **Directory (tenant) ID**.

## 3. Scope the app to only that mailbox (~5 min, important)

Application permissions are tenant-wide by default: this app could read *every*
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
[airtable.com/create/tokens](https://airtable.com/create/tokens), separate from
bedlam-bacs' so either can be revoked independently:

- Scopes: `data.records:read`, `data.records:write`
- Access: only the Bedlam Fringe 2026 base

## 5. Gemini key (~0 min)

Reuse the bedlam-bacs `GEMINI_API_KEY`, or mint a fresh one in Google AI Studio if you
want separate quota/revocation.

## 6. Hand the values over (Rails credentials)

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
  azure_secret_expires_on: "2028-07-01"  # expiry you picked in step 2.2 (drives the IT-subcommittee warning email)
  airtable_pat: "..."               # step 4
  gemini_api_key: "..."             # step 5
  alert_email: "..."                # IT subcommittee address for secret-expiry / auth-failure alerts
```

`REIMBURSEMENTS_*` environment variables with matching names override credentials if
you ever want to inject via Kamal env instead. A daily job warns `alert_email` from 30
days before `azure_secret_expires_on`, and a Graph "invalid client secret" auth failure
alerts immediately, so rotation shouldn't ever be a surprise.

The mailbox address and all Airtable base/table/field IDs are configuration, not
secrets; they live in Rails credentials (field IDs copied from bedlam-bacs'
`config/field_ids.toml`; already handled in the implementation, nothing for you to do).

## 7. Nothing else (for the producer portal)

MX/DNS: no changes. Airtable schema: no changes. bedlam-bacs: no changes.

---

## Operator tooling: ongoing setup lives in-app

The finance operator tooling (Review / Build Batch / Reconcile / Settings) adds recurring manual
steps: adding a cost centre's mailboxes, scoping the Graph app to them, granting a SharePoint site,
and choosing where operator emails send from. Those live as an **in-app guide** the finance team and
IT read in context (**Admin → Reimbursements → Setup guide**, `/admin/reimbursements/help`) rather
than in this file, so non-developers can find it and it stays versioned with the UI.

The one-time setup above (§1–6) still applies. Add `Sites.Selected` (granted per-site) and `Mail.Send`
to the same Entra app for Build Batch's SharePoint uploads and EUSA draft.
