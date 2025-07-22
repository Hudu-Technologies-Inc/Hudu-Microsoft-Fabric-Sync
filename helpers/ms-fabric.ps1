$delegatedPermissions = $delegatedPermissions = @("Dataset.ReadWrite.All","Workspace.Read.All")
$ApplicationPermissions = @("Tenant.Read.All","Dataset.ReadWrite.All","Workspace.ReadWrite.All")
$scope= "https://analysis.windows.net/powerbi/api/.default"
# fallback values for improper or null workspace/dataset name

function Get-AuthStrategyMessage {
    param (
        [bool]$clientIdPresent,
        [bool]$tenantIdPresent,
        [bool]$clientSecretPresent
    )
    if (-not $clientIdPresent -or -not $tenantIdPresent) {
        return "Missing Client Id or Tenant Id, we'll start up the registration helper script for you. (tenant id present: $tenantIdPresent; client id preseent $clientIdPresent)"
    } elseif (-not $clientSecretPresent) {
        return "Client Id and Tenant Id present, but no ClientSecret. We'll assume that you want to use -deviceCode interactive authentication. (good for testing, not good for backgrounded, noninteractive use)"
    } else {
        return "Client Id and Tenant Id present, ClientSecret Present. Assuming fully noninteractive use! Be sure you have Azure Keystore set up!!."
    }
}


function Convert-HuduSchemaToDataset {
    param (
        [Parameter(Mandatory)]
        $HuduSchema
    )

    $FetchMap = @{}
    foreach ($f in $HuduSchema.Fetch) {
        $FetchMap[$f.Name] = $f
    }

    $Tables = @()
    foreach ($table in $HuduSchema.Tables) {
        $columns = @()
        foreach ($colName in $table.columns) {
            $fetch = $FetchMap[$colName]
            $columns += [pscustomobject]@{
                name     = $colName
                dataType = $fetch.dataType ?? "String"
            }
        }

        $Tables += [pscustomobject]@{
            name    = $table.name
            columns = $columns
        }
    }

    return [pscustomobject]@{
        WorkspaceName     = $HuduSchema.WorkspaceName
        DatasetName       = $HuduSchema.DatasetName
        DatasetDefinition = [pscustomobject]@{
            name         = $HuduSchema.DatasetName
            defaultMode  = "Push"
            tables       = $Tables
        }
    }
}

function Set-Workspace {
    param (
        [string]$name,
        [string]$token
    )

    Set-PrintAndLog -message "Looking for a workspace with name: $name"

    $groups = Invoke-RestMethod -Uri "https://api.powerbi.com/v1.0/myorg/groups" -Headers @{ Authorization = "Bearer $token" }
    $workspace = $groups.value | Where-Object { $_.name -eq $name }

    if ($null -ne $workspace) {
        Set-PrintAndLog -message "Workspace found: $name (ID: $($workspace.id))"
        return $workspace
    }

    Set-PrintAndLog -message "Workspace not found. Creating new workspace: $name"
    $body = @{ name = $name } | ConvertTo-Json
    $workspace = Invoke-RestMethod -Uri "https://api.powerbi.com/v1.0/myorg/groups" -Method Post -Headers @{ Authorization = "Bearer $token" } -Body $body -ContentType "application/json"

    Set-PrintAndLog -message "Workspace created: $name (ID: $($workspace.id))"
    return $workspace
}

