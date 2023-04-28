param (
    [string]$File = 'Secrets.json',
    [string]$RepositoryName = (git remote get-url origin).Split("/")[-1].Replace(".git",""),
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

if (!$VersionHistory) {
    Clear-Content -Path "${File}.tmp" -ErrorAction SilentlyContinue
}

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

$KeyVaults = New-Object PSCustomObject
$KeyVaultNames | ForEach-Object {
    $KeyVaultName = $_
    Write-Host "Generating secrets for $KeyVaultName..." -ForegroundColor DarkGray
    $KeyVault = @()
    if ($PSBoundParameters.ContainsKey('SecretName')) {
        $Secrets = $SecretName.ToLower().Replace("_", "-")
    }
    else {
        $Secrets = (Get-AzKeyVaultSecret -VaultName $_).Name
    }
    $Secrets | ForEach-Object {
        $OriginalSecretName = $_
        $SecretName = $_.ToUpper().Replace("-", "_").Replace("`"", "")
        if ($VersionHistory) {
            $Versions = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $_ -IncludeVersions

            $VersionHistoryHash = @()
            $Versions | ForEach-Object {
                $Version = $_.Version
                $Updated = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId($_.Updated, 'Central Standard Time')
                $SecretValue = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $OriginalSecretName -Version $Version -AsPlainText
                $VersionHash = @{
                    "Version" = "$Version"
                    "SecretValue" = "$SecretValue"
                    "Updated" = [datetime]"$Updated"
                }    
                $VersionHistoryHash += $VersionHash
            }
            Write-Host "Retrieving last $VersionHistoryLength revisions of $SecretName..." -ForegroundColor DarkGray
            Write-Host "[$KeyVaultName] Versions for ${SecretName}:" -ForegroundColor Green
            $VersionHistoryHash | 
                Sort-Object -Property Updated -Descending -Top $VersionHistoryLength |
                Select-Object -Property Updated,SecretValue |
                Format-Table -AutoSize
            return
        }
        else {
            $SecretValue = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $_ -AsPlainText
            $ContentType = (Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $_).ContentType  

            $SecretHash = @{
                "SecretName" = "$SecretName"
                "SecretValue" = "$SecretValue"
                "ContentType" = "$ContentType"
            }
            $KeyVault += $SecretHash
        }
    }
    $KeyVaults | Add-Member -NotePropertyName $KeyVaultName -NotePropertyValue $KeyVault
}

if ($VersionHistory) {
    exit 0
}

Add-Content -Path "${File}.tmp" -Value ($KeyVaults | ConvertTo-Json)

if (Test-Path "${File}") {
    if (((Get-FileHash "${File}.tmp").Hash) -ne ((Get-FileHash "${File}").Hash)) {
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
}

Copy-Item -Path "${File}.tmp" -Destination "${File}"

Write-Host "✨ $File file generated" -ForegroundColor Green
Write-Host "Once you've finished editing $File, please update this project's Azure Key Vaults by running '$SetFile'" -ForegroundColor Yellow

Remove-Item -Path "${File}.tmp" -ErrorAction SilentlyContinue