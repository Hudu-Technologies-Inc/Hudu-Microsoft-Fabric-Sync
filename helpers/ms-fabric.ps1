$delegatedPermissions = $delegatedPermissions = @("Dataset.ReadWrite.All","Workspace.Read.All")
$ApplicationPermissions = @("Tenant.Read.All","Dataset.ReadWrite.All","Workspace.ReadWrite.All")
$scope= "https://analysis.windows.net/powerbi/api/.default"
# fallback values for improper or null workspace/dataset name

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
    Set-PrintAndLog -message "Pushing $($rows.Count) rows to table [$tableName]..."

    $result = Invoke-RestMethod -Uri $uri -Method Post -Headers @{ Authorization = "Bearer $token" } `
        -ContentType "application/json" -Body $body

    Set-PrintAndLog -message "Push result: $($result | Out-String)"
}

function Invoke-TabulationTask {
    param (
        [Parameter(Mandatory)]
        $Tab,

        [Parameter(Mandatory)]
        [array]$AllCompanies,

        [Parameter(Mandatory)]
        [string]$AccessToken,

        [Parameter(Mandatory)]
        [string]$DatasetId,

        [Parameter()]
        [switch]$DryRun
    )

    $functionName = $Tab.Function
    $paramNames   = $Tab.Params

    if ($Tab.PerCompany -eq $true) {
        $data = @()
        $current_idx = 0
        foreach ($company in $AllCompanies) {
            $current_idx++
            Write-Progress -Activity "submitting $($Tab.TableName)..." `
                -Status "Company $current_idx / $($AllCompanies.Count)" `
                -PercentComplete (($current_idx / $AllCompanies.Count) * 100)

            $args = @()
            foreach ($p in $paramNames) {
                $args += (Get-Variable -Name $p -ValueOnly)
            }

            $row = & $functionName -company $company @args
            if ($row) { $data += $row }
        }
    } else {
        $args = @()
        foreach ($p in $paramNames) {
            $args += (Get-Variable -Name $p -ValueOnly)
        }

        $data = @(& $functionName @args)
    }

    if ($DryRun) {
        Write-Host "`n=== [$($Tab.TableName)] ==="
        $data | Format-Table
        Read-Host "Press Enter to continue"
    } else {
        if ($data.Count -eq 0) {
            Write-Warning "Skipping $($Tab.TableName): No data returned."
            return
        }
        Push-DataToTable -TableName $Tab.TableName -Data $data -Token $AccessToken -DatasetId $DatasetId
    }
}
