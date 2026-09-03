
param
(
    [Parameter(Mandatory=$false)]
    [object] $WebhookData,
    [Parameter(Mandatory=$false)]
    [string]$callBackUri

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

    $CallbackURI = (Convertfrom-json -InputObject $WebhookData.RequestBody).callbackURI

    $PropertyList = (Convertfrom-json -InputObject $WebhookData.RequestBody).fields
}
Catch {

    write-output "Webhook is not being used..."
}


#Load API module
import-module Paylocity
Connect-AzAccount -identity


#This is the function to retrieve Lat and Long when given address
function Get-LatAndLong
{
		<#
	.SYNOPSIS
		    Given input parameters for a location, will return Geolocation data from an API
	
	.DESCRIPTION
		 
	    This pulls long/lat from an API at https://geocode.maps.co/

        Forward Geocode: https://geocode.maps.co/search?q=address&api_key=api_key

        Reverse Geocode: https://geocode.maps.co/reverse?lat=latitude&lon=longitude&api_key=api_key

        Examples:

        https://geocode.maps.co/search?q=555+5th+Ave+New+York+NY+10017+US&api_key=api_key

        Or you can search by name, e.g. for the Statue of Liberty:

        https://geocode.maps.co/search?q=Statue+of+Liberty+NY+US&api_key=api_key

        However, you can also reverse geocode by providing the following parameters (all are optional, but no results will be returned if none are supplied):

        street=<housenumber> <streetname>
        city=<city>
        county=<county>
        state=<state>
        country=<country>
        postalcode=<postalcode>

	.PARAMETER 1
		Street - the street address. Secondary (ie suite or apt numbers) are not necessary
	
	.PARAMETER 2
		City
	
	.PARAMETER 3
		State - This may only be relevant when Country="US", so we will blank it if country is something else

    .PARAMETER 4
        Country - will default to US if not supplied

    .PARAMETER 5
        Zip
                    		
	
	.EXAMPLE
        Get-LatAndLong -zip 29642
				
	
	.NOTES
		Additional information about the function.
#>
	
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $false)]
		[string]$Street,
		[Parameter(Mandatory = $false)]
		[string]$city,
		[Parameter(Mandatory = $false)]
		[string]$state,
		[Parameter(Mandatory = $false)]
		[string]$country="US",
        [Parameter(Mandatory = $false)]
        [string]$Zip

	)
	
	$APIKey = "679a32f16928f637158487rqe1aff16"

	$url = "https://geocode.maps.co/search?<search>api_key=$APIkey"

	$strSearch = ""

	#If the country isn't blank and isn't 'US', the state needs to be cleared. This may end up being a kludge for foreign projects, so may need
	#refinement later

	if ($country -and $Country -ne 'US') {
    		$State = ""
	}

	if ($Street) {
    		$strSearch = "street=" + $Street.replace(" ", "+") + "&"
	}

	if ($Zip) {
    		$strSearch += "postalcode=" + $Zip.replace(" ", "+") + "&"
	}

	ELSE {
        	# Only use the city and state if there is no zip code
    		if ($City) {
        		$strSearch += "city=" + $City.replace(" ", "+") + "&"
    		}

    		if ($State) {
        		$strSearch += "state=" + $State.replace(" ", "+") + "&"
    		}
	}

	if ($Country) {
    		$strSearch += "country=" + $Country.replace(" ", "+") + "&"
	} 
	Else {
    		$strSearch += "country=US&" 
	}

	$url = $url.replace("<search>",$strSearch)

    	return Invoke-RestMethod -Uri $url -Method Get #-Headers $headers
}







$VaultName = "Paylocity-Key-Vault"

#Retrieve Paylocity credentials
$Global:PaylocityUser = Get-AzKeyVaultSecret -VaultName $vaultName -Name "ClientID" -AsPlainText
$Global:PaylocityPW = Get-AzKeyVaultSecret -VaultName $vaultName -Name "ClientSecret" -AsPlainText

