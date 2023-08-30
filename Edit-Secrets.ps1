param (
    [string]$TenantName = "Andrews McMeel Universal",
    [string]$SubscriptionName = "AMU Pay-as-you-go",
    [string]$File = 'Secrets.json',
    [string]$RepositoryName = (git remote get-url origin).Split("/")[-1].Replace(".git", ""),
    [string]$SetFile = 'Set-Secrets.ps1',
    [string]$KeyVaultName,
    [string]$SecretName,
    [switch]$VersionHistory = $false,
    [int]$VersionHistoryLength = 10
)

# Check to see if Azure PowerShell Module is installed
if (!(Get-Module -ListAvailable Az.KeyVault)) {
    Write-Host "Installing Azure Powershell Module..."
    Install-Module -Name Az.KeyVault -Confirm:$false
}

# Check if user needs to log in
if (!(Get-AzContext)) {
    Write-Host "Cannot retrieve AzContext. Running 'Connect-AzAccount'" -ForegroundColor DarkGray
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
Write-Host "AzContext set to 'TenantName=$TenantName' and 'SubscriptionName=$SubscriptionName'" -ForegroundColor DarkGray

# Don't clear the ${File}.tmp file if using the VersionHistory option
if (!$VersionHistory) {
    Clear-Content -Path "${File}.tmp" -ErrorAction SilentlyContinue
}

# Get key vault names
if (!$PSBoundParameters.ContainsKey('KeyVaultName')) {
    Write-Host "Searching for key vaults with tag: 'repository-name=$RepositoryName'" -ForegroundColor DarkGray
    $KeyVaultNames = (Get-AzKeyVault -Tag @{"repository-name" = "$RepositoryName" }).VaultName

    if ($KeyVaultNames) {
        Write-Host "Key vaults found: $KeyVaultNames" -ForegroundColor DarkGray
    }
    else {
        Write-Error "No key vaults found. Please make sure the key vault is tagged correctly"  -ForegroundColor Red
    }
}
else {
    $KeyVaultNames = $KeyVaultName
}

# Create key vaults dictionary
$KeyVaults = New-Object PSCustomObject
$KeyVaultNames | ForEach-Object {
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

# Check if ${File} already exists before proceeding
if (Test-Path "${File}") {
    # Compare current and working files
    if (((Get-FileHash "${File}.tmp").Hash) -ne ((Get-FileHash "${File}").Hash)) {
        # Ask user if they want to overwrite their existing ${File}
        $choice = $(Write-Host "File '$File' exists. Overwrite? (y/N)" -ForegroundColor Yellow; Read-Host)
        if ($choice.ToUpper() -eq "N") {
            Write-Host "No changes made to $File" -ForegroundColor DarkGray
            Remove-Item -Path "${File}.tmp" -ErrorAction SilentlyContinue
            # Exit out if user chooses not to overwrite the file
            exit 0
        }
    }
    else {
        Write-Host "No changes made to file '$File'" -ForegroundColor DarkGray
        Remove-Item -Path "${File}.tmp" -ErrorAction SilentlyContinue
        # Exit out if the hashes are the same
        exit 0
    }
}

Copy-Item -Path "${File}.tmp" -Destination "${File}"
Remove-Item -Path "${File}.tmp" -ErrorAction SilentlyContinue

Write-Host "✨ File '$File' generated" -ForegroundColor Green
Write-Host "Once you've finished editing $File, please update this project's Azure Key Vaults by running '$SetFile'" -ForegroundColor Yellow