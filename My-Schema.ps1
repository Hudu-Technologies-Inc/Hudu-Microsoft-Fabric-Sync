# Unified schema config file for Hudu → Power BI/Fabric
$UseAzureKeyStore=$true
$AzVault_Name = "your-vaultname"
$HuduApiKeySecretName = "your-secretname"
$clientIdSecretName = "clientid-secretname"
$clientSecretName = "client-secretname"
$tenantIdSecretName = "tenantid-secretname"
$HuduBaseUrl= "yoururl.huducloud.com"
$WorkspaceName = "myworkspace"


$HuduSchema = @{
    WorkspaceName = "MyWorkspaceName"
    DatasetName   = "MyDatasetName"
    Fetch = @(
        @{
            Name    = 'all_companies'
            Command = { Get-HuduCompanies }
            dataType = 'Int64'
            Filter = {
                param ($items)
                [pscustomobject]@{ all_companies = $items.Count }
            }
        },
        @{
            Name    = 'all_assets'
            Command = { Get-HuduAssets }
            dataType = 'Int64'
            Filter = {
                param ($items)
                [pscustomobject]@{ all_assets = $items.Count }
            }
        },
        @{
            Name    = 'all_articles'
            Command = { Get-HuduArticles }
            dataType = 'Int64'
            Filter = {
                param ($items)
                [pscustomobject]@{ all_articles = $items.Count }
            }
        },
        @{
            Name = 'all_assetlayouts'
            Command = { Get-HuduAssetLayouts }
            dataType = 'Int64'
            Filter = {
                param ($items)
                [pscustomobject]@{ all_assetlayouts = $items.Count }
            }
        },
        @{
            Name = 'all_processes'
            Command = { Get-HuduProcesses }
            dataType = 'Int64'
            Filter = {
                param ($items)
                [pscustomobject]@{ all_processes = $items.Count }
            }
        },
        @{
            Name = 'all_websites'
            Command = { Get-HuduWebsites }
            dataType = 'Int64'
            Filter = {
                param ($items)
                [pscustomobject]@{ all_websites = $items.Count }
            }
        },
        @{
            Name = 'all_uploads'
            Command = { Get-HuduUploads }
            dataType = 'Int64'
            Filter = {
                param ($items)
                [pscustomobject]@{ all_uploads = $items.Count }
            }
        },
        @{
            Name = 'num_users'
            Command = { Get-HuduUsers }
            dataType = 'Int64'
            Filter = {
                param ($items)
                [pscustomobject]@{ num_users = $items.Count }
            }
        },
        @{
            Name = 'num_admins'
            Command = { Get-HuduUsers }
            dataType = 'Int64'
            Filter = {
                param ($users)
                [pscustomobject]@{ num_admins = ($users | Where-Object { $_.security_level -eq 'admin' }).Count }
            }
        },
        @{
            Name = 'num_superadmins'
            dataType = 'Int64'
            Command = { Get-HuduUsers }
            Filter = {
                param ($users)
                [pscustomobject]@{ num_superadmins = ($users | Where-Object { $_.security_level -eq 'super_admin' }).Count }
            }
        },
        @{
            Name = 'top_author_email'
            Command = { Get-HuduUsers }
            dataType = 'String'
            Filter = {
                param ($users)
                [pscustomobject]@{ top_author_email = ($users | Sort-Object { [int]$_.score_all_time } -Descending | Select-Object -First 1).email }
            }
        },
        @{
            Name = 'public_articles'
            Command = { Get-HuduArticles }
            dataType = 'Int64'
            Filter = {
                param ($articles)
                [pscustomobject]@{ public_articles = ($articles | Where-Object { $_.sharing_enabled -eq $true }).Count }
            }
        },
        @{
            Name = 'old_passwords'
            Command = { Get-HuduPasswords }
            dataType = 'Int64'
            Filter = {
                param ($pw)
                $threshold = (Get-Date).AddMonths(-6)
                [pscustomobject]@{ old_passwords = ($pw | Where-Object { [datetime]$_.created_at -lt $threshold }).Count }
            }
        },
        @{
            Name = 'weak_passwords'
            dataType = 'Int64'
            Command = { Get-HuduPasswords }
            Filter = {
                param ($pw)
                [pscustomobject]@{ weak_passwords = ($pw | Where-Object { "$($_.password)".Length -le 6 }).Count }
            }
        },
        @{
            Name = 'archived_assets'
            dataType = 'Int64'
            Command = { Get-HuduAssets }
            Filter = {
                param ($assets)
                [pscustomobject]@{ archived_assets = ($assets | Where-Object { $true -eq [bool]$_.Archived }).Count }
            }
        },
        @{
            Name = 'finished_articles'
            dataType = 'Int64'
            Command = { Get-HuduArticles }
            Filter = {
                param ($articles)
                [pscustomobject]@{ finished_articles = ($articles | Where-Object { $_.Draft -eq $false }).Count }
            }
        },
        @{
            Name = 'draft_articles'
            Command = { Get-HuduArticles }
            dataType = 'Int64'
            Filter = {
                param ($articles)
                [pscustomobject]@{ draft_articles = ($articles | Where-Object { $_.Draft -eq $true }).Count }
            }
        },
        @{
            Name = 'short_articles'
            Command = { Get-HuduArticles }
            dataType = 'Int64'
            Filter = {
                param ($articles)
                [pscustomobject]@{ short_articles = ($articles | Where-Object { "$($_.content)".Length -lt 250 }).Count }
            }
        }
    )
    Tables = @(
        @{
            name        = "Mytablename1"
            perCompany  = $true
            columns     = @(
                "all_assets",
                "all_articles",
                "all_processes",
                "all_websites",
                "all_magic_dashes",
                "top_author_email",
                "public_articles",
                "old_passwords",
                "weak_passwords",
                "archived_assets",
                "finished_articles",
                "draft_articles",
                "short_articles"
            )
            
        }
        @{
            name        = "MyTableName2"
            perCompany  = $false
            columns     = @(
                "num_users",
                "num_admins",
                "num_superadmins",
                "top_author_email"
            )
            
        }        
    )
}
