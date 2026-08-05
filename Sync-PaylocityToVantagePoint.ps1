
<#   Webhook URL as of 3-18-26.     Remember to refresh every time webhook changes.

https://cf14e64d-ba81-401b-8266-8bc2401f54e0.webhook.eus.azure-automation.net/webhooks?token=3otztcgvLrtck5MGNPqkXBp4%2fcTQCfaMhOa1ZiYp7Dc%3d


#>

param
(
    [Parameter(Mandatory=$false)]
    [object] $WebhookData,
    [Parameter(Mandatory=$false)]
    [string]$PaylocityID,   #this is only for testing or manually updating someone
    [Parameter(Mandatory=$false)]
    [int]$Test
) 

Try {
 
    write-output "start"
    write-output ("object type: {0}" -f $WebhookData.gettype())
    write-output $WebhookData
    echo $WebhookData
    write-output "`n`n"
    write-output $WebhookData.WebhookName
    write-output $WebhookData.RequestBody
    write-output $WebhookData.RequestHeader
    write-output "end"

    $PaylocityID = (Convertfrom-json -InputObject $WebhookData.RequestBody).employeeid

}
Catch {

    write-output "Webhook is not being used..."
}


#Comment this line out for production runs
$test = 1

$DebugPreference = "Continue"   #set to SilentContinue to ignore write-debug statements

Connect-AzAccount -identity
# Import our custom modules
write-output "Importing Paylocity module..."
Import-Module Paylocity
write-output "Importing VantagePoint module..."
Import-Module VantagePoint

Write-output "Using PaylocityID = $PaylocityID"


#Set email addresses for notifications
$HelpDeskEmail = 'helpdesk@mcmillanpazdansmith.com'
$BusinessTeamEmail = 'payroll@mcmillanpazdansmith.com'
$BusinessTeamEmail1 = 'jcolvin@mcmillanpazdansmith.com'
$ITManagerEmail = 'dsnider@mcmillanpazdansmith.com'
$HREmail = 'HR@mcmillanpazdansmith.com'

#If the test flag is set, change the DB and email addresses
if ($test) {

    $HelpDeskEmail = 'dsnider@mcmillanpazdansmith.com'
    $BusinessTeamEmail = 'dsnider@mcmillanpazdansmith.com'
    $BusinessTeamEmail1 = 'dsnider@mcmillanpazdansmith.com'
    $ITManagerEmail = 'dsnider@mcmillanpazdansmith.com'
    $HREmail = 'dsnider@mcmillanpazdansmith.com'
}



#Global variables for logging to Azure SQL
$Global:LogServerName = "mps-datawarehousesql"    # Azure SQL logical server name  
$Global:LogDatabaseName = "Automation_logs"     # Azure SQL database name
$Global:LogResourceGroup = "MPS-DataWarehouse"

#Get access token for SQL
$queryParameter = "?resource=https://database.windows.net/" 
$url = $env:IDENTITY_ENDPOINT + $queryParameter
$Headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]" 
$Headers.Add("X-IDENTITY-HEADER", $env:IDENTITY_HEADER) 
$Headers.Add("Metadata", "True") 
$content =[System.Text.Encoding]::Default.GetString((Invoke-WebRequest -UseBasicParsing -Uri $url -Method 'GET' -Headers $Headers).RawContentStream.ToArray()) | ConvertFrom-Json 
$Global:SQLToken = $content.access_token 



#Retrieve VantagePoint credentials
$VaultName = "Paylocity-Key-Vault"
$Global:username = Get-AzKeyVaultSecret -VaultName $vaultName -Name "VisionUser" -AsPlainText
$Global:password = Get-AzKeyVaultSecret -VaultName $vaultName -Name "VisionPW" -AsPlainText
$Global:ClientID = Get-AzKeyVaultSecret -VaultName $vaultName -Name "VantagePointClientID" -AsPlainText
$Global:ClientSecret = Get-AzKeyVaultSecret -VaultName $vaultName -Name "VantagePointClientSecret" -AsPlainText

#Retrieve Paylocity credentials
$Global:PaylocityUser = Get-AzKeyVaultSecret -VaultName $vaultName -Name "ClientID" -AsPlainText
$Global:PaylocityPW = Get-AzKeyVaultSecret -VaultName $vaultName -Name "ClientSecret" -AsPlainText

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


