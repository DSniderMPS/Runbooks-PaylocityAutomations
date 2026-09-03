
Connect-AzAccount -identity
 
import-module sqlserver

# Import our custom module
write-output "Importing Paylocity module..."
Import-Module Paylocity
write-output "Importing VantagePoint module..."
Import-Module VantagePoint
 


#Retrieve VantagePoint credentials
$VaultName = "Paylocity-Key-Vault"
$Global:username = Get-AzKeyVaultSecret -VaultName $vaultName -Name "VisionUser" -AsPlainText
$Global:password = Get-AzKeyVaultSecret -VaultName $vaultName -Name "VisionPW" -AsPlainText
$Global:ClientID = Get-AzKeyVaultSecret -VaultName $vaultName -Name "VantagePointClientID" -AsPlainText
$Global:ClientSecret = Get-AzKeyVaultSecret -VaultName $vaultName -Name "VantagePointClientSecret" -AsPlainText

#Set VantagePoint server and database for token retrieval
$BaseURL = "https://mps.dvphosted.com/mps/api"
$database = "MPSVP_Preview"

#Get VantagePoint token
$Params = @{
username = $Username
password = $Password
ClientID = $ClientID
ClientSecret = $ClientSecret
database = $database
BaseURL = $BaseURL
}

write-output $Params

#Retrieve token for subsequent VantagePoint API calls
Write-output "Getting VantagePoint token..."
$VPAccessToken = Get-VantagePointToken @Params
write-output "VantagePoint token: $VPAccessToken"




#Retrieve Paylocity credentials
$Global:PaylocityUser = Get-AzKeyVaultSecret -VaultName $vaultName -Name "ClientID" -AsPlainText
$Global:PaylocityPW = Get-AzKeyVaultSecret -VaultName $vaultName -Name "ClientSecret" -AsPlainText

#Retrieve token for subsequent Paylocity API calls
Write-output "Getting Paylocity token..."
$global:PaylocityToken = Get-Token
write-output "Paylocity token: $PaylocityToken"

#Set up for reading SQL from data warehouse
#Get access token for SQL
$queryParameter = "?resource=https://database.windows.net/" 
$url = $env:IDENTITY_ENDPOINT + $queryParameter
$Headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]" 
$Headers.Add("X-IDENTITY-HEADER", $env:IDENTITY_HEADER) 
$Headers.Add("Metadata", "True") 
$content =[System.Text.Encoding]::Default.GetString((Invoke-WebRequest -UseBasicParsing -Uri $url -Method 'GET' -Headers $Headers).RawContentStream.ToArray()) | ConvertFrom-Json 
$Global:SQLToken = $content.access_token 

write-output "SQLToken: $SQLtoken"

$ServerName = "mps-datawarehousesql"    # Azure SQL logical server name  
$DatabaseName = "MPS-SQLDB"     # Azure SQL database name


#*************   End of setup



#Read employee data from data warehouse
$query = "SELECT TOP (100) PERCENT CustPaylocityID as PaylocityID FROM [dbo].[DW_EmployeeMaster] where status = 'a'"

$Records = Invoke-Sqlcmd -ServerInstance "$ServerName.database.windows.net" -Database $DatabaseName -AccessToken $SQLtoken -query $query

write-output "$($Records.count) records retrieved."

#Set counter for a progress indicator
$i = 0

Foreach ($PaylocityID in $Records.PaylocityID) {

    

    #every 20th record, give an indicator
    $i++
    if ($i % 20 -eq 0) {
        write-output "$i records processed."
    }


    # Fetch current info from Paylocity
    $PaylocityEmployee = Get-PaylocityEmployee -PaylocityID $PaylocityID

    write-output "Fetched $($PaylocityEmployee.firstname) $($PaylocityEmployee.lastname)"

        #Check that no error happened while retrieving Paylocity data
        if ($PaylocityEmployee.PaylocityID.length -lt 1) {

            write-output "Error retrieving ID: $PaylocityID from Paylocity."
            Continue
        }



#  UPDATE VP
    #Transform Paylocity data to VantagePoint data
    $NewVantagePointEmployee = Get-NewVantagePointFromPaylocity -PaylocityEmployee $PaylocityEmployee -token $VPAccessToken -BaseURL $BaseURL

    #Get VantagePoint data
    $VantagePointEmployee = Get-VantagePointEmployee -PaylocityID $PaylocityID -token $VPAccessToken -BaseURL $BaseURL

        #Verify that no error happened while retrieving VantagePoint data
        if ($VantagePointEmployee.PaylocityID.length -lt 1) {

            write-output "Error retrieving ID: $PaylocityID from VantagePoint."
            Continue
        }




#  UPDATE VP
    # These two fields will not generally match between Paylocity and VantagePoint. This isn't a bug, so ignore these two fields by setting them equivalent to each other.
        $NewVantagePointEmployee.AdjustedSeniorityDate = $VantagePointEmployee.AdjustedSeniorityDate
        $NewVantagePointEmployee.Employee = $VantagePointEmployee.Employee





    #The Paylocity Position codes may not match anything in VantagePoint. Uncomment this code to ignore those cases.
    <#
        if ($NewVantagePointEmployee.LaborCategory.length -eq 0) {
                $NewVantagePointEmployee.LaborCategory = $VantagePointEmployee.LaborCategory
                $NewVantagePointEmployee.LaborCategoryDesc = $VantagePointEmployee.LaborCategoryDesc
            }

    #>


#  UPDATE VP
    #Compare the two sources.
    $Changed = $false
    $Changed = Compare-PaylocityVantagePointUpdateFlag -VantagePointEmployee $VantagePointEmployee -NewVantagePointEmployee $NewVantagePointEmployee






    if ($Changed -AND $PaylocityID -ne 0) {

        #If changes noted, call webhook to sync
        Write-output "Syncing ID: $PaylocityID"

        #  UPDATE VP
        $URI = "https://cf14e64d-ba81-401b-8266-8bc2401f54e0.webhook.eus.azure-automation.net/webhooks?token=3otztcgvLrtck5MGNPqkXBp4%2fcTQCfaMhOa1ZiYp7Dc%3d"
        
        
        
        
        
        $headerMessage = @{message = "Manually sent from Powershell"}

        $data=   "{""companyId"":""N6635"",""employeeId"":""$PaylocityID"",""Test"":""$test""}"

        $Response = Invoke-WebRequest -method Post -uri $URI -header $headerMessage -body $data -UseBasicParsing

    }

}