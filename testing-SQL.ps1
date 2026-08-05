 
import-module sqlserver

#Get access token for SQL
$queryParameter = "?resource=https://database.windows.net/" 
$url = $env:IDENTITY_ENDPOINT + $queryParameter
$Headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]" 
$Headers.Add("X-IDENTITY-HEADER", $env:IDENTITY_HEADER) 
$Headers.Add("Metadata", "True") 
$content =[System.Text.Encoding]::Default.GetString((Invoke-WebRequest -UseBasicParsing -Uri $url -Method 'GET' -Headers $Headers).RawContentStream.ToArray()) | ConvertFrom-Json 
$SQLToken = $content.access_token 

$Content
$url

echo "IDENTITY_ENDPOINT: " + $env:IDENTITY_ENDPOINT
echo "IDENTITY_HEADER:" + $env:IDENTITY_HEADER


#Define server, tables and query
$LogServerName = "mps-datawarehousesql"    # Azure SQL logical server name  
$LogDatabaseName = "Automation_logs"     # Azure SQL database name 
$Global:LogResourceGroup = "MPS-DataWarehouse"

#$query = "select * from Paylocity_log"  #Sample query

#Get EST time since runbooks use UTC. 
$tDate =(Get-Date).ToUniversalTime()
$tz = [System.TimeZoneInfo]::FindSystemTimeZoneById("Eastern Standard Time")
$tCurrentTime = [System.TimeZoneInfo]::ConvertTimeFromUtc($tDate, $tz)



    [pscustomobject]$Fields = @{
        Time = (Get-Date -Date $tCurrentTime -Format "MM/dd/yyyy HH:mm")
        Level = "LOL"
        Function = "Function"
        Line = 100
        Tag = "Tag"
        Message = "Message"
        ErrorRecord = "ErrorRecord"
    }
    
    $Query = "Insert into Paylocity_log  VALUES ('$($Fields.Time)', '$($Fields.Level)', '$($Fields.Function)', '$($Fields.Line)', '$($Fields.Tag)', '$($Fields.Message)', '$($Fields.ErrorRecord)')"

    echo $query

    echo "$LogServerName.database.windows.net" 
    
$result = Invoke-Sqlcmd -ServerInstance "$LogServerName.database.windows.net" -Database Automation_logs -AccessToken $SQLtoken -query $Query 

$result