#Retrieve token for subsequent Paylocity API calls
write-output "ClientID: $PaylocityUser"
write-output "ClientSecret: $PaylocityPW"

Write-output "Getting Paylocity token..."
$global:PaylocityToken = Get-Token
write-output "Paylocity token: $paylocityToken"



##    END OF SETUP





#Fetch record from Paylocity
Write-Output "Getting Paylocity record..."
$PaylocityEmployee = get-PaylocityEmployee -PaylocityID $PaylocityID

<#  Uncomment to inject test data.
$PaylocityEmployee.PaylocityID = '2000'
$PaylocityEmployee.FirstName = 'test'
$PaylocityEmployee.LastName = 'testLast'
$PaylocityEmployee.workemail =  'test@mps.com'
#>

$PaylocityEmployee








#Create an employee object for Vision- NOW VANTAGEPOINT
#OLD     $NewVisionEmployee = Get-NewVisionFromPaylocity -PaylocityEmployee $PaylocityEmployee
$NewVantagePointEmployee = Get-NewVantagePointFromPaylocity -baseURL $BaseUrl -token $VPAccessToken -PaylocityEmployee $PaylocityEmployee

#If adjustedSenioritydate is not defined, set to to hiredate by default
if ($NewVantagePointEmployee.AdjustedSeniorityDate.Length -eq 0) {
        write-output "Setting AdjustedSeniorityDate to HireDate."
        $NewVantagePointEmployee.AdjustedSeniorityDate = $NewVantagePointEmployee.HireDate
    }

write-output "Paylocity converted to VantagePoint..."
$NewVantagePointEmployee









#Load VantagePoint record if it exists (checking for PaylocityID and then email)
write-output "Getting any existing VantagePoint record"
$VantagePointEmployee = Get-VantagePointEmployee -BaseURL $BaseURL -token $VPAccessToken -PaylocityID $PaylocityEmployee.PaylocityID

    if ($VantagePointEmployee.Employee.length -eq 0) {
            #Vision record for Paylocity ID wasn't found, so look for email address
            Write-Output "Getting Vision information using email..."
            $VantagePointEmployee = Get-VantagePointEmployee -BaseURL $BaseURL -token $VPAccessToken -Email $PaylocityEmployee.workemail
    }

#Load the current Employee into the NewVantagePointEmployee object or create one if there's no current employee record
If ($VantagePointEmployee.Employee.length -eq 0) {
        write-output "New Vision Record. Getting new Vision ID."
        $NewVantagePointEmployee.Employee = Get-NewEmployeeID -FirstName $PaylocityEmployee.FirstName -PreferredName $PaylocityEmployee.preferredName -LastName $PaylocityEmployee.LastName
        $VantagePointEmployee = New-VantagePointEmployee
    }
    Else
    {
        write-output "Existing Vision record. Vision ID: $($VantagePointEmployee.Employee)"
        $NewVantagePointEmployee.Employee = $VantagePointEmployee.Employee
    }

$VantagePointEmployee









#Compare New Vision Object with Vision object. If there is no current vision employee, create a blank object for comparison
$ResultsHTML = ""
$ResultsHTML = Compare-PaylocityVantagePoint -VantagePointEmployee $VantagePointEmployee -NewVantagePointEmployee $NewVantagePointEmployee

write-output "Comparison results obtained."





