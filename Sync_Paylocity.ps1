 
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

<#########################################################################

    Setup

##########################################################################

#$test = 1

$DebugPreference = "Continue"   #set to SilentContinue to ignore write-debug statements

Write-output "Using PaylocityID = $PaylocityID"

#Set DB information for Vision
$Global:VisionDB = "MPSv76"

#Set email addresses for notifications
$HelpDeskEmail = 'helpdesk@mcmillanpazdansmith.com'
$BusinessTeamEmail = 'payroll@mcmillanpazdansmith.com'
$BusinessTeamEmail1 = 'jcolvin@mcmillanpazdansmith.com'
$ITManagerEmail = 'dsnider@mcmillanpazdansmith.com'
$HREmail = 'HR@mcmillanpazdansmith.com'

#If the test flag is set, change the DB and email addresses
if ($test) {

    $Global:VisionDB = "MPSv76Test ***Testing Only"

    $HelpDeskEmail = 'dsnider@mcmillanpazdansmith.com'
    $BusinessTeamEmail = 'dsnider@mcmillanpazdansmith.com'
    $BusinessTeamEmail1 = 'dsnider@mcmillanpazdansmith.com'
    $ITManagerEmail = 'dsnider@mcmillanpazdansmith.com'
    $HREmail = 'dsnider@mcmillanpazdansmith.com'
}

#Proxy and URI for Vision
$Global:URI = "https://mps.visionhosted.com/mps/visionws.asmx?WSDL"
$Global:proxy = new-webserviceproxy $uri -Namespace X

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

write-output "ClientID: $PaylocityUser"
write-output "ClientSecret: $PaylocityPW"

#Retrieve token for subsequent Paylocity API calls
Write-output "Getting Paylocity token..."
$global:PaylocityToken = Get-Token

write-output "Paylocity token: $paylocityToken"

<######################################################################################

    Get info from Paylocity

########################################################################################

#Fetch record from Paylocity
Write-Output "Getting Paylocity record..."
$PaylocityEmployee = get-PaylocityEmployee -PaylocityID $PaylocityID

$PaylocityEmployee


<########################################################################################

Create an employee object for Vision from the Paylocity info

#########################################################################################


$NewVisionEmployee = Get-NewVisionFromPaylocity -PaylocityEmployee $PaylocityEmployee

#If adjustedSenioritydate is not defined, set to to hiredate by default
if ($NewVisionEmployee.AdjustedSeniorityDate.Length -eq 0) {
        write-output "Setting AdjustedSeniorityDate to HireDate."
        $NewVisionEmployee.AdjustedSeniorityDate = $NewVisionEmployee.HireDate
    }

write-output "Paylocity converted to Vision..."
$NewVisionEmployee


<########################################################################################

Load Vision record if it exists (checking for PaylocityID and then email)

#########################################################################################

write-output "Getting any existing Vision record"
$VisionEmployee = Get-VisionEmployee -PaylocityID $PaylocityID

    if ($VisionEmployee.visionID.length -eq 0) {
            #Vision record for Paylocity ID wasn't found, so look for email address
            Write-Output "Getting Vision information using email..."
            $VisionEmployee = Get-VisionEmployee -Email $PaylocityEmployee.workemail
    }




#Load the current VisionID into the NewVisionEmployee object or create one if there's no current employee record
If ($VisionEmployee.VisionID.length -eq 0) {
        write-output "New Vision Record. Getting new Vision ID."
        $NewVisionEmployee.VisionID = Get-NewEmployeeID -FirstName $PaylocityEmployee.FirstName -PreferredName $PaylocityEmployee.preferredName -LastName $PaylocityEmployee.LastName
        $VisionEmployee = New-VisionEmployee
    }
    Else
    {
        write-output "Existing Vision record. Vision ID: $($VisionEmployee.VisionID)"
        $NewVisionEmployee.VisionID = $VisionEmployee.VisionID
    }

#If adjustedSenioritydate is not defined, set to to hiredate by default
if ($NewVisionEmployee.AdjustedSeniorityDate.Length -eq 0) {
        write-output "Setting AdjustedSeniorityDate to HireDate."
        $NewVisionEmployee.AdjustedSeniorityDate = $NewVisionEmployee.HireDate
    }

$VisionEmployee


<########################################################################################

Compare New Vision Object. If there is no current vision employee, create a blank object for comparison with Vision object. 

#########################################################################################

$ResultsHTML = ""
$ResultsHTML = Compare-PaylocityVision -VisionEmployee $VisionEmployee -NewVisionEmployee $NewVisionEmployee

write-output "Comparison results obtained."

<########################################################################################

ERROR CHECKING SECTION 

