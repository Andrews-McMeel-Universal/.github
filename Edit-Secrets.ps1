param (
    [string]$File = 'Secrets.json',
    [string]$RepositoryName = ((git remote get-url origin).Split("/")[-1].Replace(".git","")),
    [string]$SetFile = 'Set-Secrets.ps1'
)

#Check to see if Az module is installed
if (!(Get-Module -ListAvailable Az)) {
    Write-Host "Installing Azure Powershell Module." -ForegroundColor DarkGray
    Install-Module -Name Az -Confirm:$false
}
Import-Module Az -ErrorAction SilentlyContinue

Clear-Content -Path "${File}.tmp" -ErrorAction SilentlyContinue

Write-Host "Searching for key vaults with tag: @{'repository-name'='$RepositoryName'}" -ForegroundColor DarkGray
$KeyVaultNames = (Get-AzKeyVault -Tag @{"repository-name" = "$RepositoryName" }).VaultName

if ($KeyVaultNames) {
    Write-Host "Key vaults found: $KeyVaultNames" -ForegroundColor DarkGray
}
else {
    Write-Error "No key vaults found. Please make sure the key vault is tagged correctly"  -ForegroundColor Red
}

$KeyVaults = New-Object PSCustomObject
$KeyVaultNames | ForEach-Object {
    $KeyVaultName = $_
    Write-Host "Generating secrets for $KeyVaultName" -ForegroundColor DarkGray
    $KeyVault = @()
    $Secrets = (Get-AzKeyVaultSecret -VaultName $_).Name
    $Secrets | ForEach-Object {
        $SecretName = $_.ToUpper().Replace("-", "_").Replace("`"", "")
        $SecretValue = (Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $_).SecretValue | ConvertFrom-SecureString -AsPlainText
        $ContentType = (Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $_).ContentType  

        $SecretHash = @{
            "SecretName" = "$SecretName"
            "SecretValue" = "$SecretValue"
            "ContentType" = "$ContentType"
        }
        $KeyVault += $SecretHash
    }
    $KeyVaults | Add-Member -NotePropertyName $KeyVaultName -NotePropertyValue $KeyVault
}

Add-Content -Path "${File}.tmp" -Value ($KeyVaults | ConvertTo-Json)

if ((Test-Path "${File}") -and (((Get-FileHash "${File}.tmp").Hash) -ne ((Get-FileHash "${File}").Hash))) {
    $choice = $(Write-Host "The local copy of $File does not match what is currently in the Azure Key Vaults. Do you still want to overwrite it? (Y/N)" -ForegroundColor Yellow; Read-Host)
    if ($choice.ToUpper() -eq "N") {
        Write-Host "No changes made to $File" -ForegroundColor DarkGray
        Remove-Item -Path "${File}.tmp" -ErrorAction SilentlyContinue
        exit 0
    }
}
else {
    Write-Host "No changes made to $File" -ForegroundColor DarkGray
    Remove-Item -Path "${File}.tmp" -ErrorAction SilentlyContinue
    exit 0
}

Copy-Item -Path "${File}.tmp" -Destination "${File}"

Write-Host "$File file generated" -ForegroundColor Green
Write-Host "Once you've finished editing $File, please update this project's Azure Key Vaults by running '$SetFile'" -ForegroundColor Green

Remove-Item -Path "${File}.tmp" -ErrorAction SilentlyContinue