# Unified schema config file for Hudu → Power BI/Fabric
$UseAzureKeyStore=$true
$AzVault_Name = "your-vaultname"
$HuduApiKeySecretName = "your-secretname"
$clientIdSecretName = "clientid-secretname"
$tenantIdSecretName = "tenantid-secretname"
$HuduBaseUrl= "yoururl.huducloud.com"
$WorkspaceName = "myworkspace"

$HuduSchema = @{
Fetch = @(
    @{  Name = 'all_companies'
        Command = { Get-HuduCompanies }
        dataType = 'Int64'},
    @{  Name = 'all_assets'
        Command = { Get-HuduAssets }
        dataType = 'Int64'},
    @{  Name = 'all_articles'
        Command = { Get-HuduArticles }
        dataType = 'Int64'},
    @{  Name = 'all_assetlayouts'
        Command = { Get-HuduAssetLayouts }
        dataType = 'Int64'},
    @{  Name = 'all_processes';
        Command = { Get-HuduProcesses }
        dataType = 'Int64'},
    @{  Name = 'all_websites'
        Command = { Get-HuduWebsites }
        dataType = 'Int64'
    },
    @{ Name = 'all_uploads'
        Command = { Get-HuduUploads }
        dataType = 'Int64'},
    @{ Name = 'num_users'
        Command = { Get-HuduUsers }
        Filter = {
            param ($items)
            [pscustomobject]@{ num_users = $items.Count }
        }},
    @{ Name = 'num_admins'
        Command = { Get-HuduUsers }
        Filter = {
            param ($items)
            $count = ($items | Where-Object { $_.security_level -eq 'admin' }).Count
            [pscustomobject]@{ num_admins = $count }
        }},
    @{ Name = 'num_superadmins'
        Command = { Get-HuduUsers }
        Filter = {
            param ($items)
            $count = ($items | Where-Object { $_.security_level -eq 'super_admin' }).Count
            [pscustomobject]@{ num_superadmins = $count }
        }},
    @{ Name = 'top_author_email'
        Command = { Get-HuduUsers }
        Filter = {
            param ($items)
            $top = $items | Sort-Object { [int]$_.score_all_time } -Descending | Select-Object -First 1
            [pscustomobject]@{ top_author_email = $top.email }
        }},
    @{ Name = 'public_articles'
        Command = { Get-HuduArticles }
        Filter = {
            param ($items)
            $count = ($items | Where-Object { $_.sharing_enabled -eq $true }).Count
            [pscustomobject]@{ public_articles = $count }
        }},
    @{ Name = 'old_passwords'
        Command = { Get-HuduPasswords }
        Filter = {
            param ($items)
            $threshold = (Get-Date).AddMonths(-6)
            $count = ($items | Where-Object { [datetime]$_.created_at -lt $threshold }).Count
            [pscustomobject]@{ old_passwords = $count }
        }},
    @{ Name = 'weak_passwords'
        Command = { Get-HuduPasswords }
        Filter = {
            param ($items)
            $count = ($items | Where-Object { "$($_.password)".Length -le 6 }).Count
            [pscustomobject]@{ weak_passwords = $count }
        }},
    @{ Name = 'archived_assets'
        Command = { Get-HuduAssets }
        Filter = {
            param ($items)
            $count = ($items | Where-Object { $true -eq [bool]$_.Archived }).Count
            [pscustomobject]@{ archived_assets = $count }
        }},
    @{ Name = 'finished_articles'
        Command = { Get-HuduArticles }
        Filter = {
            param ($items)
            $count = ($items | Where-Object { $_.Draft -eq $false }).Count
            [pscustomobject]@{ finished_articles = $count }
        }},
    @{ Name = 'draft_articles'
        Command = { Get-HuduArticles }
        Filter = {
            param ($items)
            $count = ($items | Where-Object { $_.Draft -eq $true }).Count
            [pscustomobject]@{ draft_articles = $count }
        }},
    @{ Name = 'short_articles'
        Command = { Get-HuduArticles }
        Filter = {
            param ($items)
            $count = ($items | Where-Object { "$($_.content)".Length -lt 250 }).Count
            [pscustomobject]@{ short_articles = $count }
        }})
Tables = @(
        @{
            name        = "PerCompanyInfo"
            perCompany  = $true
            columns     = @(
                "all_assets",
                "all_articles",
                "all_processes",
                "all_websites",
                "all_expirations",
                "all_folders",
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
            name        = "UserInfo"
            perCompany  = $false
            columns     = @(
                "num_users",
                "num_admins",
                "num_superadmins"
        )
    }
    )
}

