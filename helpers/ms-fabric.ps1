$delegatedPermissions = $delegatedPermissions = @("Dataset.ReadWrite.All","Workspace.Read.All")
$ApplicationPermissions = @("Tenant.Read.All","Dataset.ReadWrite.All","Workspace.ReadWrite.All")
$scope= "https://analysis.windows.net/powerbi/api/.default"
# fallback values for improper or null workspace/dataset name

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

    $uri = "https://api.powerbi.com/v1.0/myorg/groups/$workspaceId/datasets/$datasetId/tables/$tableName/rows"

    $body = @{ rows = $rows } | ConvertTo-Json -Depth 10
    Set-PrintAndLog -message "Pushing $($rows?.Count ?? 0) rows to table [$tableName]... $body"

    $result = Invoke-RestMethod -Uri $uri -Method Post -Headers @{ Authorization = "Bearer $token" } `
        -ContentType "application/json" -Body $body

    Set-PrintAndLog -message "Push result: $($result | Out-String)"
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
        [string]$tablename   
    )

    $TableName = if ($Schema.TableName) { $Schema.TableName } elseif ($Schema.name) { $Schema.name } else { "UnnamedTable" }

    Write-Host "`n[+] Tabulating: $TableName..." -ForegroundColor Cyan

    # Run tabulation function
    $row = @{}
    foreach ($col in $Schema.columns) {
        $val = Get-Variable -Name $col.name -ValueOnly -ErrorAction SilentlyContinue
        if ($val -is [hashtable] -or $val -is [pscustomobject]) {
            $val = $val.$($col.name)
        }

        $row[$col.name] = $val
        Set-PrintAndLog "Tabulated row:`n$($safeData | ConvertTo-Json -Depth 10)" -Color Yellow

    }
    $data = @([pscustomobject]$row)

    # Deduplicate and clean nulls (flatten single-level only)
    $safeData = @()
    foreach ($entry in $data) {
        $obj = @{}
        foreach ($k in $entry.PSObject.Properties.Name) {
            if ($entry.$k -ne $null) {
                $obj[$k] = $entry.$k
            }
        }
        $safeData += [pscustomobject]$obj
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