#Retrieve token for subsequent Paylocity API calls
$global:Paylocitytoken = Get-Token

#Set headers for API call
        $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        $headers.Add("Authorization", "Bearer $PaylocityToken")

    $PageSize = 5000
    $PageNumber = 0

    $PaylocityURI = "https://api.paylocity.com/api/v2/companies/N6635/employees?pagesize=$PageSize&pagenumber=$PageNumber&includetotalcount=true"



#Set API limit in calls per second. This will be used to slow down API calls to prevent overrun.
$APILimit = 25
$APIWaitTime = 1 / $APILimit * 1000   #This is the wait time in milliseconds

$AllPaylocity = Invoke-RestMethod $PaylocityURI -Method Get -headers $headers 

#Initiate output array
$Output = New-Object System.Data.DataTable
    $Output.Columns.add('PaylocityID')
    $Output.Columns.add('birthDate')
    $Output.Columns.add('firstName')
    $Output.Columns.add('lastName')
    $Output.Columns.add('employeeType')
    $Output.Columns.add('positionCode')
    $Output.Columns.add('jobTitle')
    $Output.Columns.add('statusType')
    $Output.Columns.add('hireDate')
    $Output.Columns.add('changeReason')
    $Output.Columns.add('terminationDate')
    $Output.Columns.add('studio')
    $Output.Columns.add('team')
    $Output.Columns.add('ethnicity')
    $Output.Columns.add('Associate')
    $Output.Columns.add('Principal')
    $Output.Columns.add('SeniorAssociate')
    $Output.Columns.add('LicensedArchitect')
    $Output.Columns.add('ManagementTeamMember')
    $Output.Columns.add('Gender')
    $Output.Columns.add('AnnualSalary')
    $Output.Columns.add('DefaultHours')
    $Output.Columns.add('PayFrequency')
    $Output.Columns.add('PayType')
    $Output.Columns.add('RatePer')
    $Output.Columns.add('Salary')
    $Output.Columns.add('TaxForm')
    $Output.Columns.add('EmployeeStatus')
    $Output.Columns.add('Address1')
    $Output.Columns.add('city')
    $Output.Columns.add('state')
    $Output.Columns.add('postalcode')
    $Output.Columns.add('Latitude')
    $Output.Columns.add('Longitude')
    $Output.Columns.add('workLatitude')
    $Output.Columns.add('workLongitude')
    $Output.Columns.add('location')



