param (
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

Clear-Content -Path $File -ErrorAction SilentlyContinue

if (!"$KeyVaultName") {
    if (!$PSBoundParameters.ContainsKey('Environment')) {
        Write-Host "Environment missing. Defaulting to development." -ForegroundColor DarkGray
    }

    Write-Host "Searching for key vault with tags: 'repository-name=$RepositoryName;environment=$Environment'" -ForegroundColor DarkGray
    $KeyVaultName = (Get-AzKeyVault -Tag @{"environment" = "$Environment" } | Get-AzKeyVault -Tag @{"repository-name" = "$RepositoryName" }).VaultName
}
else {
    Write-Host "Searching for key vault named: $KeyVaultName" -ForegroundColor DarkGray
}

$Secrets = (Get-AzKeyVaultSecret -VaultName $KeyVaultName).Name

if ($Secrets) {
    Write-Host "Key vault found: $KeyVaultName" -ForegroundColor DarkGray
    Write-Host "Retrieving secrets..." -ForegroundColor DarkGray
}
$Secrets | ForEach-Object {
    $SecretName = $_.ToUpper().Replace("-", "_").Replace("`"", "")
    $SecretValue = (Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $_).SecretValue | ConvertFrom-SecureString -AsPlainText
    $Secret = $SecretName + "=" + $SecretValue
    Write-Host "$Secret"
    Add-Content -Path $File -Value $Secret
}

Write-Host "✨ .env file generated from $KeyVaultName" -ForegroundColor Green