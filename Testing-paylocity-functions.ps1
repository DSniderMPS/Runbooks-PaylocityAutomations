
import-module Paylocity
Connect-AzAccount -identity 

#  Checking the Labor Category lookup

$Global:URI = "https://evision1.visionhosted.com/mps/visionws.asmx?WSDL"
$Global:proxy = new-webserviceproxy $uri -Namespace X

$VisionUser = "blackbox"
$VisionPW = "Blackbox1"
$VisionDB = "MPSv76"

    $Global:ConnectionXML = "<VisionConnInfo>`
    <databaseDescription>$VisionDB</databaseDescription>`
    <userName>$VisionUser</userName>`
    <userPassword>$VisionPW</userPassword>`
    </VisionConnInfo>"
    
$DebugPreference = "Continue"
$PositionCode = "SOLTNENG"



$LC = Get-LaborCategory -positioncode $PositionCode

$LC


#>




<#  Creating new Employee object
$Paylocity = New-PaylocityEmployee

$paylocity
#>





<#  Sending email

$params = @{
    "To" = "dsnider@mcmillanpazdansmith.com"
    "Subject" = "This is a test email";
    "Body" = "Don't panic. It's just a test."
}

.\Secure-Email.ps1 @params
#>





#   Testing the logging function
<#Get access token for SQL
$queryParameter = "?resource=https://database.windows.net/" 
$url = $env:IDENTITY_ENDPOINT + $queryParameter
$Headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]" 
$Headers.Add("X-IDENTITY-HEADER", $env:IDENTITY_HEADER) 
$Headers.Add("Metadata", "True") 
$content =[System.Text.Encoding]::Default.GetString((Invoke-WebRequest -UseBasicParsing -Uri $url -Method 'GET' -Headers $Headers).RawContentStream.ToArray()) | ConvertFrom-Json 
$Global:SQLToken = $content.access_token 

$Global:LogServerName = "mps-datawarehousesql"
$Global:LogDatabaseName = "Automation_logs"

#Sample for getting records

$results = Invoke-Sqlcmd -ServerInstance "$LogServerName.database.windows.net" -Database $LogDatabaseName -AccessToken $SQLtoken -query 'select Top 10 * from Paylocity_log'

$results

$message = "Message"
$ErrorRecord = "ErrorRecord"
$Tag = "tag"
$Level = "Information"

#write-log -message $message -ErrorRecord $ErrorRecord -tag $Tag -level $Level -function "Testing-Paylocity"

#>




<# This is script to use the database, but if it isn't online, it will wait or timeout
#Get access token for SQL
$queryParameter = "?resource=https://database.windows.net/" 
$url = $env:IDENTITY_ENDPOINT + $queryParameter
$Headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]" 
$Headers.Add("X-IDENTITY-HEADER", $env:IDENTITY_HEADER) 
$Headers.Add("Metadata", "True") 
$content =[System.Text.Encoding]::Default.GetString((Invoke-WebRequest -UseBasicParsing -Uri $url -Method 'GET' -Headers $Headers).RawContentStream.ToArray()) | ConvertFrom-Json 
$Global:SQLToken = $content.access_token 

$Global:LogServerName = "mps-datawarehousesql"
$Global:LogDatabaseName = "Automation_logs"

$Params = @{
ServerName = $LogServerName
DatabaseName = $LogDatabaseName
ResourceGroupName = "MPS_DataWarehouse"
}

#Check for status of database. If not online, we must wake it up first.
$Status = (Get-AzSqlDatabase @params).status
write-output "Initial status: $status"

if ($Status -ne "online") {

    #Start the timer
    $stopWatch = New-Object -TypeName System.Diagnostics.Stopwatch
    $stopwatch.Start()

    $Timelimit = 3  #this sets a limit of 3 minutes for db to come online

    #Trigger the database to wake up.
    Invoke-Sqlcmd -ServerInstance "$LogServerName.database.windows.net" -Database $LogDatabaseName -AccessToken $SQLtoken -query 'select Top 10 * from Paylocity_log'

    #Wait until db is online or time limit is reached.
    Do
    {
        $Status = (Get-AzSqlDatabase @params).status

    } while ($Status -ne "Online" -and $stopWatch.Elapsed.TotalMinutes -lt $Timelimit)

    Write-output "Elapsed time was $($stopwatch.elapsed)"
    Write-output "Database status is $Status"

}

    #If db is back online, this should now work
    $results = Invoke-Sqlcmd -ServerInstance "$LogServerName.database.windows.net" -Database $LogDatabaseName -AccessToken $SQLtoken -query 'select Top 10 * from Paylocity_log'
    $results
#>
