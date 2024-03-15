param (
    [string]$File = 'Secrets.json',
    [string]$RepositoryName = (git remote get-url origin).Split("/")[-1].Replace(".git", ""),
    [string]$KeyVaultName,
    [string]$SecretName,
    [switch]$VersionHistory = $false,
    [int]$VersionHistoryLength = 10,
    [switch]$Force,
    [switch]$Verbose = $false
)

$TenantName = "Andrews McMeel Universal"
$SubscriptionName = "AMU Pay-as-you-go"
$SetFile = 'Set-Secrets.ps1'

function Test-FileExists {
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )

    if ((Test-Path $FilePath) -and (! $Force)) {
        # Compare current and working files
        if (((Get-FileHash "${SecretValue}.tmp").Hash) -ne ((Get-FileHash $FilePath).Hash)) {
            # Ask user if they want to overwrite their existing file
            $choice = $(Write-Host "File '$FilePath' exists. Overwrite? (y/N)" -ForegroundColor Yellow; Read-Host)
            if ($choice.ToUpper() -eq "N") {
                Write-Host "No changes made to $FilePath" -ForegroundColor DarkGray
                Remove-Item -Path "${SecretValue}.tmp" -ErrorAction SilentlyContinue
                return $false
            }
        }
        else {
            Write-Host "File $FilePath is already up-to-date." -ForegroundColor DarkGray
            Remove-Item -Path "${SecretValue}.tmp" -ErrorAction SilentlyContinue
            return $false
        }
    }
    return $true
}

function Get-KeyVaultName {
    param (
        [string]$RepositoryName,
        [switch]$Verbose
    )

    if ($Verbose) {
        $VerbosePreference = 'Continue'
    }

    # Search for key vault using tags
    Write-Verbose "Searching for key vaults with tag: 'repository-name=$RepositoryName'"
    $KeyVaultName = (Get-AzKeyVault -Tag @{"repository-name" = "$RepositoryName" }).VaultName

    # Check if key vault name is empty
    if (!$KeyVaultName) {
        Write-Error "Key vault name cannot be found. Please confirm this repository's key vaults are tagged correctly."
        return
    }
    else {
        return $KeyVaultName
    }
}

function Set-AzureContext {
    param (
        [string]$SubscriptionName,
        [string]$TenantName
    )

    # Check to see if Azure PowerShell Module is installed
    if (!(Get-Module -ListAvailable Az.KeyVault)) {
        Write-Host "Installing Azure Powershell Module..."
        Install-Module -Name Az.KeyVault -Confirm:$false
    }

    # Check if user needs to log in
    if (!(Get-AzContext)) {
        Write-Output "Cannot retrieve AzContext. Running 'Connect-AzAccount'"
        [void](Connect-AzAccount -Subscription $SubscriptionName -Force)
    }

    # Check if tenant is available
    $Tenant = Get-AzTenant -ErrorAction SilentlyContinue | Where-Object Name -match "$TenantName"
    if (!$Tenant) {
        Write-Error "Cannot retrieve '$TenantName' tenant. Please try logging in with 'Connect-AzAccount'"
        return
    }

    # Switch to the correct subscription and tenant
    [void](Set-AzContext -SubscriptionName $SubscriptionName -Tenant $Tenant.Id)
}

# Set Azure context
Set-AzureContext -SubscriptionName $SubscriptionName -TenantName $TenantName

# Get key vault name
if (!$PSBoundParameters.ContainsKey('KeyVaultName')) {
    $KeyVaultName = Get-KeyVaultName -RepositoryName $RepositoryName -Verbose:$Verbose
}

# Clear file if not viewing version history
if (!$VersionHistory) {
    Clear-Content -Path "${File}.tmp" -ErrorAction SilentlyContinue
}

# Create key vaults dictionary
$KeyVaults = New-Object PSCustomObject
$KeyVaultName | ForEach-Object {
    $KeyVaultName = $_
    Write-Host "Generating secrets for $KeyVaultName..." -ForegroundColor DarkGray
    
    # Create key vault hash table
    $KeyVault = @()

    # Set Secrets object depending on $SecretName argument
    if ($PSBoundParameters.ContainsKey('SecretName')) {
        $Secrets = $SecretName.ToLower().Replace('_', '-')
    }
    else {
        $Secrets = (Get-AzKeyVaultSecret -VaultName $_).Name
    }

    # Loop through Secrets objects
    $Secrets | ForEach-Object {
        $SecretName = $_.ToUpper().Replace('-', '_').Replace('`"', '')

        if ($VersionHistory) {
            # Create version history hash table
            $VersionHistoryHash = @()

            # Set separate value to use in loop
            $OriginalSecretName = $_

            $Versions = Get-AzKeyVaultSecret -VaultName "$KeyVaultName" -Name "${_}" -IncludeVersions
            $Versions | ForEach-Object {
                $Version = $_.Version

                # Convert secret updated time to CST
                $Updated = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId($_.Updated, 'Central Standard Time')
                $SecretValue = Get-AzKeyVaultSecret -VaultName "$KeyVaultName" -Name "$OriginalSecretName" -Version "$Version" -AsPlainText

                # Set $Updated to [datetime] type to fix AM/PM indicator
                $VersionHash = @{
                    "Version"     = "$Version"
                    "SecretValue" = "$SecretValue"
                    "Updated"     = [datetime]"$Updated"
                }

                # Append to version history hash table
                $VersionHistoryHash += $VersionHash
            }
            Write-Host "Retrieving last $VersionHistoryLength revisions of $SecretName..." -ForegroundColor DarkGray
            Write-Host "[$KeyVaultName] Versions for ${SecretName}:" -ForegroundColor Green

            # Format hash table
            $VersionHistoryHash |
            Sort-Object -Property Updated -Descending -Top $VersionHistoryLength |
            Select-Object -Property Updated, SecretValue |
            Format-Table -AutoSize

            # Continue
            return
        }
        else {
            # Set secret properties
            $SecretValue = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $_ -AsPlainText
            $ContentType = (Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $_).ContentType

            # Create secret hash
            $SecretHash = @{
                "SecretName"  = "$SecretName"
                "SecretValue" = "$SecretValue"
                "ContentType" = "$ContentType"
            }

            # Append to key vault hash table
            $KeyVault += $SecretHash
        }
    }
    # Append to key vaults dictionary
    $KeyVaults | Add-Member -NotePropertyName $KeyVaultName -NotePropertyValue $KeyVault
}

if ($VersionHistory) {
    # Exit out if viewing version history
    exit 0
}

Add-Content -Path "${File}.tmp" -Value ($KeyVaults | ConvertTo-Json)

# Finish up
if (Test-FileExists -FilePath $SecretValue) {
    Copy-Item -Path "${File}.tmp" -Destination "${File}"
    Remove-Item -Path "${File}.tmp" -Force -ErrorAction SilentlyContinue
    Write-Host "✨ ${File} file generated" -ForegroundColor Green
    Write-Host "Once you've finished editing $File, please update this project's Azure Key Vaults by running '$SetFile'" -ForegroundColor Yellow
}