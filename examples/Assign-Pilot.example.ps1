#requires -Version 5.1
<#
Illustrative, source-checked against IntuneWin32App 1.5.0; never executed against Intune.
Default is a local preview. Execute starts a REQUIRED, immediate pilot deployment.
Use only after isolated-machine tests pass, with an approved existing pilot device group.
This deliberately accepts a previously unassigned app, not general assignment reconciliation.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][guid]$IntuneAppId,
    [Parameter(Mandatory)][guid]$PilotGroupId,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9._-]+$')][string]$ApplicationId,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9._-]+$')][string]$ReleaseId,
    [string]$TenantId,
    [string]$ClientId,
    [switch]$ConfirmedCommercialCloud,
    [switch]$Execute
)
$ErrorActionPreference = 'Stop'
$marker = "ManagedBy=ManualIntuneResearch;ApplicationId=$ApplicationId;ReleaseId=$ReleaseId"
if (-not $Execute) {
    [pscustomobject]@{ Operation = 'AssignRequiredPilot'; IntuneAppId = $IntuneAppId; PilotGroupId = $PilotGroupId; Intent = 'required'; Notification = 'showAll'; Availability = 'Immediate'; DeploymentEvidence = 'Required before execution'; NotesMustEqual = $marker }
    return
}
if (-not $ConfirmedCommercialCloud) { throw 'Confirm commercial-cloud compatibility before execution.' }
if ([string]::IsNullOrWhiteSpace($TenantId) -or [string]::IsNullOrWhiteSpace($ClientId)) { throw 'TenantId and ClientId are required with Execute.' }
if (Get-Module -Name IntuneWin32App) { throw 'Use a fresh process so existing module/authentication state cannot be reused.' }
Import-Module -Name IntuneWin32App -RequiredVersion 1.5.0 -ErrorAction Stop
Connect-MSIntuneGraph -TenantID $TenantId -ClientID $ClientId -Interactive -Scopes @('DeviceManagementApps.ReadWrite.All', 'offline_access') -WarningAction Stop | Out-Null
$app = Get-IntuneWin32App -ID $IntuneAppId -WarningAction Stop
if ($app.notes -ne $marker -or $app.publishingState -ne 'published' -or -not $app.committedContentVersion) { throw 'App identity or published content does not match the approved release.' }
$uri = "https://graph.microsoft.com/v1.0/deviceAppManagement/mobileApps/$IntuneAppId/assignments"
$current = Invoke-RestMethod -Method Get -Uri $uri -Headers $Global:AuthenticationHeader
if (@($current.value).Count -or $current.'@odata.nextLink') { throw 'Assignments already exist. Review them explicitly before any further assignment; this example does not reconcile or overwrite them.' }
Add-IntuneWin32AppAssignmentGroup -Include -ID $IntuneAppId -GroupID $PilotGroupId -Intent required -Notification showAll -WarningAction Stop | Out-Null
$after = Invoke-RestMethod -Method Get -Uri $uri -Headers $Global:AuthenticationHeader
$match = @($after.value | Where-Object { $_.intent -eq 'required' -and $_.target.groupId -eq [string]$PilotGroupId -and $_.target.'@odata.type' -eq '#microsoft.graph.groupAssignmentTarget' })
if ($match.Count -ne 1) { throw 'Pilot assignment not confirmed. Reconcile the tenant before retrying.' }
[pscustomobject]@{ IntuneAppId = $IntuneAppId; PilotGroupId = $PilotGroupId; State = 'PilotAssigned'; InstallationSuccess = 'Not yet measured' }
