param (
    [string]$schemaFile,
    [bool]$dryRun = $false
)
#### Part 0- Set up
##
#
# define sensitive vars to unset at the end
$sensitiveVars = @("clientSecret","HuduApiKey","clientId","tenantId")
$Results     = @{}
$AllResults  = @{}
$workdir = $PSScriptRoot
$defaultSchemaPath = Join-Path $workdir "My-Schema.ps1"
if (-not $schemaFile -or -not (Test-Path $schemaFile)) {$schemaFile = $defaultSchemaPath}
Write-Host "Fabric Sync started with schema file: $schemaFile $(if ($dryRun) {'in dry run mode.'})"
. $schemaFile
foreach ($file in $(Get-ChildItem -Path ".\helpers" -Filter "*.ps1" -File | Sort-Object Name)) {
    Write-Host "Importing: $($file.Name)" -ForegroundColor DarkBlue
    . $file.FullName
}
# get secrets or ascertain alternative path
if ($UseAzureKeyStore) {
    Get-EnsuredModule -name "Az.Keystore"
    if (-not (Get-AzContext)) { Connect-AzAccount | Out-Null }
    $HuduApiKey = Get-AzKeyVaultSecret -VaultName $AzVault_Name -Name $HuduApiKeySecretName -AsPlainText
    $clientId   = Get-AzKeyVaultSecret -VaultName $AzVault_Name -Name $tenantIdSecretName -AsPlainText
    $tenantId = Get-AzKeyVaultSecret -VaultName $AzVault_Name -Name $clientIdSecretName -AsPlainText
    $clientSecret = ConvertTo-SecureString -String "$(Get-AzKeyVaultSecret -VaultName $AzVault_Name -Name $clientSecretName -AsPlainText)" -AsPlainText -Force
    $clientSecret = if ([bool]$([string]::IsNullOrWhiteSpace($clientSecret))) {$null} else {$clientSecret}
} else {
    $HuduApiKey = $HuduApiKey ?? $(Read-Host "Enter API key")
    $clientId = $clientId ?? $(Read-Host "Enter AppId (ClientId) for your PowerBI App Registration [or leave empty to create an app registration later]")
    $clientId = if ([bool]$([string]::IsNullOrWhiteSpace($clientId))) {$null} else {$clientId}
    $tenantId = $tenantId ?? $(if ($null -eq $clientId) {$null} else {$(Read-Host "Enter TenantId for your Microsoft Account")})
}
#### Part 1- Determine authentication strategy and get access token for Power BI / Fabric; Initialize Logfile
##
#
# perform startup checks and kick off registration if client or tenant vars are blank/null
Add-Content -Path $logFile -Value "Starting Fabric Sync at $(Get-Date). Running self-checks and setting fallback values."
$AuthStrategyMessage = Get-AuthStrategyMessage -clientIdPresent [bool]$([string]::IsNullOrWhiteSpace($clientId)) -tenantIdPresent [bool]$([string]::IsNullOrWhiteSpace($tenantId)) -cleintSecretPresent [bool]$([string]::IsNullOrWhiteSpace($clientSecret))
Set-PrintAndLog -message "$AuthStrategyMessage" -color Magenta
Get-EnsuredModule -name "MSAL.PS"
Set-LoggedStartupItems
$registration = EnsureRegistration -ClientId $clientId -TenantId $tenantId -delegatedPermissions $delegatedPermissions -ApplicationPermissions $ApplicationPermissions
$clientId = $clientId ?? $registration.clientId
$tenantId = $tenantId ?? $registration.tenantId
if ($null -ne $clientSecret) {
    Set-PrintAndLog -message "client secret was retrieved. Assuming application auth." -Color Green
    $tokenResult = Get-MsalToken -ClientId $clientId -TenantId $tenantId -ClientSecret $clientSecret -Scopes $scope
    $accessToken =  $tokenResult.AccessToken
} else {
    Set-PrintAndLog -message "No client secret was retrieved. Assuming Device Login." -Color Green
    Start-Process "https://microsoft.com/devicelogin"
    $tokenResult = $(Get-MsalToken -ClientId $clientId -TenantId $tenantId -DeviceCode -Scopes $scope)
    $accessToken =  $tokenResult.AccessToken
}
if ($true -eq $dryRun) {Write-Host "Debugging decoded token in dry-run mode.  $($(Decode-JwtTokenPayload -Token $accessToken) | convertto-Json -depth 3 | Out-String)"}

#### Part 2- Parse user workspace and dataset infos, find if they exist or create them
##
$SchemaResult = Convert-HuduSchemaToDataset -HuduSchema $HuduSchema
$WorkspaceName     = $SchemaResult.WorkspaceName
$DatasetName       = $SchemaResult.DatasetName
$DatasetSchema     = $SchemaResult.DatasetDefinition

# Inject company_id and company_name into each perCompany table
foreach ($table in $DatasetSchema.tables) {
    if ($table.perCompany -and -not ($table.columns | Where-Object { $_.name -eq 'company_id' })) {
        $table.columns = @(
            @{ name = 'company_id'; dataType = 'Int64' }
            @{ name = 'company_name'; dataType = 'String' }            
        ) + $table.columns
    }
}

$DatasetSchemaJson = $DatasetSchema | ConvertTo-Json -Depth 10

