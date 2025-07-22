# Unified schema config file for Hudu → Power BI/Fabric
# Drop this into your project and source it with `. .\MySchema.ps1`

$HuduSchema = @{
    Fetch = @(
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
        @{ Name = 'all_activities';    Command = { Get-HuduActivityLogs } }
    )

    Tables = @(
        @{
            name     = "Company Metrics"
            function = "Get-CompanyMetrics"
            perItem  = $true
            depends  = @("all_assets", "all_articles", "all_processes", "all_websites", "all_expirations", "all_folders", "all_magic_dashes")
            columns  = @(
                @{ name = "CompanyName";         dataType = "String" },
                @{ name = "AssetCount";          dataType = "Int64" },
                @{ name = "ArchivedAssetCount";  dataType = "Int64" },
                @{ name = "AllArticlesCount";    dataType = "Int64" },
                @{ name = "DraftArticlesCount";  dataType = "Int64" },
                @{ name = "ProcessesCount";      dataType = "Int64" },
                @{ name = "WebsitesCount";       dataType = "Int64" },
                @{ name = "ExpirationsCount";    dataType = "Int64" },
                @{ name = "ExpiredExpirations";  dataType = "Int64" },
                @{ name = "FoldersCount";        dataType = "Int64" },
                @{ name = "MagicDashesCount";    dataType = "Int64" },
                @{ name = "LastRefreshed";       dataType = "DateTime" }
            )
        },
        @{
            name     = "Asset Metrics"
            function = "Get-AssetMetrics"
            perItem  = $false
            depends  = @("all_assets", "all_assetlayouts", "all_expirations")
            columns  = @(
                @{ name = "AllAssetCount";            dataType = "Int64" },
                @{ name = "AllAssetLayoutCount";      dataType = "Int64" },
                @{ name = "AverageAssetsPerLayout";   dataType = "Double" },
                @{ name = "AllArchivedAssetCount";    dataType = "Int64" },
                @{ name = "AllExpiredAssetCount";     dataType = "Int64" }
            )
        },
        @{
            name     = "Article Metrics"
            function = "Get-ArticleMetrics"
            perItem  = $false
            depends  = @("all_articles", "all_expirations")
            columns  = @(
                @{ name = "AllDraftArticlesCount";            dataType = "Int64" },
                @{ name = "AllArticlesWithPublicPhotosCount"; dataType = "Int64" },
                @{ name = "AllExpiredArticleCount";           dataType = "Int64" }
            )
        }
    )
}

# Build DatasetSchemaJson from table defs
$DatasetSchemaJson = @{
    name   = $DataSetName ?? "DefaultDataset"
    tables = @()
}

foreach ($table in $HuduSchema.Tables) {
    $DatasetSchemaJson.tables += @{
        name    = $table.name
        columns = $table.columns
    }
}

# Convert to JSON when needed
$DatasetSchemaJson = $DatasetSchemaJson | ConvertTo-Json -Depth 10
