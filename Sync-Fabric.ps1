param (
    [string]$schemaFile,
    [bool]$dryRun = $false
)
#### Part 0- Set up
##
#
$workdir = $PSScriptRoot
$defaultSchemaPath = Join-Path $workdir "My-Schema.ps1"
if (-not $schemaFile -or -not (Test-Path $schemaFile)) {$schemaFile = $defaultSchemaPath}

Write-Host "Fabric Sync started with schema file: $schemaFile $(if ($dryRun) {'in dry run mode.'})"
. $schemaFile
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
    $clientSecret = ConvertTo-SecureString -String "$(Get-AzKeyVaultSecret -VaultName $AzVault_Name -Name $clientSecretName -AsPlainText)" -AsPlainText -Force
} else {
    $HuduApiKey = $HuduApiKey ?? $(Read-Host "Enter API key")
    $clientId = $clientId ?? $(Read-Host "Enter AppId (ClientId) for your PowerBI App Registration [or leave empty to create an app registration later]")
    $clientId = if ([bool]$([string]::IsNullOrWhiteSpace($clientId))) {$null} else {$clientId}
    $tenantId = $tenantId ?? $(if ($null -eq $clientId) {$null} else {$(Read-Host "Enter TenantId for your Microsoft Account")})
}
#### Part 1- Determine authentication strategy and get access token for Power BI / Fabric; Initialize Logfile
##
#
Get-EnsuredModule -name "MSAL.PS"
Set-Content -Path $logFile -Value "Starting Fabric Sync at $(get-date). Running self-checks and setting fallback values." 
$WorkspaceName=$WorkspaceName ?? "ws-$(Get-SafeTitle -Name $HuduBaseUrl)"
Set-LoggedStartupItems
$registration = EnsureRegistration -ClientId $clientId -TenantId $tenantId -delegatedPermissions $delegatedPermissions -ApplicationPermissions $ApplicationPermissions
$clientId = $clientId ?? $registration.clientId
$tenantId = $tenantId ?? $registration.tenantId

if ($null -ne $clientSecret) {
    Set-PrintAndLog -message "client secret was retrieved. Assuming application auth." -Color Green
    $tokenResult = Get-MsalToken -ClientId $clientId -TenantId $tenantId -ClientSecret $clientSecret -Scopes $scope
    $accessToken = $accessToken ?? $tokenResult.AccessToken
} else {
    Set-PrintAndLog -message "No client secret was retrieved. Assuming Device Login." -Color Green
    Start-Process "https://microsoft.com/devicelogin"
    $tokenResult = $tokenResult ?? $(Get-MsalToken -ClientId $clientId -TenantId $tenantId -DeviceCode -Scopes $scope)
    $accessToken = $accessToken ?? $tokenResult.AccessToken
}


Write-Host "$(Decode-JwtTokenPayload -Token $accessToken)"

#### Part 2- Find or Create Workspace and Dataset!
##
$WorkspaceName = $HuduSchema.WorkspaceName
$DataSetName   = $HuduSchema.DatasetName
$DatasetSchemaJson = Convert-HuduSchemaToDatasetJson -Schema $HuduSchema

# Set Workspace
$Workspace = Set-Workspace -name $WorkspaceName -token $accessToken
if (-not $Workspace) {Set-PrintAndLog -message "Couldn’t find or create workspace $WorkspaceName. Review your settings and permissions." -Color Red; exit 1}
Set-PrintAndLog -message "Using Workspace $($Workspace | ConvertTo-Json -Depth 10)" -Color Green

# Set Dataset
$DataSet = Set-DataSet -name $DataSetName -schemaJson $DatasetSchemaJson -token $accessToken -workspaceId $Workspace.id
if (-not $DataSet) {Set-PrintAndLog -message "Couldn’t find or create dataset $DataSetName. Review your settings and permissions." -Color Red; exit 1}
Set-PrintAndLog -message "Using Dataset $($DataSet | ConvertTo-Json -Depth 10)" -Color Green

#### Part 3- Get useful source data and Tabulate it
##
#
$fetchIdx=0
foreach ($f in $HuduSchema.Fetch) {
    $fetchIdx=$fetchIdx +1
    $completionPercentage=Get-PercentDone -Current $fetchIdx -Total $HuduSchema.Fetch.count
    $name = $f.Name
    Write-Host "Fetching: $name"
    $result = & $f.Command
    if ($f.Filter) {
        $result = & $f.Filter.Invoke($result)
    }
    Set-Variable -Name $name -Value $result -Scope Global
    Set-PrintAndLog "$name count: $($result?.Count ?? 'null')" -Color Cyan
    Write-Progress -Activity "Fetching $title... ($fetchIdx / $($HuduSchema.Fetch.count))" -Status "$completionPercentage%" -PercentComplete $completionPercentage
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