Foreach ($PaylocityID in $AllPaylocity) {

        $PaylocityURI = "https://api.paylocity.com/api/v2/companies/N6635/employees/" + $PaylocityID.employeeId
    
        $response = Invoke-RestMethod $PaylocityURI -Method Get -headers $headers 

        #wait to avoid API wait limit
        Start-sleep -Milliseconds $APIWaitTime

        $Row = $Output.NewRow()
            $Row.PaylocityID = $PaylocityID.employeeId
            $Row.birthDate = $response.birthDate
            $Row.firstName = $response.firstName
            $Row.lastName = $response.lastName
            $Row.employeeType = $response.departmentPosition.employeeType
            $Row.positionCode = $response.departmentPosition.positionCode
            $Row.jobTitle = $response.departmentPosition.jobTitle
            $Row.statusType = $response.status.statusType
            $Row.hireDate = $response.status.hireDate
            $Row.changeReason = $response.status.changeReason
            $Row.terminationDate = $response.status.terminationDate
            $Row.studio = $response.departmentPosition.costCenter1
            $Row.team = $response.departmentPosition.costCenter3
            $Row.ethnicity = $response.ethnicity

        $BooleanValues = $Response.customBooleanFields

            $Row.Associate = Switch ($($BooleanValues | where-object {$_.label -eq "Associate"}).value) { 'True' {'Y'} default {'N'}}
            $Row.Principal = Switch ($($BooleanValues | where-object {$_.label -eq "Principal"}).value) { 'True' {'Y'} default {'N'}}
            $Row.SeniorAssociate = Switch ($($BooleanValues | where-object {$_.label -eq "Senior Associate"}).value) { 'True' {'Y'} default {'N'}}
            $Row.LicensedArchitect = Switch ($($BooleanValues | where-object {$_.label -eq "Licensed Architect"}).value) { 'True' {'Y'} default {'N'}}
            $Row.ManagementTeamMember = Switch ($($BooleanValues | where-object {$_.label -eq "Management Team Member"}).value) { 'True' {'Y'} default {'N'}}

            $Row.Gender = $response.gender
            $Row.AnnualSalary = $response.primaryPayRate.AnnualSalary
            $Row.DefaultHours = $response.primaryPayRate.DefaultHours
            $Row.PayFrequency = $response.primaryPayRate.PayFrequency
            $Row.PayType = $response.primaryPayRate.PayType
            $Row.RatePer = $response.primaryPayRate.RatePer
            $Row.Salary = $response.primaryPayRate.Salary
            $Row.TaxForm = $response.departmentPosition.costCenter3
            $Row.EmployeeStatus = $response.status.EmployeeStatus
            $Row.Address1 = $response.homeAddress.Address1
            $Row.city = $response.homeAddress.city
            $Row.state = $response.homeAddress.state
            $Row.postalcode = $response.homeAddress.postalcode
            $Row.location = $response.workAddress.location


                #Get home location coordinates (NOTE: we are only using zip code at this point)
                $params = @{
                    #Street = $response.homeAddress.Address1
                    #City =$response.homeAddress.city
                    #State = $response.homeAddress.state
                    Zip = $response.homeAddress.postalcode
                    Country= $response.homeAddress.country
                }

                    #Try to get the location 5 times before moving on
                    $i = 0
                    Do {

                        Try {
                            $Location = Get-LatAndLong @params
                            $i = 5
                            }
                        Catch {
                            #Wait one second before trying again
                            Start-Sleep -Seconds 1
                            $i++
                            }
                    } Until ($i -eq 5)

                [double]$NewLatitude = $location[0].lat
                [double]$NewLongitude = $location[0].lon

            $Row.Latitude = $NewLatitude
            $Row.Longitude = $NewLongitude


                #Get work location coordinates
                $params = @{
                    Street = $response.workAddress.Address1
                    City =$response.workAddress.city
                    State = $response.workAddress.state
                    Zip = $response.workAddress.postalcode
                    Country= $response.workAddress.country
                }

                    #Try to get the location 5 times before moving on
                    $i = 0
                    Do {

                        Try {
                            $Location = Get-LatAndLong @params
                            $i = 5
                            }
                        Catch {
                            #Wait one second before trying again
                            Start-Sleep -Seconds 1
                            $i++
                            }
                    } Until ($i -eq 5)

                [double]$NewLatitude = $location[0].lat
                [double]$NewLongitude = $location[0].lon

            $Row.workLatitude = $NewLatitude
            $Row.workLongitude = $NewLongitude


        $Output.Rows.add($row)


    }


    #Save any results returned to a CSV file in Azure
$OutputFile = $env:temp +"\PaylocityExtendedData.csv"
$OutputFile

$Output | export-csv -path $OutputFile -notypeinformation

 

# storage account information
$StorageAccountName = "mpswarehousestorage"
#$StorageAccountKey = ""
$ContainerName = "paylocity"

$Context = New-AzStorageContext -StorageAccountName $StorageAccountName -UseConnectedAccount
$Container = Get-AzStorageContainer -Container $ContainerName -Context $Context 

# export the query result to blob storage
$Container | Set-AzStorageBlobContent -File $OutputFile -BlobType Block -Force -Verbose

write-output "Done."

$callbackResponse = Invoke-WebRequest -Uri $callbackuri -UseBasicParsing -Method POST -ContentType "application/json" #-Body $OutputJson