# Find or Create Workspace
$Workspace = Set-Workspace -name $WorkspaceName -token $accessToken
if (-not $Workspace) {Set-PrintAndLog -message "Couldn’t find or create workspace $WorkspaceName. Review your settings and permissions." -Color Red; exit 1}
Set-PrintAndLog -message "Using Workspace $($Workspace | ConvertTo-Json -Depth 10)" -Color Green

# Find or Create Dataset
Set-PrintAndLog "Final Dataset JSON: $DatasetSchemaJson" -Color Yellow
$DataSet = Set-DataSet -name $DataSetName -schemaJson $DatasetSchemaJson -token $accessToken -workspaceId $Workspace.id
if (-not $DataSet) {Set-PrintAndLog -message "Couldn’t find or create dataset $DataSetName. Review your settings and permissions." -Color Red; exit 1}
Set-PrintAndLog -message "Using Dataset $($DataSet | ConvertTo-Json -Depth 10)" -Color Green

#### Part 3- Get useful source data and Tabulate it
##
#
$fetchIdx    = 0
$allCompanies = Get-HuduCompanies
# fetch all companies for any tables that might be per-company.
foreach ($f in $HuduSchema.Fetch) {
    $fetchIdx++
    $completionPercentage = Get-PercentDone -Current $fetchIdx -Total $HuduSchema.Fetch.Count

    $name = $f.Name
    if (-not $name -or -not $f.Command -or -not $f.Filter) {
        Write-Warning "Malformed fetch entry: $($f | Out-String); SKIPPING!"
        continue
    }
    # if this table is set up as being per-company
    if ($f.perCompany) {
        foreach ($company in $allCompanies) {
            Write-Host "Fetching: $name (per-company: $($company.name))"
            $raw = & $f.Command
            if ($raw -is [System.Collections.IEnumerable]) {
                $raw = $raw | Where-Object { $_.company_id -eq $company.id }
            }
            $filtered = & $f.Filter $raw
            $row = @{}

            foreach ($prop in $filtered.PSObject.Properties) {
                $row[$prop.Name] = $prop.Value
            }
            #auto-inject company id and name into any per-company metrics
            $row["company_id"] = $company.id
            $row["company_name"] = $company.name

            if (-not $AllResults.ContainsKey($name)) {
                $AllResults[$name] = @()
            }
            $AllResults[$name] += [pscustomobject]$row

            Set-PrintAndLog "$name → $($row | ConvertTo-Json -Compress)" -Color Cyan
        }
    # if this table is set up as generalized data
    } else {
        Write-Host "Fetching: $name (global)"
        $raw = & $f.Command
        $filtered = & $f.Filter $raw

        $row = @{}
        foreach ($prop in $filtered.PSObject.Properties) {
            $row[$prop.Name] = $prop.Value
            $Results[$prop.Name] = $prop.Value
        }

        if (-not $AllResults.ContainsKey($name)) {
            $AllResults[$name] = @()
        }
        $AllResults[$name] += [pscustomobject]$row

        Set-PrintAndLog -message "$name → $($row | ConvertTo-Json -Compress)" -Color Cyan
    }

    Write-Progress -Activity "Fetching $name... ($fetchIdx / $($HuduSchema.Fetch.Count))" -Status "$completionPercentage%" -PercentComplete $completionPercentage
}

#### Part 4- Dynamically Submit Data based on how you configured your schema nd tabulation map
##
#
foreach ($table in $HuduSchema.Tables) {
    $tableName = $table.name
    $isPerCompany = $table.perCompany
    $finalRows = @()

    # enumerate rows in the expected format based on whether table is per-company or not.
    if ($isPerCompany) {
        foreach ($company in $allCompanies) {
            $row = @{ company_id = $company.id }
            foreach ($col in $table.columns) {
                $entries = $AllResults[$col]
                if (-not $entries) { continue }
                $match = $entries | Where-Object { $_.company_id -eq $company.id }
                $row[$col] = if ($match) { $match[0].$col } else { 0 }
            }
            $finalRows += [pscustomobject]$row
        }
    } else {
        $row = @{}
        foreach ($col in $table.columns) {
            $entries = $AllResults[$col]
            if ($entries) {
                $row[$col] = $entries[0].$col
            }
        }
        $finalRows += [pscustomobject]$row
    }

    try {
        # write-data to host for debug and dry-run
        $finalHashRows = $finalRows | ForEach-Object {
            if ($_ -is [hashtable]) { $_ } else {
                $_ | ConvertTo-Json -Depth 10 | ConvertFrom-Json -AsHashtable }}

        # only commit data if not in dry-run
        Write-Host "tabulate: $tableName $($finalHashRows | ConvertTo-Json -depth 8)" -ForegroundColor Yellow
        if ($true -eq $dryRun) {Set-PrintAndLog -message "dry-run, skipping submission of data!" -Color DarkYellow; continue}

        Invoke-HuduTabulation `
            -Schema $table `
            -TableName $tableName `
            -Token $accessToken `
            -DatasetId $dataset `
            -WorkspaceId $workspace.id `
            -Values $finalHashRows
    } catch {
        Write-ErrorObjectsToFile -Name "Tabulation-Err" -ErrorObject @{
            finalRows  = $finalHashRows
            tablename    = $tablename
            Error  = $_
        }
    }
}

Write-Host "`n=== Final Tabulation Values ==="
$Results.GetEnumerator() | Sort-Object Name | ForEach-Object {
    Write-Host "$($_.Name): $($_.Value)"
}
Write-Host "Unsetting vars before next run."
foreach ($var in $sensitiveVars) {
    Unset-Vars -varname $var
}