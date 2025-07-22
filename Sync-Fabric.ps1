param (
    [string]$schemaFile,
    [bool]$dryRun = $false
)

$workdir = $PSScriptRoot
$defaultSchemaPath = Join-Path $workdir "My-Schema.ps1"

if (-not $schemaFile -or -not (Test-Path $schemaFile)) {
    if (Test-Path $defaultSchemaPath) {
        $schemaFile = $defaultSchemaPath
    } else {
        Write-Error "Schema file was not provided and default schema file '$defaultSchemaPath' not found."
        exit 1
    }
}

Write-Host "Fabric Sync started with schema file: $schemaFile". $schemaFile
$dryRun = $dryRun ?? $false


# If you are using AZ keystore (reccomended, fill out) the line that starts with AZVault_name


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
Get-EnsuredModule -name "MSAL.PS"
#### Part 1- Init and load modules + user's schema definitions
##
#
Set-Content -Path $logFile -Value "Starting Fabric Sync at $(get-date). Running self-checks and setting fallback values." 
$DataSetName=$DataSetName ?? "data-$(Get-SafeTitle -Name $HuduBaseUrl)"
$WorkspaceName=$WorkspaceName ?? "ws-$(Get-SafeTitle -Name $HuduBaseUrl)"
Set-LoggedStartupItems


$registration = EnsureRegistration -ClientId $clientId -TenantId $tenantId -delegatedPermissions $delegatedPermissions -ApplicationPermissions $ApplicationPermissions
$clientId = $clientId ?? $registration.clientId
$tenantId = $tenantId ?? $registration.tenantId
clear-host

Start-Process "https://microsoft.com/devicelogin"
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