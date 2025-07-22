function Decode-JwtTokenPayload {
    param (
        [Parameter(Mandatory=$true)][string]$Token
    )

    $parts = $Token -split '\.'
    if ($parts.Count -lt 2) {
        throw "Invalid JWT structure (must have at least two parts)"
    }

    # Base64url decode the second part (payload)
    $payload = $parts[1]
    $remainder = $payload.Length % 4
    if ($remainder -ne 0) {
        $payload += '=' * (4 - $remainder)
    }
    $payload = $payload -replace '-', '+' -replace '_', '/'

    $decoded = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload))
    return $decoded | ConvertFrom-Json
}

function Set-AzureAppRegistration {
    param (
        [Parameter(Mandatory)]
        [string]$SAMDisplayName,
        [System.Collections.ArrayList]$delegatedPermissions=@("User.Read"),
        [System.Collections.ArrayList]$ApplicationPermissions=@("User.Read")

    )
    Set-PrintAndLog -message "Starting App Registration create/update for $SAMDisplayName with $($delegatedPermissions.count) Delegated permissions and $($ApplicationPermissions.count) application permissions" -Color DarkGreen

     # Alt URL for redirects
    $env:AZURE_CLI_ENCODING = "UTF-8"
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $TenantId = $null
    $SubscriptionId = $null

    # install/import az module, set initial AZ context
    Write-Host "Ensuring AZ Moduleis installed and loaded. (be patient, it takes a while sometimes.)"
    Get-EnsuredModule -name "Az"

    if (-not (Get-AzContext)) {
        try {
            Connect-AzAccount -UseDeviceAuthentication -ErrorAction Stop
        } catch {
            Write-Error "Failed to connect to Azure. Error: $_" -ForegroundColor Red
            exit 1
        }
    } else {
        Set-PrintAndLog -message "AZContext already set. Skipping Sign-on." -Color Green
    }
    # Checking for AZ CLI and installing
    Write-Host "Checking for AZ CLI..."
    $azCommand = Get-Command az -ErrorAction SilentlyContinue
    if (-not $azCommand) {
        Set-PrintAndLog -message "AZ CLI command not found! If this script was ran as Administrator, we can install it, let's check." -Color DarkYellow
        if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Set-PrintAndLog -message "You will need AZ CLI to run this autoregistration. If you want to install AZ CLI with this script, run again as admin, otherwise install AZ CLI Manually before running..." -Color Red
            exit 1
        }
        try {
            Set-PrintAndLog -message "Attempting WinGet install of AZ CLI via PowerShell module from PSGallery..." -Color DarkYellow
            Set-PrintAndLog -message "Setting up Nuget Provider for AZ CLI... $(Install-PackageProvider -Name NuGet -Force)" -Color DarkYellow
            Set-PrintAndLog -message "Setting up PSGallery for AZ CLI... $(Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery)" -Color DarkYellow
            Set-PrintAndLog -message "Ensuring Winget for AZ CLI... $(Repair-WinGetPackageManager)" -Color DarkYellow
            Set-PrintAndLog -message "Using Winget to install Azure CLI... $(winget install -e --id Microsoft.AzureCLI)" -Color DarkYellow
        } catch {
            Set-PrintAndLog -message  "Couldnt install AZ CLI via Winget. Attempting install via MSI package." -Color DarkYellow
            Set-PrintAndLog -message  "Downloading MSI Package to .\AzureCLI.msi... $(Invoke-WebRequest -Uri https://aka.ms/installazurecliwindowsx64 -OutFile .\AzureCLI.msi)" -Color DarkYellow
            Set-PrintAndLog -message  "Installing AZ CLI via MSI Package in Background... $(Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet')" -Color DarkYellow
            Set-PrintAndLog -message  "Clean up MSI Package file post-install... $(Remove-Item .\AzureCLI.msi -Force)" -Color DarkYellow
        }
    } else { Set-PrintAndLog -message "Azure CLI is available at: $($azCommand.Path)" -Color Green }

    # Sign in with AZ CLI
    Set-PrintAndLog -message "AZ CLI is present and available. Attempting login with AZ CLI if not already authenticated..." -Color DarkGreen
    try {
        # Check if already logged in
        $account = az account show --output json | ConvertFrom-Json
        if ($account -and $account.id) {
            Set-PrintAndLog -message "Already logged into Azure CLI as: $($account.user.name)" -Color Green
        } else {
            throw "No active Azure account."
        }
    } catch {
        # If not logged in, log in
        Set-PrintAndLog -message "Not logged into Azure CLI. Attempting to log in..." -Color DarkGreen
        try {
            az login --use-device-code
            Set-PrintAndLog -message "Successfully logged into Azure CLI." -Color Green
        } catch {
            Write-Error "Failed to log in to Azure CLI. Exiting." -ForegroundColor Red
            exit 1
        }
    }

    Set-PrintAndLog -message "Step 1: Select Tenants" -Color Green
    $Tenants = az account list --query "[].{Name:name, TenantId:tenantId, SubscriptionId:id}" --output json | ConvertFrom-Json

        if ($Tenants.Count -eq 1) {
            $TenantId = $Tenants[0].TenantId
            $SubscriptionId = $Tenants[0].SubscriptionId
            Set-PrintAndLog -message "Only one tenant found. Using: $TenantId ($($Tenants[0].Name))" -Color Yellow
            az account set --subscription $SubscriptionId
        } else {
        Set-PrintAndLog -message "Available Tenants:" -Color Green
        $Tenants | ForEach-Object {
            Set-PrintAndLog -message "$($_.Name) - $($_.TenantId)" -Color Blue
        }

        $TenantId = Read-Host "Enter the Tenant ID to use (leave blank for current)"
        
        if ($TenantId -ne "") {
            az account set --tenant $TenantId
            Set-PrintAndLog -message "Switched to Tenant: $TenantId" -Color Green
        } else {
            $TenantId = az account show --query tenantId --output tsv
            Set-PrintAndLog -message "Using current Tenant: $TenantId" -Color Green
        }
    }

    # Step 2, find or create app
    Set-PrintAndLog -message "Step 2: Find or Create App" -Color DarkGreen
    $AppId = az ad app list --all --display-name "$SAMDisplayName" --query "[?displayName=='$SAMDisplayName'].appId" --output tsv
    if ($AppId) {
        Set-PrintAndLog -message "App '$SAMDisplayName' already exists with ID: $AppId" -Color Green
    } else {
        Set-PrintAndLog -message "Creating new App Registration: $SAMDisplayName" -Color Green
        $AppId = az ad app create `
            --display-name "$SAMDisplayName" `
            --query appId --output tsv
        Set-PrintAndLog -message "Created App with ID: $AppId" -Color Green
    }

    # Step 3, find or create Service Principal
    Set-PrintAndLog -message "Step 3: Find or Create Service Principal" -Color DarkGreen
    $ServicePrincipalId = az ad sp list --all --query "[?appId=='$AppId'].id" --output tsv
    if (-not $ServicePrincipalId) {
        Set-PrintAndLog -message "Creating Service Principal for App ID: $AppId" -Color DarkGreen
        $ServicePrincipalId = az ad sp create --id "$AppId" --query id --output tsv
        Set-PrintAndLog -message "Created Service Principal with ID: $ServicePrincipalId" -Color DarkGreen
    } else {
        Set-PrintAndLog -message "Service Principal already exists with ID: $ServicePrincipalId" -Color DarkGreen
    }

    # Step 4: Get Service Principal Type(s) from user, desired permissions, scopes, roles
    Set-PrintAndLog -message "Step 4: Get Service Principal Type(s) from user, desired permissions, scopes, roles" -Color DarkGreen
    $PowerBIAppId = az ad sp list --filter "displayName eq 'Power BI Service'" --query "[0].appId" --output tsv
    if (-not $PowerBIAppId) {
        $PowerBIAppId = "00000009-0000-0000-c000-000000000000"
        Set-PrintAndLog -message "Could not auto-detect Power BI App ID; falling back to default ID: $PowerBIAppId" -Color Yellow
    }

    $PermissionsToAssign = @()
    $PermissionsToAssign = $DelegatedPermissions + $ApplicationPermissions

    # Step 5, Apply Desired AD Service Principal Permissions/Scopes
    Set-PrintAndLog -message "Step 5, Apply Desired AD Service Principal Permissions/Scopes" -Color DarkGreen
    $DelegatedScopes = @()
    $ApplicationRoles = @()
    foreach ($permission in $PermissionsToAssign) {
        Set-PrintAndLog -message "Retrieving permission ID for '$permission'..." -Color DarkGreen
        $PermissionId = az ad sp show --id $PowerBIAppId --query "appRoles[?value=='$permission'].id" --output tsv
        if (-not $PermissionId) {
            $PermissionId = az ad sp show --id $PowerBIAppId --query "oauth2PermissionScopes[?value=='$permission'].id" --output tsv
            if ($PermissionId) {
                Set-PrintAndLog -message "Granting $permission ($PermissionId) as Scope (Delegated permission)..." -Color Green
                $DelegatedScopes += "$PermissionId=Scope"
            } else {
                Set-PrintAndLog -message "Warning: Permission '$permission' not found in Microsoft Graph API!" -Color DarkYellow
            }
        } else {
            Set-PrintAndLog -message "Granting $permission ($PermissionId) as Role (Application permission)..." -Color Green
            $ApplicationRoles += "$PermissionId=Role"
        }
    }
    Set-PrintAndLog -message "Step 5, Apply Desired AD Service Principal Permissions/Scopes" -Color DarkGreen
    if ($DelegatedScopes.Count -gt 0) {
        Set-PrintAndLog -message "Applying Delegated permissions..." -Color DarkGreen
        foreach ($scope in $DelegatedScopes) {
            Start-Sleep -Seconds 6
            az ad app permission add --id $AppId --api $PowerBIAppId --api-permissions "$scope" *> $null
        }
    }
    if ($ApplicationRoles.Count -gt 0) {
        Set-PrintAndLog -message "Applying Application permissions..." -Color DarkGreen
        foreach ($role in $ApplicationRoles) {
            Start-Sleep -Seconds 6
            az ad app permission add --id $AppId --api $PowerBIAppId --api-permissions "$role" *> $null
        }
    }
    if ($DelegatedScopes.Count -gt 0) {
        Start-Sleep -Seconds 8
        Set-PrintAndLog -message "Granting admin consent for Delegated permissions..." -Color DarkGreen
        az ad app permission grant --id $AppId --api $PowerBIAppId --scope ($DelegatedScopes -replace "=Scope", "" -join " ")  *> $null
    }
    if ($ApplicationRoles.Count -gt 0) {
        Start-Sleep -Seconds 8
        Set-PrintAndLog -message "Granting admin consent for Application permissions..." -Color DarkGreen
        az ad app permission admin-consent --id $AppId  *> $null
    }
    # Print final summary in a structured way
    return @{
        AppId                   = $AppId
        TenantId                = $TenantId
        ServicePrincipalId      = $ServicePrincipalId
        AppSecret               = $(az ad app credential reset --id $AppId --query password --output tsv)
        DefaultAccount          = $($AzAccounts | Where-Object { $_.isDefault -eq $true })
        GraphAppId              = $PowerBIAppId
        Account                 = $account
        RegistrationUrl         = "https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/Authentication/appId/$AppId/isMSAApp~/false?Microsoft_AAD_IAM_legacyAADRedirect=true"
    }



}

