param (
    [string]$TenantName = "Andrews McMeel Universal",
    [string]$KeyVaultName,
    [string]$File = '.env',
    [string]$RepositoryName = ((git remote get-url origin).Split("/")[-1].Replace(".git","")),
    [string]$Environment = "development"
)

# Check to see if Azure PowerShell Module is installed
if (!(Get-Module -ListAvailable Az.KeyVault)) {
    Write-Host "Installing Azure Powershell Module..."
    Install-Module -Name Az.KeyVault -Confirm:$false
}

# Switch to AMU Tenant
Get-AzTenant | ForEach-Object {
    # Search for tenant ID that has a name matching $TenantName
    if ($_.Name | Select-String $TenantName) {
        $TenantId = Set-AzContext -TenantId $_.Id
    }
}

Clear-Content -Path "${File}.tmp" -ErrorAction SilentlyContinue

# If $KeyVaultName argument isn't set
if (!$PSBoundParameters.ContainsKey('KeyVaultName')) {
    # If $Environment argument isn't set, use default value
    if (!$PSBoundParameters.ContainsKey('Environment')) {
        Write-Host "Environment missing. Defaulting to $Environment." -ForegroundColor DarkGray
    }

    Write-Host "Searching for key vault with tags: 'repository-name=$RepositoryName;environment=$Environment'" -ForegroundColor DarkGray
    $KeyVaultName = (Get-AzKeyVault -Tag @{"environment" = "$Environment" } | Get-AzKeyVault -Tag @{"repository-name" = "$RepositoryName" }).VaultName
}
else {
    Write-Host "Searching for key vault named: $KeyVaultName" -ForegroundColor DarkGray
}

# Get secrets for the key vault
$Secrets = (Get-AzKeyVaultSecret -VaultName "$KeyVaultName").Name
Write-Host "Key vault found: $KeyVaultName" -ForegroundColor DarkGray
Write-Host "Retrieving secrets..." -ForegroundColor DarkGray

# Loop through secrets and add them to ${File}.tmp
$Secrets | ForEach-Object {
    $SecretName = $_.ToUpper().Replace("-", "_").Replace("`"", "")
    $SecretValue = (Get-AzKeyVaultSecret -VaultName "$KeyVaultName" -Name $_).SecretValue | ConvertFrom-SecureString -AsPlainText
    $Secret = "$SecretName" + "=" + "$SecretValue"
    Write-Host "$Secret"
    Add-Content -Path "${File}.tmp" -Value "$Secret"
}

Copy-Item -Path "${File}.tmp" -Destination "${File}"
Write-Host "✨ .env file generated from $KeyVaultName" -ForegroundColor Green