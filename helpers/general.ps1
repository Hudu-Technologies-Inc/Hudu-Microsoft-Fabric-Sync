function Get-EnsuredModule {
    param ($Name)
    if (-not (Get-Module -ListAvailable -Name $Name)) {
        Install-Module $Name -Scope CurrentUser -Force -AllowClobber
    }
    Import-Module $Name -Force
}

function Unwrap-SinglePropertyWrapper {
    param (
        [Parameter(Mandatory)]
        $InputObject
    )

    $obj = $InputObject
    write-host "before: $($obj | ConvertTo-Json -depth 6 | Out-String)"
    while (
        $obj -isnot [string] -and
        ($obj -is [hashtable] -or $obj -is [pscustomobject]) -and
        $obj.PSObject.Properties.Count -eq 1
    ) {
        $value = $obj.PSObject.Properties[0].Value

        # Break loop if it's scalar or array
        if ($value -is [string] -or $value -is [int] -or $value -is [array]) {
            break
        }
        
        $obj = $value
    }
    write-host "after: $($obj | ConvertTo-Json -depth 6 | Out-String)"
    read-host
    return $obj
}
function Unset-Vars {
    param (
        [string]$varname,
        [string[]]$scopes = @('Local', 'Script', 'Global', 'Private')
    )

    foreach ($scope in $scopes) {
        if (Get-Variable -Name $varname -Scope $scope -ErrorAction SilentlyContinue) {
            Remove-Variable -Name $varname -Scope $scope -Force -ErrorAction SilentlyContinue
            Write-Host "Unset `$${varname} from scope: $scope"
        }
    }
}

function Prompt-IfMissing {
    param ($varRef, $prompt)
    if (-not $varRef.Value) { $varRef.Value = Read-Host $prompt }
}
function Write-ErrorObjectsToFile {
    param (
        [Parameter(Mandatory)]
        [object]$ErrorObject,

        [Parameter()]
        [string]$Name = "unnamed",

        [Parameter()]
        [ValidateSet("Black","DarkBlue","DarkGreen","DarkCyan","DarkRed","DarkMagenta","DarkYellow","Gray","DarkGray","Blue","Green","Cyan","Red","Magenta","Yellow","White")]
        [string]$Color
    )

    $stringOutput = try {
        $ErrorObject | Format-List -Force | Out-String
    } catch {
        "Failed to stringify object: $_"
    }

    $propertyDump = try {
        $props = $ErrorObject | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name
        $lines = foreach ($p in $props) {
            try {
                "$p = $($ErrorObject.$p)"
            } catch {
                "$p = <unreadable>"
            }
        }
        $lines -join "`n"
    } catch {
        "Failed to enumerate properties: $_"
    }

    $logContent = @"
==== OBJECT STRING ====
$stringOutput

==== PROPERTY DUMP ====
$propertyDump
"@

    if ($ErroredItemsFolder -and (Test-Path $ErroredItemsFolder)) {
        $SafeName = ($Name -replace '[\\/:*?"<>|]', '_') -replace '\s+', ''
        if ($SafeName.Length -gt 60) {
            $SafeName = $SafeName.Substring(0, 60)
        }
        $filename = "${SafeName}_error_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
        $fullPath = Join-Path $ErroredItemsFolder $filename
        Set-Content -Path $fullPath -Value $logContent -Encoding UTF8
        if ($Color) {
            Write-Host "Error written to $fullPath" -ForegroundColor $Color
        } else {
            Write-Host "Error written to $fullPath"
        }
    }

    if ($Color) {
        Write-Host "$logContent" -ForegroundColor $Color
    } else {
        Write-Host "$logContent"
    }
}

function Get-PercentDone {
    param (
        [int]$Current,
        [int]$Total
    )
    if ($Total -eq 0) {
        return 100}
    $percentDone = ($Current / $Total) * 100
    if ($percentDone -gt 100){
        return 100
    }
    $rounded = [Math]::Round($percentDone, 2)
    return $rounded
}   
function Set-PrintAndLog {
    param (
        [string]$message,
        [Parameter()]
        [Alias("ForegroundColor")]
        [ValidateSet("Black","DarkBlue","DarkGreen","DarkCyan","DarkRed","DarkMagenta","DarkYellow","Gray","DarkGray","Blue","Green","Cyan","Red","Magenta","Yellow","White")]
        [string]$Color
    )
    $logline = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $message"
    if ($Color) {
        Write-Host $logline -ForegroundColor $Color
    } else {
        Write-Host $logline
    }
    Add-Content -Path $LogFile -Value $logline
}
function Select-ObjectFromList($objects,$message,$allowNull = $false) {
    $validated=$false
    while ($validated -eq $false){
        if ($allowNull -eq $true) {
            Write-Host "0: None/Custom"
        }
        for ($i = 0; $i -lt $objects.Count; $i++) {
            $object = $objects[$i]
            if ($null -ne $object.OptionMessage) {
                Write-Host "$($i+1): $($object.OptionMessage)"
            } elseif ($null -ne $object.name) {
                Write-Host "$($i+1): $($object.name)"
            } else {
                Write-Host "$($i+1): $($object)"
            }
        }
        $choice = Read-Host $message
        if ($null -eq $choice -or $choice -lt 0 -or $choice -gt $objects.Count +1) {
            Set-PrintAndLog -message "Invalid selection. Please enter a number from above"
        }
        if ($choice -eq 0 -and $true -eq $allowNull) {
            return $null
        }
        if ($null -ne $objects[$choice - 1]){
            return $objects[$choice - 1]
        }
    }
}
function Get-SafeFilename {
    param([string]$Name,
        [int]$MaxLength=25
    )

    # If there's a '?', take only the part before it
    $BaseName = $Name -split '\?' | Select-Object -First 1

    # Extract extension (including the dot), if present
    $Extension = [System.IO.Path]::GetExtension($BaseName)
    $NameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($BaseName)

    # Sanitize name and extension
    $SafeName = $NameWithoutExt -replace '[\\\/:*?"<>|]', '_'
    $SafeExt = $Extension -replace '[\\\/:*?"<>|]', '_'

    # Truncate base name to 25 chars
    if ($SafeName.Length -gt $MaxLength) {
        $SafeName = $SafeName.Substring(0, $MaxLength)
    }

    return "$SafeName$SafeExt"
}
function Get-SafeTitle {
    param ([string]$Name)

    if (-not $Name) {
        return "untitled"
    }
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($Name)
    $decoded = [uri]::UnescapeDataString($baseName)
    $safe = $decoded -replace '[\\/:*?"<>|]', ' '
    $safe = ($safe -replace '\s{2,}', ' ').Trim()
    return $safe
}
function Set-LastSyncedTimestampFile {
    param (
        [Parameter(Mandatory)]
        [string]$DirectoryPath,
        [string]$schemaName
    )

    if (-not (Test-Path $DirectoryPath)) {
        throw "Directory '$DirectoryPath' does not exist."
    }

    Get-ChildItem -Path $DirectoryPath -Filter 'last_synced_at*' -File -ErrorAction SilentlyContinue | Remove-Item -Force

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $newFile = Join-Path $DirectoryPath "$(Get-SafeTitle $schemaName)_last_synced_at_$timestamp"

    New-Item -Path $newFile -ItemType File -Force | Out-Null

    Write-Host "Created sync marker: $newFile"
}
