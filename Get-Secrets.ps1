param (
    [string]$TenantName = "Andrews McMeel Universal",
    [string]$SubscriptionName = "AMU Pay-as-you-go",
    [string]$KeyVaultName,
    [string]$File = '.env',
    [string]$RepositoryName = ((git remote get-url origin).Split("/")[-1].Replace(".git", "")),
    [string]$Environment = "development"
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

# Clear temporary file
Clear-Content -Path "${File}.tmp" -ErrorAction SilentlyContinue

# Check if searching for key vaults by repository name or otherwise, if key vault name argument is given
if (!$PSBoundParameters.ContainsKey('KeyVaultName')) {
    # If $Environment argument isn't set, use default value
    if (!$PSBoundParameters.ContainsKey('Environment')) {
        Write-Host "Environment missing. Defaulting to $Environment." -ForegroundColor DarkGray
    }

    # Search for key vault using tags
    Write-Host "Searching for key vault with tags: 'repository-name=$RepositoryName;environment=$Environment'" -ForegroundColor DarkGray
    $KeyVaultName = (Get-AzKeyVault -Tag @{"environment" = "$Environment" } | Get-AzKeyVault -Tag @{"repository-name" = "$RepositoryName" }).VaultName

    # Check if key vault name is empty
    if (!$KeyVaultName) {
        Write-Error "Key vault name cannot be found. Please confirm this repository's key vaults are tagged correctly."
        return
    }
}
else {
    # Just output KeyVaultName if passed as an argument
    Write-Host "Searching for key vault named: $KeyVaultName" -ForegroundColor DarkGray
}

# Get key vault object
$KeyVault = Get-AzKeyVault -Name "$KeyVaultName"

# Check if key vault exists
if (!$KeyVault) {
    Write-Error "Invalid value provided for 'KeyVaultName'. Please confirm a Key Vault exists under the name specified. Value provided: $KeyVaultName"
    return
}
Write-Host "Key vault found: $KeyVaultName" -ForegroundColor DarkGray

# Set secrets list 
$Secrets = (Get-AzKeyVaultSecret -VaultName "$KeyVaultName").Name

# Create secret hash
$SecretHash = @()

# Loop through secrets and add them to ${File}.tmp
Write-Host "Retrieving secrets..." -ForegroundColor DarkGray
$Secrets | ForEach-Object {
    # Convert to upper case snake case and remove quotes
    $SecretName = $_.ToUpper().Replace("-", "_").Replace("`"", "")

    # Get secret value and set it to the secret name
    $SecretValue = (Get-AzKeyVaultSecret -VaultName "$KeyVaultName" -Name $_).SecretValue | ConvertFrom-SecureString -AsPlainText

    # Add secret to hash
    $SecretHash += [pscustomobject]@{SecretName = $SecretName; SecretValue = $SecretValue }

    # Add secret to temporary file
    Add-Content -Path "${File}.tmp" -Value "$SecretName=$SecretValue"
}

# Output secret variable
$SecretHash | Format-Table

# Copy the temporary file over the original file
Copy-Item -Path "${File}.tmp" -Destination "${File}"
Remove-Item -Path "${File}.tmp"-Force -ErrorAction SilentlyContinue

# Output success
Write-Host "✨ .env file generated from $KeyVaultName" -ForegroundColor Green