#  ERROR CHECKING SECTION    

        $StatusMessage = ""        #This will be prepended to the email later
        $UpdateFlag = $true        #THis will be used to skip trying to update Vision.

        #Check for blank labor category
        If ($NewVantagePointEmployee.LaborCategory.Length -eq 0 ) {
                $StatusMessage += "Warning: Position Code $($PaylocityEmployee.PositionCode) could not be mapped to labor category in VantagePoint. `r`n"
                #$UpdateFlag = $False
            }

        #Check for illegal ORG
        If ($NewVantagePointEmployee.Org.Length -lt 5 ) {
                $StatusMessage += "Error:  ORG/Costcenter 1,2,or 3 (ORG: $($NewVantagePointEmployee.org) ) is ill-defined in Paylocity.  `r`n"
                $UpdateFlag = $False
            }

        #Check for blank Team number
        If ($NewVantagePointEmployee.Team.Length -eq 0 ) {
                $StatusMessage += "Error:  Team Number ( $($PaylocityEmployee.CostCenter3) ) is incorrect in Paylocity.`r`n"
                $UpdateFlag = $False
            }

        #Check for blank Office
        If ($NewVantagePointEmployee.Office.Length -eq 0 ) {
                $StatusMessage += "Error:  Office ( $($PaylocityEmployee.CostCenter1) )is incorrect in Paylocity.`r`n"
                $UpdateFlag = $False
            }

        #Check for wrong Practice Area
        If ($NewVantagePointEmployee.PracticeArea.Length -lt 2 ) {
                $StatusMessage += "Error:  Practice Area ( $($PaylocityEmployee.CostCenter2) )is incorrect in Paylocity.`r`n"
                $UpdateFlag = $False
            }

        #Check for MPS email
        if ($NewVantagePointEmployee.WorkEmail -notmatch "mcmillanpazdansmith.com") {
                $StatusMessage += "Warning: email ( $($NewVantagePointEmployee.workEmail) )is not in the MPS domain.`r`n"
            }

        #Check that paylocity email for a new employee doesn't match email for an existing employee
        if ($PaylocityEmployee.PaylocityID -ne $NewVantagePointEmployee.PaylocityID -and $NewVantagePointEmployee.PaylocityID.length -ne 0) {
                Write-Output "Email conflict!"
                Write-output "New Employee ID: $($PaylocityEmployee.PaylocityID)   Prior EmployeeID: $($NewVantagePointEmployee.PaylocityID)"
                $StatusMessage += "Error: Email for new employee matches email for prior employee"
                $UpdateFlag = $False
        }            

#END OF ERROR CHECKING SECTION
write-output "Status message after error checks: $StatusMessage"
write-output "Update flag after error checks: $UpdateFlag"
Write-output "Now on to updating VantagePoint..."

#Check if there are any updates to perform
$Changes = Compare-PaylocityVantagePointUpdateFlag -VantagePointEmployee $VantagePointEmployee -NewVantagePointEmployee $NewVantagePointEmployee

if (!$Changes) {

        #There were no changes to note, so just send a notification email.
        $Subject = "INFO: Paylocity had no change necessary for VantagePoint $($VantagePointEmployee.Employee)"
        $Body = "There are no changes for VantagePoint. `r`n"
        $Body += "$StatusMessage `r`n"
        $body += $ResultsHTML
        
        $Subject
        $Params = @{
            "To" = @("$ITManagerEmail","$HREmail", "$BusinessTeamEmail1") #@("$ITManagerEmail","$HREmail") is the usual setting here
            "Body" = $Body
            "Subject" = $Subject
        }

        .\Secure-Email.ps1 @Params

        Write-log -Message "No Paylocity update necessary for $($PaylocityEmployee.firstname) $($PaylocityEmployee.lastname)." -level Information -tag "Info" -ErrorRecord $StatusMessage -function "Sync_Paylocity"
    }


