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
$SchemaResult = Convert-HuduSchemaToDataset -HuduSchema $HuduSchema

$WorkspaceName     = $SchemaResult.WorkspaceName
$DatasetName       = $SchemaResult.DatasetName
$DatasetSchema     = $SchemaResult.DatasetDefinition

# Inject company_id into each perCompany table
foreach ($table in $DatasetSchema.tables) {
    if ($table.perCompany -and -not ($table.columns | Where-Object { $_.name -eq 'company_id' })) {
        $table.columns = @(
            @{ name = 'company_id'; dataType = 'Int64' }
        ) + $table.columns
    }
}

$DatasetSchemaJson = $DatasetSchema | ConvertTo-Json -Depth 10

# Set Workspace
$Workspace = Set-Workspace -name $WorkspaceName -token $accessToken
if (-not $Workspace) {Set-PrintAndLog -message "Couldn’t find or create workspace $WorkspaceName. Review your settings and permissions." -Color Red; exit 1}
Set-PrintAndLog -message "Using Workspace $($Workspace | ConvertTo-Json -Depth 10)" -Color Green

# Set Dataset
Set-PrintAndLog "Final Dataset JSON: $DatasetSchemaJson" -Color Yellow
$DataSet = Set-DataSet -name $DataSetName -schemaJson $DatasetSchemaJson -token $accessToken -workspaceId $Workspace.id
if (-not $DataSet) {Set-PrintAndLog -message "Couldn’t find or create dataset $DataSetName. Review your settings and permissions." -Color Red; exit 1}
Set-PrintAndLog -message "Using Dataset $($DataSet | ConvertTo-Json -Depth 10)" -Color Green

#### Part 3- Get useful source data and Tabulate it
##
#
$AllResults = @()
$fetchIdx = 0
$allCompanies = Get-HuduCompanies

foreach ($company in $allCompanies) {
    $Results = @{}
    
    foreach ($f in $HuduSchema.Fetch) {
        $fetchIdx++
        $completionPercentage = Get-PercentDone -Current $fetchIdx -Total $HuduSchema.Fetch.Count

        $name = $f.Name
        if (-not $name -or -not $f.Command -or -not $f.Filter) {
            Write-Warning "Malformed fetch entry: $($f | Out-String)"
            continue
        }

        $table = $HuduSchema.Tables | Where-Object { $_.columns -match $name }
        $isPerCompany = $table.perCompany -eq $true

        if ($isPerCompany) {
            Write-Host "Fetching (per-company): $name for company $($company.name)"

            $raw = & $f.Command
            if ($raw -is [System.Collections.IEnumerable]) {
                $raw = $raw | Where-Object { $_.company_id -eq $company.id }
            }

            $filtered = & $f.Filter $raw

            # Inject company_id
            if ($filtered -is [pscustomobject]) {
                Add-Member -InputObject $filtered -MemberType NoteProperty -Name "company_id" -Value $company.id -Force
            }

            foreach ($prop in $filtered.PSObject.Properties) {
                $Results[$prop.Name] = $prop.Value
            }

            Set-PrintAndLog "$name → $($filtered | ConvertTo-Json -Compress)" -Color Cyan
        }
        else {
            # Only fetch global values once (on first loop)
            if ($company -eq $allCompanies[0]) {
                Write-Host "Fetching (global): $name"

                $raw = & $f.Command
                $filtered = & $f.Filter $raw

                foreach ($prop in $filtered.PSObject.Properties) {
                    $Results[$prop.Name] = $prop.Value
                }

                Set-PrintAndLog "$name → $($filtered | ConvertTo-Json -Compress)" -Color Cyan
            }
        }

        Write-Progress -Activity "Fetching $name... ($fetchIdx / $($HuduSchema.Fetch.Count))" -Status "$completionPercentage%" -PercentComplete $completionPercentage
    }

    $AllResults += [pscustomobject]$Results
}

# Then later, push $AllResults to Fabric table

#### Part 4- Dynamically Submit Data based on how you configured your schema nd tabulation map
##
#
foreach ($tableSchema in $HuduSchema.Tables) {
    $row = @{}
    foreach ($col in $tableSchema.columns) {
        $row[$col] = $Results[$col]  # If missing, will be $null
    }

    Write-Host "[*] Tabulating: $($tableSchema.Name)..."
    foreach ($key in $Results.Keys) {
        Set-Variable -Name $key -Value $Results[$key] -Scope Local
        Set-PrintAndLog "Bound variable `$${key} = $($Results[$key])" -Color DarkGray
    }
    if ($druRun) {
        continue
    }

    try {
        invoke-HuduTabulation `
            -Schema $tableSchema `
            -TableName $tableSchema.name `
            -Token $accessToken `
            -DatasetId $dataset `
            -WorkspaceId $workspace.id `
            -Values $AllResults


    } catch {
        Write-ErrorObjectsToFile -Name "Tabulation-Err" -ErrorObject @{
            Table  = $tableSchema
            Row    = $row
            Error  = $_
        }
    }
}

Write-Host "`n=== Final Tabulation Values ==="
$Results.GetEnumerator() | Sort-Object Name | ForEach-Object {
    Write-Host "$($_.Name): $($_.Value)"
}