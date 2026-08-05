
Connect-AzAccount -identity

import-module sqlserver
import-module Paylocity

#Set DB information for Vision
$Global:VisionDB = "MPSv76"

#Proxy and URI for Vision
$Global:URI = "https://mps.visionhosted.com/mps/visionws.asmx?WSDL"
$Global:proxy = new-webserviceproxy $uri -Namespace X

#Get Vision user and PW from secure vault
Connect-AzAccount -identity
$VaultName = "Paylocity-Key-Vault"
$Global:VisionUser = Get-AzKeyVaultSecret -VaultName $vaultName -Name "VisionUser" -AsPlainText
$Global:VisionPW = Get-AzKeyVaultSecret -VaultName $vaultName -Name "VisionPW" -AsPlainText

#This is the connection to the Vision database.
    $Global:ConnectionXML = "<VisionConnInfo>`
    <databaseDescription>$VisionDB</databaseDescription>`
    <userName>$VisionUser</userName>`
    <userPassword>$VisionPW</userPassword>`
    </VisionConnInfo>"

# Import our custom module
write-output "Importing Paylocity module..."
Import-Module Paylocity

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
$query = "SELECT CustPaylocityID as PaylocityID FROM [dbo].[DW_EmployeeMaster] where status = 'a'"

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

    #Transform Paylocity data to Vision data
    $NewVisionEmployee = Get-NewVisionFromPaylocity -PaylocityEmployee $PaylocityEmployee

    #Get Vision data
    $VisionEmployee = Get-VisionEmployee -PaylocityID $PaylocityID

        #Verify that no error happened while retrieving Vision data
        if ($VisionEmployee.PaylocityID.length -lt 1) {

            write-output "Error retrieving ID: $PaylocityID from Vision."
            Continue
        }

    # These two fields will not generally match between Paylocity and Vision. This isn't a bug, so ignore these two fields by setting them equivalent to each other.
        $NewVisionEmployee.AdjustedSeniorityDate = $VisionEmployee.AdjustedSeniorityDate
        $NewVisionEmployee.VisionID = $VisionEmployee.VisionID

    #The Paylocity Position codes may not match anything in Vision. Uncomment this code to ignore those cases.
    <#
        if ($NewVisionEmployee.LaborCategory.length -eq 0) {
                $NewVisionEmployee.LaborCategory = $VisionEmployee.LaborCategory
                $NewVisionEmployee.LaborCategoryDesc = $VisionEmployee.LaborCategoryDesc
            }

    #>

    #Compare the two sources.
    $Changed = Compare-PaylocityVisionUpdateFlag -VisionEmployee $VisionEmployee -NewVisionEmployee $NewVisionEmployee

    if ($Changed) {

        #If changes noted, call webhook to sync
        Write-output "Syncing ID: $PaylocityID"
        $URI = "https://cf14e64d-ba81-401b-8266-8bc2401f54e0.webhook.eus.azure-automation.net/webhooks?token=flB8%2fQzSsWG8PyBLyjM1W2D%2bQEOWiBXx8twexH%2fQHEI%3d"
        $headerMessage = @{message = "Manually sent from Powershell"}

        $data=   "{""companyId"":""N6635"",""employeeId"":""$PaylocityID"",""Test"":""$test""}"

        $Response = Invoke-WebRequest -method Post -uri $URI -header $headerMessage -body $data -UseBasicParsing

    }

}