ElseIf (!$UpdateFlag) {

        write-output "Update flag after error checks(2): $UpdateFlag"
        
        $Subject = "ERROR: Paylocity couldn't update VantagePoint $($NewVantagePointEmployee.Employee)"
        write-output $StatusMessage
        $Body = "$StatusMessage `r`n"
        $body += $ResultsHTML
        
        $Subject

        $Params = @{
            "To" = @("$ITManagerEmail","$HREmail", "$BusinessTeamEmail1")
            "Body" = $Body
            "Subject" = $Subject
        }
            .\Secure-Email.ps1 @params

        Write-log -Message "Paylocity update for $($PaylocityEmployee.firstname) $($PaylocityEmployee.lastname) failed." -level Error -tag "Error" -ErrorRecord $StatusMessage -function "Sync_Paylocity"
    }
    Else
    {

        write-output "UPDATE: Now updating VantagePoint $($NewVantagePointEmployee.Employee)"

        #Create the body object for the insert or update API calls
        $Body = @{
            Employee = $NewVantagePointEmployee.Employee
            LastName= $NewVantagePointEmployee.LastName
            FirstName= $NewVantagePointEmployee.FirstName
            MiddleName= $NewVantagePointEmployee.MiddleName
            HireDate= $NewVantagePointEmployee.HireDate
            #Status= $NewVantagePointEmployee.Status   #don't update status automatically. This will remain a manual update by Payroll dept
            Type= "E"
            Org= $NewVantagePointEmployee.Org
            BillingCategory= $NewVantagePointEmployee.LaborCategory
            EMail= $NewVantagePointEmployee.WorkEmail
            DefaultLC1= $NewVantagePointEmployee.LaborCategory
            Salutation= $NewVantagePointEmployee.Salutation
            Suffix= $NewVantagePointEmployee.Suffix
            Title= $NewVantagePointEmployee.JobTitle
            Supervisor= $NewVantagePointEmployee.SupervisorID
            WorkPhone= $NewVantagePointEmployee.WorkPhone
            MobilePhone= $NewVantagePointEmployee.MobilePhone
            AvailableForCRM= "Y"
            ReadyForApproval= "Y"
            ReadyForProcessing= "Y"
            PreferredName= $NewVantagePointEmployee.PreferredName
            CustPaylocityID= $NewVantagePointEmployee.PaylocityID
            custOfficeLocation= $NewVantagePointEmployee.Office
            CustAdjustedSeniorityDate= $NewVantagePointEmployee.AdjustedSeniorityDate
            CustTeam= $NewVantagePointEmployee.team
            CustTeamLeader= $NewVantagePointEmployee.TeamLeaderFlag
            CustPaylocityEmployeeType= $NewVantagePointEmployee.PaylocityEmployeeType
        }

        $BodyJSON = $Body | ConvertTo-JSON

	    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        $headers.Add("content-type", "application/x-www-form-urlencoded")
        $headers.Add("Authorization", "Bearer $VPAccessToken")


        
TRY {
        #Send changes/additions to Vision
        #
        if ($VantagePointEmployee.Employee.Length -eq 0) {
                #$Xml = $XML -replace "</DefaultLC1>","</DefaultLC1><DefaultLC2>00</DefaultLC2>"

                write-output "Creating employee: $($NewVantagePointEmployee.employee)"

                $URL = "$BaseURL/employee"
                $response = Invoke-RestMethod $URL -Method post -headers $headers -body $body
            }
        ELSE 
            {
                write-output "Updating employee: $($VantagePointEmployee.employee)"
                $URL = "$BaseURL/employee/$($NewVantagePointEmployee.employee)"
                $response = Invoke-RestMethod $URL -Method put -headers $headers -body $body
            }

    }

catch {
    Write-Error "REST call failed: $($_.Exception.Message)"
}


if (!$response) { 

    write-output "No response was received."
    
}



    $responseJSON = $response | ConvertTo-JSON
    
    write-output "URL: $url"
    write-output "Body: $BodyJSON"
    write-output "Response: $responseJSON"

#Check result
if ($response.employee) {

        #Send notifications
        $body = "$StatusMessage `r`n"
        $body += $ResultsHTML
        $Subject = "VantagePoint employee updated/added from Paylocity - $($NewVantagePointEmployee.employee)"
  
        $Subject

        $Params = @{
            "To" = @("$ITManagerEmail","$HREmail", "$BusinessTeamEmail", "$BusinessTeamEmail1")
            "Body" = $Body
            "Subject" = $Subject
        }

        .\Secure-Email.ps1 @Params

        write-output "Email sent. Logging to db..."

        Write-Log -message "Paylocity update for $($PaylocityEmployee.firstname) $($PaylocityEmployee.lastname) succeeded." -ErrorRecord $StatusMessage -Tag "Success" -Level Information -function "Sync_Paylocity"
    }
    Else
    {
                #Send notifications
        $Subject = "ERROR: Paylocity couldn't update VantagePoint $($NewVantagePointEmployee.employee)"
        $Body = $result.DLTKVisionMessage.ReturnDesc
        $body += "`r`n"
        $body += $ResultsHTML
        
        $Subject
        $Params = @{
            "To" = @("$ITManagerEmail","$HREmail", "$BusinessTeamEmail1")
            "Body" = $Body
            "Subject" = $Subject
        }
        .\Secure-Email.ps1 @params

        write-output "Error Details: $($result.dltkvisionmessage.detail)"

        Write-Log -message "Paylocity update for $($PaylocityEmployee.firstname) $($PaylocityEmployee.lastname) failed." -ErrorRecord $result.DLTKVisionMessage.ReturnDesc -Tag "Error" -Level Error -function "Sync_Paylocity"
    }

} 
#>