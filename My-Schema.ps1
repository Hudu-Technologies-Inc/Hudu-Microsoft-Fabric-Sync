# this is all the source data you want to retrieve
$HuduFetchMap = @(
    @{ Name = 'all_companies';     Command = { Get-HuduCompanies } },
    @{ Name = 'all_assets';        Command = { Get-HuduAssets } },
    @{ Name = 'all_articles';      Command = { Get-HuduArticles } },
    @{ Name = 'all_assetlayouts';  Command = { Get-HuduAssetLayouts } },
    @{ Name = 'all_processes';     Command = { Get-HuduProcesses } },
    @{ Name = 'all_websites';      Command = { Get-HuduWebsites } },
    @{ Name = 'all_uploads';       Command = { Get-HuduUploads } },
    @{ Name = 'all_public_photos'; Command = { Get-HuduPublicPhotos } },
    @{ Name = 'all_magic_dashes';  Command = { Get-HuduMagicDashes } },
    @{ Name = 'all_folders';       Command = { Get-HuduFolders } },
    @{ Name = 'all_expirations';   Command = { Get-HuduExpirations } },
    @{ Name = 'all_activities';    Command = { Get-HuduActivityLogs } },
    @{ Name = 'all_processes';    Command = { Get-HuduProcesses } }
)



# this is the data as you want it in fabric
$DatasetSchemaJson = @{
    name   = "$DataSetName"
    tables = @(
        @{
            name   = "Company Metrics"
            columns = @(
                @{ name = "CompanyName"; dataType = "String" }
                @{ name = "AssetCount"; dataType = "Int64" }
                @{ name = "ArchivedAssetCount"; dataType = "Int64" }
                @{ name = "AllArticlesCount"; dataType = "Int64" }
                @{ name = "DraftArticlesCount"; dataType = "Int64" }
                @{ name = "ProcessesCount"; dataType = "Int64" }
                @{ name = "WebsitesCount"; dataType = "Int64" }
                @{ name = "ExpirationsCount"; dataType = "Int64" }
                @{ name = "ExpiredExpirations"; dataType = "Int64" }
                @{ name = "FoldersCount"; dataType = "Int64" }
                @{ name = "MagicDashesCount"; dataType = "Int64" }
                @{ name = "LastRefreshed"; dataType = "DateTime" }
            )
        },
        @{
            name   = "Asset Metrics"
            columns = @(
                @{ name = "AllAssetCount"; dataType = "Int64" }
                @{ name = "AllAssetLayoutCount"; dataType = "Int64" }
                @{ name = "AverageAssetsPerLayout"; dataType = "Double" }
                @{ name = "AllArchivedAssetCount"; dataType = "Int64" }
                @{ name = "AllExpiredAssetCount"; dataType = "Int64" }
            )
        },
        @{
            name   = "Article Metrics"
            columns = @(
                @{ name = "AllDraftArticlesCount"; dataType = "Int64" }
                @{ name = "AllArticlesWithPublicPhotosCount"; dataType = "Int64" }
                @{ name = "AllExpiredArticleCount"; dataType = "Int64" }
            )
        }
    )
} | ConvertTo-Json -Depth 10

# these are the defs for your tabulations
function Get-CompanyMetrics {
    param (
        [PSCustomObject]$company,
        [array]$all_assets,
        [array]$all_articles,
        [array]$all_processes,
        [array]$all_websites,
        [array]$all_expirations,
        [array]$all_folders,
        [array]$all_magic_dashes
    )

    $cid = [int]$company.Id
    $cname = $company.Name

    return [PSCustomObject]@{
        CompanyName          = $cname
        AssetCount           = ($all_assets | Where-Object { [int]$_.Company_Id -eq $cid }).Count
        ArchivedAssetCount   = ($all_assets | Where-Object { [int]$_.Company_Id -eq $cid -and $_.Archived }).Count
        AllArticlesCount     = ($all_articles | Where-Object { [int]$_.Company_Id -eq $cid }).Count
        DraftArticlesCount   = ($all_articles | Where-Object { [int]$_.Company_Id -eq $cid -and $_.Draft }).Count
        ProcessesCount       = ($all_processes | Where-Object { $_.Company_Name -eq $cname -or [int]$_.company_id -eq $cid }).Count
        WebsitesCount        = ($all_websites | Where-Object { [int]$_.Company_Id -eq $cid }).Count
        ExpirationsCount     = ($all_expirations | Where-Object { [int]$_.Company_Id -eq $cid }).Count
        ExpiredExpirations   = ($all_expirations | Where-Object { [int]$_.Company_Id -eq $cid -and $_.ParsedExpirationDate -lt (Get-Date) }).Count
        FoldersCount         = ($all_folders | Where-Object { [int]$_.Company_Id -eq $cid }).Count
        MagicDashesCount     = ($all_magic_dashes | Where-Object { [int]$_.Company_Id -eq $cid }).Count
        LastRefreshed        = [DateTime](Get-Date)
    }
}

function Get-AssetMetrics {
    param (
        [array]$all_assets,
        [array]$all_assetlayouts,
        [array]$all_expirations
    )

    $assetCount = $all_assets.Count
    $layoutCount = $all_assetlayouts.Count

    return [PSCustomObject]@{
        AllAssetCount            = $assetCount
        AllAssetLayoutCount      = $layoutCount
        AverageAssetsPerLayout   = if ($layoutCount -ne 0) { [math]::Round($assetCount / $layoutCount, 2) } else { 0 }
        AllArchivedAssetCount    = ($all_assets | Where-Object { $_.Archived }).Count
        AllExpiredAssetCount     = ($all_expirations | Where-Object { $_.ParsedExpirationDate -lt (Get-Date) -and $_.expirationable_type -eq 'Asset' }).Count
    }
}

function Get-ArticleMetrics {
    param (
        [array]$all_articles,
        [array]$all_expirations
    )

    return [PSCustomObject]@{
        AllDraftArticlesCount            = ($all_articles | Where-Object { $_.Draft }).Count
        AllArticlesWithPublicPhotosCount = ($all_articles | Where-Object { $_.public_photos.Count -gt 0 }).Count
        AllExpiredArticleCount           = ($all_expirations | Where-Object { $_.ParsedExpirationDate -lt (Get-Date) -and $_.expirationable_type -eq 'Article' }).Count
    }
}

# Define your functions and the data needed to tabulate them
$HuduTabulationMap = @(
    @{
        TableName = "Company Metrics"
        Function  = "Get-CompanyMetrics"
        PerCompany   = $true   # Indicates it's called once per company
        Params    = @("all_assets", "all_articles", "all_processes", "all_websites", "all_expirations", "all_folders", "all_magic_dashes")
    },
    @{
        TableName = "Asset Metrics"
        Function  = "Get-AssetMetrics"
        PerCompany   = $false
        Params    = @("all_assets", "all_assetlayouts", "all_expirations")
    },
    @{
        TableName = "Article Metrics"
        Function  = "Get-ArticleMetrics"
        PerCompany   = $false
        Params    = @("all_articles", "all_expirations")
    }
)