function EnsureRegistration {
    param (
        [string]$clientId,
        [string]$tenantId,
        [array]$delegatedPermissions,
        [array]$ApplicationPermissions
    )

    if ($clientId -and $tenantId) {
        return @{
            clientId = $clientId
            tenantId = $tenantId
        }
    }

    while ($true) {
        if ((Select-ObjectFromList -objects @("enter","new") -message "Would you like to enter your App Registration info or make a new Registration?") -eq "new") {
            $newAppRegResult = Set-AzureAppRegistration -SamDisplayName $(Get-SafeTitle $(Read-Host "Enter title for your new app registration")) `
                -delegatedPermissions  $delegatedPermissions `
                -ApplicationPermissions $ApplicationPermissions

            if ($newAppRegResult -and $newAppRegResult.TenantId -and $newAppRegResult.AppId) {
                $tenantId = $newAppRegResult.TenantId
                $clientId = $newAppRegResult.AppId
            } else {
                Write-Warning "App registration failed. Try again."
                continue
            }
            $PowerBIConfigUrl="https://app.powerbi.com/admin-portal/tenantSettings?language=en-US&experience=power-bi"
            Set-PrintAndLog -message "For Single-Use: make sure Device Code Flow is enabled in your app registration." -Color Cyan
            Write-Host "`nTo do this:" -ForegroundColor DarkCyan
            Write-Host "1. Open your app registration in Azure Portal $($newAppRegResult.RegistrationUrl)" -ForegroundColor DarkCyan
            Write-Host "2. Go to Authentication > Advanced Settings" -ForegroundColor DarkCyan
            Write-Host "3. Under 'Allow public client flows', enable 'Allow device code flow'" -ForegroundColor DarkCyan
            Write-Host ""
            Set-PrintAndLog -message "For Recurring Noninteractive use (reccomended): Create an Client Secret (App Secret) in your registration and allow for use in PowerBI Admin Dashboard" -Color Cyan
            Write-Host "1. Open your app registration in Azure Portal $($newAppRegResult.RegistrationUrl)" -ForegroundColor DarkCyan
            Write-Host "2. Under Certificates and Secrets, generate or regenerate App Secret" -ForegroundColor DarkCyan
            Write-Host "3. In PowerBI Admin Dashboard ($PowerBIConfigUrl) check to allow service principals to A: Allow service principals to create and manage workspaces and B: Allow service principals to create and manage workspaces" -ForegroundColor DarkCyan
            Write-Host "`nOpening both URLs for your convenience"  -ForegroundColor DarkCyan
            
            Start-Process $($newAppRegResult.RegistrationUrl)
            Start-Process $($PowerBIConfigUrl)
            
            Read-Host "Press Enter when Finished"
        } else {
            $tenantId = $tenantId ?? $(Read-Host "Enter your Microsoft Tenant ID")
            $clientId = $clientId ?? $(Read-Host "Enter your App Registration Client ID")

            if (-not $tenantId -or -not $clientId) {
                Write-Warning "Both Tenant ID and Client ID are required."
                continue
            }
        }

        if ($clientId -and $tenantId) { break }
    }

    return @{
        clientId = $clientId
        tenantId = $tenantId
    }
}
function Remove-AppRegistrationAndSP {
    param (
        [Parameter(Mandatory=$true)][string]$AppId,
        [Parameter(Mandatory=$false)][bool]$AndServicePrincipal = $true
    )

    # Check if az is available
    $azPath = Get-Command az -ErrorAction SilentlyContinue
    if (-not $azPath) {
        Set-PrintAndLog -message "Azure CLI wasnt used for creating registration during this run. Opening Entra Portal to manually delete the app registration..."
        Start-Process "https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/Overview/appId/$AppId/isMSAApp~/false?Microsoft_AAD_IAM_legacyAADRedirect=true"
        return
    }

    # Delete App Registration
    Set-PrintAndLog -message "Deleting App Registration: $AppId" -ForegroundColor Yellow
    az ad app delete --id $AppId

    # Delete associated Service Principal if requested
    if ($AndServicePrincipal) {
        Set-PrintAndLog -message "Attempting to delete matching Service Principal..." -Color Yellow
        $spId = az ad sp list --filter "appId eq '$AppId'" --query '[0].id' --output tsv
        if ($spId) {
            az ad sp delete --id $spId
            Set-PrintAndLog -message "Service Principal removed: $spId" -Color Green
        } else {
            Set-PrintAndLog -message "No Service Principal found." -Color Gray
        }
    }
}