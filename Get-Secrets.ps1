param (
    [string]$KeyVaultName,
    [string]$File = '.env',
    [string]$RepositoryName = ((git remote get-url origin).Split("/")[-1].Replace(".git", "")),
    [string]$Environment = "development",
    [switch]$Verbose = $false
)

$TenantName = "Andrews McMeel Universal"
$SubscriptionName = "AMU Pay-as-you-go"


function Get-KeyVaultName {
    param (
        [string]$RepositoryName,
        [string]$Environment,
        [switch]$Verbose
    )

    if ($Verbose) {
        $VerbosePreference = 'Continue'
    }

    # Search for key vault using tags
    if ($Environment) {
        Write-Verbose "Searching for key vault with tags: 'repository-name=$RepositoryName;environment=$Environment'"
        $KeyVaultName = (Get-AzKeyVault -Tag @{"environment" = "$Environment" } | Get-AzKeyVault -Tag @{"repository-name" = "$RepositoryName" }).VaultName
    }
    else {
        Write-Verbose "Searching for key vaults with tag: 'repository-name=$RepositoryName'"
        $KeyVaultName = (Get-AzKeyVault -Tag @{"repository-name" = "$RepositoryName" }).VaultName
    }

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
    $KeyVaultName = Get-KeyVaultName -RepositoryName $RepositoryName -Environment $Environment -Verbose:$Verbose
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

# Loop through secrets and add them to the temporary file
Clear-Content -Path "${File}.tmp" -ErrorAction SilentlyContinue
Write-Host "Retrieving secrets..." -ForegroundColor DarkGray
$Secrets | ForEach-Object {
    # Set secret object
    $Secret = (Get-AzKeyVaultSecret -VaultName "$KeyVaultName" -Name $_)

    # Convert secret name to upper case snake case and remove quotes
    $SecretName = $_.ToUpper().Replace("-", "_").Replace("`"", "")

    # Get secret value
    $SecretValue = $Secret.SecretValue | ConvertFrom-SecureString -AsPlainText

    # Get content type
    $SecretContentType = $Secret.ContentType

    # Add secret to hash
    $SecretHash += [pscustomobject]@{SecretName = $SecretName; SecretValue = $SecretValue }

    # Add secret to temporary file
    Add-Content -Path "${File}.tmp" -Value "$SecretName=$SecretValue"
}

# Output secret variable
$SecretHash | Format-Table

# Finish up
Copy-Item -Path "${File}.tmp" -Destination "${File}"
Remove-Item -Path "${File}.tmp" -Force -ErrorAction SilentlyContinue
Write-Host "✨ ${File} file generated" -ForegroundColor Green