####### Unified schema config file for Hudu → Power BI/Fabric
# if you want the first-time app registration helper script to run, set these as blank or $null
# otherwise these are 'less-sensitive', but it is best to get these from AZ key vault if possible.
$clientId = ""
$tenantId = ""


# use Azure Key Vault for obtaining secrets? (highly reccomended)
$UseAzureKeyStore=$true

# AZ Vault and secrets config
$AzVault_Name = "your-vaultname"
$HuduApiKeySecretName = "your-secretname"
$clientIdSecretName = "clientid-secretname"
$clientSecretName = "client-secretname"
$tenantIdSecretName = "tenantid-secretname"

# Hudu URL Setup-
$HuduBaseUrl= "yoururl.huducloud.com"

# What will you call your new Fabric workspace?
$age_threshold = (Get-Date).AddMonths(-6)


$HuduSchema = @{
    WorkspaceName = "MyWorkspaceName"
    DatasetName   = "MyDatasetName"
    Fetch = @(
        @{
            Name    = 'all_companies'
            Command = { Get-HuduCompanies }
            dataType = 'Int64'
            Filter = {
                param ($companies)
                [pscustomobject]@{ all_companies = $companies.Count }
            }
        },
        @{
            Name    = 'all_assets'
            Command = { Get-HuduAssets }
            dataType = 'Int64'
            Filter = {
                param ($assets)
                [pscustomobject]@{ all_assets = $assets.Count }
            }
        },
        @{
            Name    = 'all_articles'
            Command = { Get-HuduArticles }
            dataType = 'Int64'
            Filter = {
                param ($articles)
                [pscustomobject]@{ all_articles = $articles.Count }
            }
        },
        @{
            Name = 'all_assetlayouts'
            Command = { Get-HuduAssetLayouts }
            dataType = 'Int64'
            Filter = {
                param ($assetlayouts)
                [pscustomobject]@{ all_assetlayouts = $assetlayouts.Count }
            }
        },
        @{
            Name = 'all_websites'
            Command = { Get-HuduWebsites }
            dataType = 'Int64'
            Filter = {
                param ($websites)
                [pscustomobject]@{ all_websites = $websites.Count }
            }
        },
        @{
            Name = 'all_uploads'
            Command = { Get-HuduUploads }
            dataType = 'Int64'
            Filter = {
                param ($uploads)
                [pscustomobject]@{ all_uploads = $uploads.Count }
            }
        },
        @{
            Name = 'num_users'
            Command = { Get-HuduUsers }
            dataType = 'Int64'
            Filter = {
                param ($users)
                [pscustomobject]@{ num_users = $users.Count }
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
                [pscustomobject]@{ old_passwords = ($pw | Where-Object {$null -ne $_.updated_at -and [datetime]$_.updated_at -lt $age_threshold }).Count }
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
                $addition + $articles

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
