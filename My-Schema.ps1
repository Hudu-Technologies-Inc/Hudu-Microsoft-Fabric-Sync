# Unified schema config file for Hudu → Power BI/Fabric
$UseAzureKeyStore=$true
$AzVault_Name = "your-vaultname"
$HuduApiKeySecretName = "your-secretname"
$clientIdSecretName = "clientid-secretname"
$tenantIdSecretName = "tenantid-secretname"
$HuduBaseUrl= "yoururl.huducloud.com"
$DataSetName = "MyDataSetName"
$WorkspaceName = "MyWorkspaceName"

$HuduSchema = @{
Fetch = @(
    @{Name    = 'all_companies'; Command = { Get-HuduCompanies }},
    @{Name    = 'all_assets'; Command = { Get-HuduAssets }},
    @{Name    = 'all_articles'; Command = { Get-HuduArticles }},
    @{Name    = 'all_assetlayouts'; Command = { Get-HuduAssetLayouts }},
    @{Name    = 'all_processes'; Command = { Get-HuduProcesses }},
    @{Name    = 'all_websites'; Command = { Get-HuduWebsites }},
    @{Name    = 'all_uploads'; Command = { Get-HuduUploads }},
    @{Name    = 'all_public_photos'; Command = { Get-HuduPublicPhotos }},
    
    @{

        
    }
    @{
        Name    = 'weak_passwords'
        Command = { Get-HuduPasswords }
        Filter  = { param($items) $items | Where-Object { ("$($_.password)".Length -le 6) } }
    },    
    @{
        Name = 'archived_assets'
        Command = { Get-HuduAssets }
        Filter = { param($items) $items | Where-Object { -not $_.Archived } }
    },
    @{
        Name = 'finished_articles'
        Command = { Get-HuduArticles }
        Filter = { param($items) $items | Where-Object { $_.Draft -eq $false } }
    },
    @{
        Name = 'draft_articles'
        Command = { Get-HuduArticles }
        Filter = { param($items) $items | Where-Object { $_.Draft -eq $true } }
    },
    @{
        Name = 'short_articles'
        Command = { Get-HuduArticles }
        Filter = { param($items) $items | Where-Object { "$($_.content)".Length -lt 250 } }
    }    
    
    )
    Tables = @(
        @{
            name     = "Company Metrics"
            function = "Get-CompanyMetrics"
            perCompany  = $true
            depends  = @("all_assets", "all_articles", "all_processes", "all_websites", "all_expirations", "all_folders", "all_magic_dashes")
            columns  = @(

            )
        }
    )
}

