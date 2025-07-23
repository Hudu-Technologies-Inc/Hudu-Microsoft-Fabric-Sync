$delegatedPermissions = $delegatedPermissions = @("Dataset.ReadWrite.All","Workspace.Read.All")
$ApplicationPermissions = @("Tenant.Read.All","Dataset.ReadWrite.All","Workspace.ReadWrite.All")
$scope= "https://analysis.windows.net/powerbi/api/.default"
# fallback values for improper or null workspace/dataset name

function Set-AuthorizedUserForWorkspace {
    param (
        [Parameter(Mandatory)]
        [string]$userEmail,
        [Parameter(Mandatory)]
        [string]$token,
        [Parameter(Mandatory)]
        [string]$workspaceId,
        [ValidateSet("User", "Group", "ServicePrincipal")]
        [string]$principalType = "User",
        [ValidateSet("Admin", "Member", "Contributor", "Viewer")]
        [string]$accessRights = "Admin"
    )

    $headers = @{ Authorization = "Bearer $token" }

    $body = @{
        identifier           = $userEmail
        principalType        = $principalType
        groupUserAccessRight = $accessRights
    } | ConvertTo-Json -Depth 5

    try {
        $uri = "https://api.powerbi.com/v1.0/myorg/groups/$workspaceId/users"
        $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body -ContentType "application/json"
        Write-Host "Successfully added $userEmail to workspace $workspaceId as $accessRights"
    } catch {
        Write-Warning "Failed to add $userEmail to workspace $workspaceId $($_.Exception.Message)"
    }
}



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
        if ($true -eq $table.PerCompany){
            $columns += [pscustomobject]@{
                name     = 'company_id'; dataType = 'Int64'}            
            $columns += [pscustomobject]@{
                name     = 'company_name'; dataType = 'String'}  
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

    $groups = @()
    $uri = "https://api.powerbi.com/v1.0/myorg/groups"

    do {
        $response = Invoke-RestMethod -Uri $uri -Headers @{ Authorization = "Bearer $token" }
        $groups += $response.value
        $uri = $response.'@odata.nextLink'
    } while ($uri)

    foreach ($existingWorkspace in $groups) {
        if ($existingWorkspace.Name -ieq $name) {
            Set-PrintAndLog -message "Workspace found: $($existingWorkspace.Name) (ID: $($existingWorkspace.id))"
            return $existingWorkspace
        }
    }

    Set-PrintAndLog -message "Workspace not found. Creating new workspace: $name"
    $body = @{ name = $name } | ConvertTo-Json
    $workspace = Invoke-RestMethod -Uri "https://api.powerbi.com/v1.0/myorg/groups" -Method Post -Headers @{ Authorization = "Bearer $token" } -Body $body -ContentType "application/json"

    if ($null -ne $workspace.id -and $(get-azcontext)){
        try {
            Set-AuthorizedUserForWorkspace -userEmail "$((get-azcontext).account)" -token $token -workspaceId $workspace.id
        } catch {
            Set-PrintAndLog -message "Was unable to set current user as viewing member of this workspace. Ask your admin to add you in powerBI admin console!" -Color Magenta
        }
    }

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
    try {
        $rows = @($rows) # Force into array
        $uri = "https://api.powerbi.com/v1.0/myorg/groups/$workspaceId/datasets/$datasetId/tables/$tableName/rows"

        $payload = @{rows = $rows} | ConvertTo-Json -Depth 10
        Set-PrintAndLog -message "Pushing $($rows.Count) rows to table [$tableName]... $payload"

        $response = Invoke-WebRequest -Uri $uri -Method Post -Headers @{ Authorization = "Bearer $token" } `
            -ContentType "application/json" -Body $payload -UseBasicParsing

        Set-PrintAndLog -message "Raw response:`n$($response.StatusCode) $($response.StatusDescription)`n$($response.Content)"

        Set-PrintAndLog -message ("Push result:`n" + ($result | Out-String))
    } catch {
        Write-ErrorObjectsToFile -Name "Tabulation-Err" -ErrorObject @{
            result = $result
            uri  = $uri
            payload    = $payload
            Error  = $_        
        }
    }
}