
## PowerShell Runbook for Azure Automation to send mail securely using Key Vault, Azure AD App and Microsoft Graph API ##
## MartijnBrant.net ##

Param(
    [Parameter (Mandatory=$false)]
    $To,
    [Parameter (Mandatory=$false)]
    [string]$Subject,
    [Parameter (Mandatory=$false)]
    [string]$Body,
    [Parameter (Mandatory=$false)]
    [string]$HTML   #flag for HTML email
    
    )


<#  Uncomment for testing 
    $To = @("dsnider@mcmillanpazdansmith.com", "aarmstrong@mcmillanpazdansmith.com")
    $Subject = "This is a test email"
    $Body = "Please do not panic. Just let David Snider know you got this."
#>

###### Change these values ######

	# Name of your Key Vault
	$KeyVaultName = "Secure-Email-Keys"

	# Name of the secret in your Key Vault
	$KeyVaultSecretName = "AzureADAppSecret"

	# The Application ID of your Azure AD App Registraion
	$client_id = '5af4dc8c-c069-4bcd-8150-f27eb957ce0c'

	# The Tenant ID (can be found at Azure AD App Registration
	$tenant_id = '2f2f3064-9dcf-49ea-a3ca-341498ba0cea'
	
	# The From Address needs to be a valid email address of an Exchange-Online/Office 365 mail-enabled user
	$fromAddress = 'canon@mcmillanpazdansmith.com'

    write-output $to

try
{
    write-output "Logging in to Azure..."
    Connect-AzAccount -Identity
}
catch {
    Write-Error -Message $_.Exception
    throw $_.Exception
}

write-output 'Retrieving value from Key Vault...'
$KeyVaultSecretValue = (Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $KeyVaultSecretName).SecretValueText

write-output 'Getting the secret...'

$secret = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $KeyVaultSecretName
$ssPtr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret.SecretValue)
try {
   $secretValueText = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ssPtr)
} finally {
   [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ssPtr)
}

write-output 'Getting a token from Graph...'
$client_secret = $secretValueText
$request = @{
        Method = 'POST'
        URI    = "https://login.microsoftonline.com/$tenant_id/oauth2/v2.0/token"
        body   = @{
            grant_type    = "client_credentials"
            scope         = "https://graph.microsoft.com/.default"
            client_id     = $client_id
            client_secret = $client_secret
        }
    }

    write-output $request
    write-output $request.body

$RequestResults = Invoke-RestMethod @request
write-output "Token Request Results:" $RequestResults
$token = $RequestResults.access_token


$ToRecipients = @()
    foreach ($email in $To) {
        $ToRecipients += @{EmailAddress=@{Address=$email}}
    }

write-output $ToRecipients

write-output 'Build the graph API request'

# Build the Microsoft Graph API request
$params = @{
  "URI"         = "https://graph.microsoft.com/v1.0/users/$fromAddress/sendMail"
  "Headers"     = @{
    "Authorization" = ("Bearer {0}" -F $token)
  }
  "Method"      = "POST"
  "ContentType" = 'application/json'
  "Body" = (@{
    "message" = @{
      "subject" = $Subject
      "body"    = @{
        "contentType" = 'html'
        "content"     = $Body
      }
      "toRecipients" = $ToRecipients
    }
  }) | ConvertTo-JSON -Depth 10
}

write-output $params.body

write-output 'Sending mail via Graph...'
Invoke-RestMethod @params -Verbose

write-output 'All Done!'