#########################################################################################

        $StatusMessage = ""        #This will be prepended to the email later
        $UpdateFlag = $true        #THis will be used to skip trying to update Vision.

        #Check for blank labor category
        If ($NewVisionEmployee.LaborCategory.Length -eq 0 ) {
                $StatusMessage += "Warning: Position Code $($PaylocityEmployee.PositionCode) could not be mapped to labor category in Vision. `r`n"
                #$UpdateFlag = $False
            }

        #Check for illegal ORG
        If ($NewVisionEmployee.Org.Length -lt 5 ) {
                $StatusMessage += "Error:  ORG/Costcenter 1,2,or 3 (ORG: $($NewVisionEmployee.org) ) is ill-defined in Paylocity.  `r`n"
                $UpdateFlag = $False
            }

        #Check for blank Team number
        If ($NewVisionEmployee.Team.Length -eq 0 ) {
                $StatusMessage += "Error:  Team Number ( $($PaylocityEmployee.CostCenter3) ) is incorrect in Paylocity.`r`n"
                $UpdateFlag = $False
            }

        #Check for blank Office
        If ($NewVisionEmployee.Office.Length -eq 0 ) {
                $StatusMessage += "Error:  Office ( $($PaylocityEmployee.CostCenter1) )is incorrect in Paylocity.`r`n"
                $UpdateFlag = $False
            }

        #Check for wrong Practice Area
        If ($NewVisionEmployee.PracticeArea.Length -lt 2 ) {
                $StatusMessage += "Error:  Practice Area ( $($PaylocityEmployee.CostCenter2) )is incorrect in Paylocity.`r`n"
                $UpdateFlag = $False
            }

        #Check for MPS email
        if ($NewVisionEmployee.WorkEmail -notmatch "mcmillanpazdansmith.com") {
                $StatusMessage += "Warning: email ( $($NewVisionEmployee.workEmail) )is not in the MPS domain.`r`n"
            }

        #Check that paylocity email for a new employee doesn't match email for an existing employee
        if ($PaylocityEmployee.PaylocityID -ne $VisionEmployee.PaylocityID -and $VisionEmployee.PaylocityID.length -ne 0) {
                Write-Output "Email conflict!"
                Write-output "New Employee ID: $($PaylocityEmployee.PaylocityID)   Prior EmployeeID: $($VisionEmployee.PaylocityID)"
                $StatusMessage += "Error: Email for new employee matches email for prior employee"
                $UpdateFlag = $False
        }            

#END OF ERROR CHECKING SECTION
write-output "Status message after error checks: $StatusMessage"
write-output "Update flag after error checks: $UpdateFlag"
Write-output "Now on to updating Vision..."

<########################################################################################

Send any changes/additions to Vision. Only notification if no changes.

#########################################################################################

#Check if there are any updates to perform
$Changes = Compare-PaylocityVisionUpdateFlag -VisionEmployee $VisionEmployee -NewVisionEmployee $NewVisionEmployee

if (!$Changes) {

        #There were no changes to note, so just send a notification email.
        $Subject = "INFO: Paylocity had no change necessary for Vision $($VisionEmployee.VisionID)"
        $Body = "There are no changes for Vision. `r`n"
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


# There are changes, so check If UpdateFlag wasn't marked as false, and do the update
ElseIf (!$UpdateFlag) {
        $Subject = "ERROR: Paylocity couldn't update Vision $($VisionEmployee.VisionID)"
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

    #Create XML for adding/updating Vision record
    $XML = $NewVisionEmployee.OutputXML($NewVisionEmployee)

    #Send changes/additions to Vision
    #If it's a new employee, change the "Update" to "Insert". Also, add field 'defaultLC2' to make it default
    if ($VisionEmployee.visionID.Length -eq 0) {
        $Xml = $XML -replace "UPDATE", "INSERT"
        $Xml = $XML -replace "</DefaultLC1>","</DefaultLC1><DefaultLC2>00</DefaultLC2>"
        [xml]$result = $proxy.AddEmployee($ConnectionXML, $XML)
    }
    ELSE 
    {
        
        [xml]$result = $proxy.UpdateEmployee($ConnectionXML, $XML)
        
    }

$Xml

$result.dltkvisionmessage
$result.DLTKVisionMessage.detail.ValidationResult.message


#Check result
if ($result.DLTKVisionMessage.ReturnCode -eq 1) {

        #Send notifications
        $body = "$StatusMessage `r`n"
        $body += $ResultsHTML
        $Subject = "Vision employee updated/added from Paylocity - $($VisionEmployee.VisionID)"
  
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
        $Subject = "ERROR: Paylocity couldn't update Vision $($VisionEmployee.VisionID)"
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

}  # end If !$Updateflag
#>


#   Upon completion, also start a sync to the preview of Vantagepoint (This is temporary until fully switched over to VantagePoint)

        $URI = "https://cf14e64d-ba81-401b-8266-8bc2401f54e0.webhook.eus.azure-automation.net/webhooks?token=3otztcgvLrtck5MGNPqkXBp4%2fcTQCfaMhOa1ZiYp7Dc%3d"

        $headerMessage = @{message = "Manually sent from Powershell"}

        $data=   "{""companyId"":""N6635"",""employeeId"":""$PaylocityID"",""Test"":""$test""}"

        $Response = Invoke-WebRequest -method Post -uri $URI -header $headerMessage -body $data -UseBasicParsing