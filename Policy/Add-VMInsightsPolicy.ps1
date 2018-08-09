<#
.SYNOPSIS
  Adds the Policies and Initiatives to configure VM's for VM Insights Preview

.Description
  This script adds the Policies and Initiatives for VM Insights preview to your current subscription or the subscription specified for -SubscriptionId

  Note:
  This script can be re-run if changes are made to the Policies.
  However if changes are made to the parameters, you will need to delete the Policies/Initiative first.

.PARAMETER UseLocalPolicies
    <Optional> Load the policies from local folder instead of https://raw.githubusercontent.com/dougbrad/OnBoardVMInsights/Policy/Policy/

.PARAMETER SubscriptionId
    SubscriptionId to add the Policies/Initiatives to

.PARAMETER Approve
    <Optional> Gives the approval to add the Policies/Initiatives without any prompt

.EXAMPLE
  .\Add-VMInsightsPolicy.ps1

.LINK
    This script is posted to and further documented at the following location:
    http://aka.ms/OnBoardVMInsights
#>

[CmdletBinding()]
param(
    [Parameter(mandatory = $false)][switch]$UseLocalPolicies,
    [Parameter(mandatory = $false)][string]$SubscriptionId,
    [Parameter(mandatory = $false)][switch]$Approve
)

# TODO: Remove the branch
#
# Take policies from here unless run with -UseLocalPolicies
$gitHubSource = "https://raw.githubusercontent.com/dougbrad/OnBoardVMInsights/Policy/Policy/"
if ($UseLocalPolicies) {
    $gitHubSource = ""
}

$policiesToAddJson = @"
[
    {
        "name": "deploy-dependencyagent-windows-vm-preview",
        "displayName": "Deploy Dependency Agent VM extension for Windows VMs - Preview",
        "description": "-",
        "policy": "deploy-dependencyagent-windows-vm.rules.json"
    },
    {
        "name": "deploy-dependencyagent-linux-vm-preview",
        "displayName": "Deploy Dependency Agent VM extension for Linux VMs - Preview",
        "description": "-",
        "policy": "deploy-dependencyagent-linux-vm.rules.json"
    },
    {
        "name": "deploy-loganalytics-windows-vm-preview",
        "displayName": "Deploy Log Analytics VM extension for Windows VMs - Preview",
        "description": "-",
        "policy": "deploy-loganalytics-windows-vm.rules.json",
        "parameter": "deploy-loganalytics-vm.parameters.json"
    },
    {
        "name": "deploy-loganalytics-linux-vm-preview",
        "displayName": "Deploy Log Analytics VM extension for Linux VMs - Preview",
        "description": "-",
        "policy": "deploy-loganalytics-linux-vm.rules.json",
        "parameter": "deploy-loganalytics-vm.parameters.json"
    }
]
"@

$vmInsightsInitiativeJson = @"
{
    "name": "vminsights-initiative-preview",
    "displayName": "Enable VM Insights for VMs - Preview",
    "description": "-",
    "policy": "vminsights.definitions.json",
    "parameters": "vminsights.parameters.json"
}
"@

$logAnalyticsParameterJson = @"
"parameters": {
    "logAnalytics": {
        "value": "[parameters('logAnalytics_1')]"
    }
}
"@

$vmInsightsParametersJson = @"
{
    "logAnalytics_1": {
        "type": "String",
        "metadata": {
            "displayName": "Log Analytics workspace",
            "description": "Select Log Analytics workspace from dropdown list",
            "strongType": "omsWorkspace"
        }
    }
}
"@

$policiesToAdd = $policiesToAddJson | ConvertFrom-Json
$vmInsightsInitiative = $vmInsightsInitiativeJson  | ConvertFrom-Json

#
# First make sure authenticed, select to the WorkspaceSubscriptionId if supplied
#
$account = Get-AzureRmContext
if ($null -eq $account.Account) {
    Write-Output("Account Context not found, please login")
    if ($SubscriptionId) {
        Connect-AzureRmAccount -SubscriptionId $SubscriptionId
    }
    else {
        Connect-AzureRmAccount
    }
}
elseif ($SubscriptionId) {
    if ($account.Subscription.SubscriptionId -eq $SubscriptionId) {
        Write-Output("Subscription: $SubscriptionId is already selected.")
    }
    else {
        Write-Output("Changing to subscription: $SubscriptionId")
        Set-AzureRmContext -SubscriptionId $SubscriptionId
    }
}

Write-Output("Policies and Initiatives for VM Insights will be added to subscription: `n" `
        + $account.Subscription.Name + " ( " + $account.Subscription.SubscriptionId + " )")
if ($Approve -eq $true -or !$PSCmdlet.ShouldProcess("All") -or $PSCmdlet.ShouldContinue("Continue?", "")) {
    Write-Output ""
}
else {
    Write-Output "You selected No - exiting"
    return
}

#
# Add the Policies
#
foreach ($policy in $policiesToAdd ) {
    $parameter = @{}
    if ($policy.parameter) {
        $parameter."Parameter" = $gitHubSource + $policy.parameter
        Write-Verbose("Policy Parameter: " + $parameter."Parameter")
    }

    Write-Verbose("Adding Policy: " + $gitHubSource + $policy.policy)

    New-AzureRmPolicyDefinition `
        -Name $policy.name `
        -DisplayName $policy.displayName `
        -Description $policy.description `
        -Policy ($gitHubSource + $policy.policy) `
        @parameter
}

#
# Add the Initiative (will take any feedback on how to improve this logic)
#
$vmInsightsDefinition = "["
foreach ($policy in $policiesToAdd) {
    $policyDefinitionId = (Get-AzureRmPolicyDefinition -Name $policy.name | Select-Object -ExpandProperty PolicyDefinitionId)
    $vmInsightsDefinition += '{ "policyDefinitionId": "' + $policyDefinitionId + '"'
    if ($policy.parameter) {
        $vmInsightsDefinition += ',' + $logAnalyticsParameterJson
    }
    $vmInsightsDefinition += '},'
}
$vmInsightsDefinition = $vmInsightsDefinition.TrimEnd(",")
$vmInsightsDefinition += "]"

Write-Verbose($vmInsightsDefinition)

New-AzureRmPolicySetDefinition `
    -Name $vmInsightsInitiative.name `
    -DisplayName $vmInsightsInitiative.displayName `
    -Description $vmInsightsInitiative.description `
    -PolicyDefinition $vmInsightsDefinition `
    -Parameter $vmInsightsParametersJson