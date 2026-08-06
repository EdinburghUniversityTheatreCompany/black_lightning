<#
.SYNOPSIS
  Scopes the Black Lightning Entra app to just its mailboxes, using RBAC for
  Applications in Exchange Online (the replacement for Application Access
  Policies).

.DESCRIPTION
  Creates the Exchange service principal pointer, a management scope per access
  level, and the role assignments. Then verifies, and tells you what to do by
  hand afterwards — the two manual steps are deliberate, see NOTES.

  Set the variables as environment variables and run it, or pass them as
  parameters. Supports -WhatIf.

.PARAMETER SendReceiveMailboxes
  Mailboxes the app must read AND send from — reimbursements (it replies to
  producers and creates EUSA drafts). Gets "Application Mail Full Access".

  Listing a mailbox that does not exist yet is free: a management scope is a
  filter, so it matches nothing until the mailbox appears, then starts working.

.PARAMETER ReadOnlyMailboxes
  Mailboxes the app only reads and files — climate CSV exports. Gets
  "Application Mail.ReadWrite": read, mark read, move. No send.

.EXAMPLE
  $env:BL_GRAPH_APP_ID           = "00000000-0000-0000-0000-000000000000"
  $env:BL_GRAPH_SP_OBJECT_ID     = "11111111-1111-1111-1111-111111111111"
  $env:BL_SEND_RECEIVE_MAILBOXES = "reimbursements@bedlamfringe.co.uk,reimbursements@bedlamtheatre.co.uk"
  $env:BL_READ_ONLY_MAILBOXES    = "climatesensors@bedlamtheatre.co.uk"

  ./graph-mailbox-rbac.ps1 -WhatIf   # see what it would do
  ./graph-mailbox-rbac.ps1           # do it

.NOTES
  Two steps are NOT automated, on purpose:

  1. Revoking the tenant-wide Mail.* consent in Entra. This is the step that
     makes the scoping real — RBAC and Entra permissions are a UNION, so a
     scoped grant does nothing while the unscoped one still exists. It is also
     the only irreversible-feeling step, so it wants a human who has just read
     the verification output.

  2. Removing the old Application Access Policy.

  Get the IDs from Entra > Enterprise applications, NOT App registrations —
  the Object ID differs between those pages and the wrong one fails.

  Needs Organization Management in Exchange Online.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [string]   $AppId                    = $env:BL_GRAPH_APP_ID,
  [string]   $ServicePrincipalObjectId = $env:BL_GRAPH_SP_OBJECT_ID,
  [string]   $DisplayName              = $(if ($env:BL_GRAPH_DISPLAY_NAME) { $env:BL_GRAPH_DISPLAY_NAME } else { "Black Lightning" }),
  [string]   $ScopePrefix              = $(if ($env:BL_GRAPH_SCOPE_PREFIX) { $env:BL_GRAPH_SCOPE_PREFIX } else { "BL" }),
  [string[]] $SendReceiveMailboxes     = @($env:BL_SEND_RECEIVE_MAILBOXES -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }),
  [string[]] $ReadOnlyMailboxes        = @($env:BL_READ_ONLY_MAILBOXES    -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
)

$ErrorActionPreference = 'Stop'

foreach ($required in @{ AppId = $AppId; ServicePrincipalObjectId = $ServicePrincipalObjectId }.GetEnumerator()) {
  if (-not $required.Value) { throw "$($required.Key) is not set. See the .EXAMPLE block in this script." }
}
if (-not $SendReceiveMailboxes -and -not $ReadOnlyMailboxes) {
  throw "No mailboxes given. Set BL_SEND_RECEIVE_MAILBOXES and/or BL_READ_ONLY_MAILBOXES."
}

if (-not (Get-Command Get-ServicePrincipal -ErrorAction SilentlyContinue)) {
  throw "Not connected to Exchange Online. Run Connect-ExchangeOnline first."
}

# An OPATH -or chain, so one scope can cover several mailboxes.
function New-MailboxFilter([string[]] $Addresses) {
  ($Addresses | ForEach-Object { "PrimarySmtpAddress -eq '$_'" }) -join ' -or '
}