function Set-DataSet {
    param (
        [string]$name,
        [PSCustomObject]$schemaJson,
        [string]$token,
        [string]$workspaceId
    )

    Set-PrintAndLog -message "Looking for dataset named: $name"

    $datasets = Invoke-RestMethod -Uri "https://api.powerbi.com/v1.0/myorg/groups/$workspaceId/datasets" -Headers @{ Authorization = "Bearer $token" }
    $dataset = $datasets.value | Where-Object { $_.name -eq $name }

    if ($null -ne $dataset) {
        Set-PrintAndLog -message "Dataset found: $name (ID: $($dataset.id))"
        return $dataset.id
    }

    Set-PrintAndLog -message "Dataset not found. Creating new dataset: $name with schema from $schemaFile - $($schemaJson | ConvertTo-Json -Depth 10)"

    $dataset = Invoke-RestMethod -Uri "https://api.powerbi.com/v1.0/myorg/groups/$workspaceId/datasets" `
        -Method Post -Headers @{ Authorization = "Bearer $token" } -Body $schemaJson -ContentType "application/json"

    Set-PrintAndLog -message "Dataset created: $name (ID: $($dataset.id))"
    return $dataset.id
}

function Push-DataToTable {
    param (
        [string]$workspaceId,
        [string]$datasetId,
        [string]$tableName,
        [array]$rows,
        [string]$token
    )

    $rows = @($rows) # Force into array
    $uri = "https://api.powerbi.com/v1.0/myorg/groups/$workspaceId/datasets/$datasetId/tables/$tableName/rows"

    $payload = @{rows = $rows} | ConvertTo-Json -Depth 10
    Set-PrintAndLog -message "Pushing $($rows.Count) rows to table [$tableName]... $payload"

    $result = Invoke-RestMethod -Uri $uri -Method Post -Headers @{ Authorization = "Bearer $token" } `
        -ContentType "application/json" -Body $payload

    Set-PrintAndLog -message "Push result: $($result | ConvertFrom-Json | Out-String)"
}

function Invoke-HuduTabulation {
    param (
        [Parameter(Mandatory)]
        [pscustomobject]$Schema,

        [Parameter(Mandatory)]
        [string]$Token,

        [Parameter(Mandatory)]
        [string]$DatasetId,

        [Parameter(Mandatory)]
        [string]$WorkspaceId,
        
        [Parameter(Mandatory)]
        [string]$TableName,

        [Parameter(Mandatory)]
        [hashtable[]]$Values

    )


    Write-Host "`n[+]Pushing : $TableName..." -ForegroundColor Cyan
    Write-Host "Values:" ($Values | ConvertTo-Json -Depth 5)

    # Run tabulation function
        # Deduplicate and clean nulls (flatten single-level only)
        $safeData = @()

        if ($Schema.perCompany) {
        foreach ($company in $all_companies) {
            $row = @{}
            if ($Schema.columns -contains 'company_id') {
                $row.company_id = $company.id
            }
            if ($Schema.columns -contains 'company_name') {
                $row.company_name = $company.name
            }            

            foreach ($colName in $Schema.columns) {
                $entry = $Values | Where-Object { $_.company_id -eq $company.id }
                $val = if ($entry) { $entry[0][$colName] } else { 0 }
                $row[$colName] = if ($null -ne $val) { $val } elseif ($val -is [string]) { "" } else { 0 }
            }

            $safeData += [pscustomobject]$row
            Set-PrintAndLog "Tabulated row:`n$($row | ConvertTo-Json -Depth 10)" -Color Yellow
        }
    } else {
        $row = @{}
        foreach ($colName in $Schema.columns) {
            $val = if ($Values.Count -gt 0) { $Values[0][$colName] } else { 0 }
            $row[$colName] = if ($null -ne $val) { $val } elseif ($val -is [string]) { "" } else { 0 }
        }
        $safeData += [pscustomobject]$row
        Set-PrintAndLog "Tabulated row:`n$($row | ConvertTo-Json -Depth 10)" -Color Yellow
    }

        foreach ($k in $row.Keys) {
            $val = $row[$k]
            if ($null -eq $val -or ($val -is [string] -and $val -eq '')) {
                Set-PrintAndLog "WARNING: Column [$k] is null or empty." -Color DarkYellow
            }
        }
    # Compose parameters
    $Params = @{
        workspaceId = $workspaceId
        datasetId = $DatasetId
        TableName = $TableName
        Token     = $Token
        rows      = $safeData
    }
    # Push to Power BI (or your target)
    Push-DataToTable @Params
}
