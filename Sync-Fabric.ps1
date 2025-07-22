param (
    [string]$schemaFile
)

$workdir = $PSScriptRoot
$schemaFile = $schemaFile ?? (Join-Path $workdir "My-Schema.ps1")

$dryRun = $false # dry run doesnt add your data to powerBI but spits it out to file, which is handy for designing your schema

$HuduBaseUrl= $HuduBaseURL ?? $(read-host "enter hudu URL")
$DataSetName = $DataSetName ?? $(read-host "What name for powerBI/fabric dataset would you like")
$WorkspaceName = $WorkspaceName ?? $(read-host "What name for powerBI/fabric workspace would you like")

# If you are using AZ keystore (reccomended, fill out) the line that starts with AZVault_name
$UseAzureKeyStore= $UseAzureKeyStore ?? $false
$AzVault_Name = "your-vaultname"
$HuduApiKeySecretName = "your-secretname"
$clientIdSecretName = "clientid-secretname"
$tenantIdSecretName = "tenantid-secretname"

foreach ($file in $(Get-ChildItem -Path ".\helpers" -Filter "*.ps1" -File | Sort-Object Name)) {
    Write-Host "Importing: $($file.Name)" -ForegroundColor DarkBlue
    . $file.FullName
}
if ($UseAzureKeyStore) {
    Get-EnsuredModule -name "Az.Keystore"
    if (-not (Get-AzContext)) { Connect-AzAccount | Out-Null }
    $HuduApiKey = Get-AzKeyVaultSecret -VaultName $AzVault_Name -Name $HuduApiKeySecretName -AsPlainText
    $clientId   = Get-AzKeyVaultSecret -VaultName $AzVault_Name -Name $tenantIdSecretName -AsPlainText
    $tenantId = Get-AzKeyVaultSecret -VaultName $AzVault_Name -Name $clientIdSecretName -AsPlainText
} else {
    $HuduApiKey = $HuduApiKey ?? $(Read-Host "Enter API key")
    $clientId = $clientId ?? $(Read-Host "Enter AppId (ClientId) for your PowerBI App Registration [or leave empty to create an app registration later]")
    $clientId = if ([bool]$([string]::IsNullOrWhiteSpace($clientId))) {$null} else {$clientId}
    $tenantId = if ($null -eq $clientId) {$null} else {$(Read-Host "Enter TenantId for your Microsoft Account")}
}
# your schema definitions
Get-EnsuredModule -name "MSAL.PS"

#### Part 1- Init and load modules + user's schema definitions
##
#
Set-Content -Path $logFile -Value "Starting Fabric Sync at $(get-date). Running self-checks and setting fallback values." 
Set-LoggedStartupItems
$DataSetName=$DataSetName ?? "data-$(Get-SafeTitle -Name $HuduBaseUrl)"
$WorkspaceName=$WorkspaceName ?? "ws-$(Get-SafeTitle -Name $HuduBaseUrl)"

Set-PrintAndLog -message "you chose name of $DataSetName and workspace name $WorkspaceName... Importing My schema from $schemaFile..." -Color Green
. $schemaFile

$registration = EnsureRegistration -ClientId $clientId -TenantId $tenantId -delegatedPermissions $delegatedPermissions -ApplicationPermissions $ApplicationPermissions
$clientId = $clientId ?? $registration.clientId
$tenantId = $tenantId ?? $registration.tenantId
clear-host
$tokenResult=$tokenResult ?? $null
if ($null -eq $tokenResult) {Start-Process "https://microsoft.com/devicelogin"} 
$tokenResult = $tokenResult ?? $(Get-MsalToken -ClientId $clientId -TenantId $tenantId -DeviceCode -Scopes $scope)
$accessToken = $accessToken ?? $tokenResult.AccessToken
Write-Host "$(Decode-JwtTokenPayload -Token $accessToken)"

#### Part 2- Find or Create Workspace and Dataset!
##
#
$Workspace = $(Set-Workspace -name $WorkspaceName -token $accessToken)
if ($null -eq $workspace) {set-printandLog -message "Couldnt find or create workspace $WorkspaceName. Review your settings and permissions" -Color Red; exit 1;}
set-printandlog -message "Using Workspace $($Workspace | ConvertTo-Json -Depth 10)" -Color Green

$DataSet = $(Set-DataSet -name $DataSetName -schemaJson $DatasetSchemaJson -token $accessToken -workspaceId $workspace.id)
if ($null -eq $DataSet) {set-printandLog -message "Couldnt find or create DataSet $DataSetName. Review your settings and permissions" -Color Red; exit 1;}
set-printandlog -message "Using Dataset $($Dataset | ConvertTo-Json -Depth 10)" -Color Green

#### Part 3- Get useful source data and Tabulate it
##
#
$fetchIdx=0
foreach ($item in $HuduSchema.Fetch) {
    $fetchIdx=$fetchIdx +1
    $completionPercentage=Get-PercentDone -Current $fetchIdx -Total $HuduFetchMap.count
    $result = & $item.Command
    Set-Variable -Name $item.Name -Value $result
    Set-PrintAndLog "$($item.Name): $($result?.Count ?? 'null')" -Color Cyan
}
# 3.5- transform your data before calculation if desired
if ($all_expirations) {
    $all_expirations = $all_expirations | ForEach-Object {
        $_ | Add-Member -MemberType NoteProperty -Name ParsedExpirationDate `
            -Value ([DateTime]::ParseExact($_.date, "yyyy-MM-dd", $null)) -PassThru
    } | Sort-Object ParsedExpirationDate
}

#### Part 4- Dynamically Submit Data based on how you configured your schema nd tabulation map
##
#
foreach ($tab in $HuduSchema.Tables) {
    try {
        Invoke-TabulationTask -Tab $tab -AllCompanies $all_companies -AccessToken $accessToken -DatasetId $DataSet -DryRun:$DryRun
    } catch {
        Write-ErrorObjectsToFile -Name "Tabulation-Err" -ErrorObject @{
            Func   = $tab.function
            Params = $tab.depends
            Error  = $_
        }
    }
}