function Sync-ManagementScope([string] $Name, [string[]] $Addresses) {
  $filter = New-MailboxFilter $Addresses
  $existing = Get-ManagementScope -Identity $Name -ErrorAction SilentlyContinue

  if ($existing) {
    Write-Host "Scope '$Name' exists; updating its filter." -ForegroundColor Yellow
    if ($PSCmdlet.ShouldProcess($Name, "Set-ManagementScope -RecipientRestrictionFilter `"$filter`"")) {
      Set-ManagementScope -Identity $Name -RecipientRestrictionFilter $filter | Out-Null
    }
  } elseif ($PSCmdlet.ShouldProcess($Name, "New-ManagementScope -RecipientRestrictionFilter `"$filter`"")) {
    New-ManagementScope -Name $Name -RecipientRestrictionFilter $filter | Out-Null
  }
  Write-Host "  scope: $Name -> $filter" -ForegroundColor Green
}

function Sync-RoleAssignment([string] $Name, [string] $Role, [string] $Scope) {
  if (Get-ManagementRoleAssignment -Identity $Name -ErrorAction SilentlyContinue) {
    Write-Host "  assignment: $Name already exists; left alone." -ForegroundColor Yellow
    return
  }
  if ($PSCmdlet.ShouldProcess($Name, "New-ManagementRoleAssignment -Role '$Role' -CustomResourceScope '$Scope'")) {
    New-ManagementRoleAssignment -Name $Name -App $ServicePrincipalObjectId `
                                 -Role $Role -CustomResourceScope $Scope -ErrorAction Stop | Out-Null
    # Confirmed rather than assumed: Exchange Online cmdlets do not always
    # honour $ErrorActionPreference, so a failure can otherwise scroll past
    # under a success message.
    if (-not (Get-ManagementRoleAssignment -Identity $Name -ErrorAction SilentlyContinue)) {
      throw "Role assignment '$Name' did not get created."
    }
    Write-Host "  assignment: $Name ($Role over $Scope)" -ForegroundColor Green
  }
}

# --- 1. The Exchange pointer to the Entra service principal -----------------

if (Get-ServicePrincipal -Identity $AppId -ErrorAction SilentlyContinue) {
  Write-Host "Service principal already registered in Exchange." -ForegroundColor Yellow
} elseif ($PSCmdlet.ShouldProcess($DisplayName, "New-ServicePrincipal -AppId $AppId")) {
  try {
    New-ServicePrincipal -AppId $AppId -ObjectId $ServicePrincipalObjectId `
                         -DisplayName $DisplayName -ErrorAction Stop | Out-Null
  } catch {
    # Overwhelmingly the ObjectId came off the App registrations blade. That page
    # shows the application object, which is a DIFFERENT object from the service
    # principal Exchange wants.
    throw @"
$($_.Exception.Message)

ObjectId '$ServicePrincipalObjectId' is not a service principal in this tenant.
It is almost certainly the App registration's Object ID. Exchange needs the
SERVICE PRINCIPAL object id — Entra > Enterprise applications > your app >
Overview > Object ID. Or:

  Connect-MgGraph -Scopes Application.Read.All
  (Get-MgServicePrincipal -Filter "AppId eq '$AppId'").Id

Then re-run with BL_GRAPH_SP_OBJECT_ID set to that value. Scopes already created
are reused, so re-running is safe.
"@
  }

  if (-not (Get-ServicePrincipal -Identity $AppId -ErrorAction SilentlyContinue)) {
    throw "Service principal for $AppId still not present in Exchange after New-ServicePrincipal."
  }
  Write-Host "Registered service principal '$DisplayName'." -ForegroundColor Green
}

# --- 2 & 3. A scope and an assignment per access level ----------------------

if ($SendReceiveMailboxes) {
  $scope = "$ScopePrefix Send-Receive Mailboxes"
  Sync-ManagementScope  -Name $scope -Addresses $SendReceiveMailboxes
  # Mail Full Access = Mail.ReadWrite + Mail.Send in one role.
  Sync-RoleAssignment   -Name "$ScopePrefix Mail Full Access" -Role "Application Mail Full Access" -Scope $scope
}

if ($ReadOnlyMailboxes) {
  $scope = "$ScopePrefix Read-Only Mailboxes"
  Sync-ManagementScope  -Name $scope -Addresses $ReadOnlyMailboxes
  Sync-RoleAssignment   -Name "$ScopePrefix Mail ReadWrite" -Role "Application Mail.ReadWrite" -Scope $scope
}

# --- 4. Verify --------------------------------------------------------------

if ($WhatIfPreference) {
  Write-Host "`n-WhatIf: nothing was changed, so there is nothing to verify." -ForegroundColor Cyan
  return
}

Write-Host "`nVerifying (this bypasses the permission cache, so it answers now):" -ForegroundColor Cyan
foreach ($mailbox in ($SendReceiveMailboxes + $ReadOnlyMailboxes)) {
  Write-Host "`n  $mailbox" -ForegroundColor Cyan
  Test-ServicePrincipalAuthorization -Identity $AppId -Resource $mailbox |
    Format-Table RoleName, GrantedPermissions, AllowedResourceScope, InScope
}

Write-Host @"

Check InScope is True above, then pick any UNRELATED mailbox and confirm it comes
back False — that proves the scoping bites, rather than merely that the grant exists:

  Test-ServicePrincipalAuthorization -Identity $AppId -Resource someone.else@example.com | Format-Table

Then, by hand:

  1. Entra > Enterprise applications > $DisplayName > Permissions.
     Revoke ONLY Mail.ReadWrite and Mail.Send.
     KEEP Sites.* / Files.* — the BACS upload needs them and RBAC cannot express
     them. Until you do this the app keeps its unscoped access and none of the
     above has any effect.

  2. Remove the old policy:
       Get-ApplicationAccessPolicy | Where-Object { `$_.AppId -eq '$AppId' }
       Remove-ApplicationAccessPolicy -Identity <identity>

Allow 30 minutes to 2 hours for the app's permission cache to turn over.
"@ -ForegroundColor Green
