
Connect-AzAccount -identity
$VaultName = "Paylocity-Key-Vault"

Import-Module Paylocity
 

#Retrieve Paylocity credentials
$Global:PaylocityUser = Get-AzKeyVaultSecret -VaultName $vaultName -Name "ClientID" -AsPlainText
$Global:PaylocityPW = Get-AzKeyVaultSecret -VaultName $vaultName -Name "ClientSecret" -AsPlainText


#Retrieve token for subsequent Paylocity API calls
Write-output "Getting Paylocity token..."
$global:PaylocityToken = Get-Token

write-output "Paylocity token: $paylocityToken"