<#
.SYNOPSIS
    Powershell management wrapper for the Netsapiens platform
.DESCRIPTION
    Upon running the script you will be prompted for your PBX credentials. Regardless of the functions in this script you will only be able to run commands available to your scope. I.e. Office Manager, Reseller, etc.
    You will also need to populate your config.json file and store it in the same folder as this script. Otherwise the script will not function. Contact OIT support for your client ID and secret.
.EXAMPLE
Get-LastBootTime -ComputerName localhost
.LINK
www.oitvoip.com
#>

## Trap any errors
trap [Net.WebException] { continue; }
#Add Web Assembly for URL encoding
Add-Type -AssemblyName System.Web

# Get authentication credentials
$Global:Creds = $host.ui.PromptForCredential("PBX Credentials", "Please enter your portal login and password.", "", "")
# Import configuration file
Try {
    $path = Join-Path -Path $PSScriptRoot "config.json"
    $global:Config = Get-Content -Path $path -Raw | ConvertFrom-Json
}
Catch {
    Write-Host "Unable to import configuration file. Verify it has been created and in the same folder as the script."
}
# Verify that you can authenticate against the API
Try {
    get-token
    Write-Host "You have been authenticated. Please continue."
}
Catch {
    Write-Host "Unable to authenticate. Please try again"
}
## Helper Functions
Function Get-Token() {
    ## Helper function to get an access token. Required to perform calls against the API
    ## Scopes: Any
    $nsapipassword = $Creds.GetNetworkCredential().Password
    $tokenURL = "https://" + $Config.NetSapiens.fqdn + "/ns-api/oauth2/token/?grant_type=password&client_id=" + $Config.NetSapiens.clientID + "&client_secret=" + $Config.NetSapiens.clientSecret + "&username=" + $creds.UserName + "&password=" + $nsapipassword

    $response = Invoke-RestMethod $tokenURL
    $currentdate = Get-Date

    $Global:apitoken = New-Object -TypeName psobject
    $apitoken | Add-Member NoteProperty -Name accesstoken -Value $response.access_token
    $apitoken | Add-Member NoteProperty -Name expiration -Value $currentdate.AddSeconds(3600)
}
Function Check-Domain {
    ## Checks if a domain exists
    ## Scopes: Any
    param (
        [Parameter(Mandatory = $true)][String]$domain
    )
    $payload = @{
        object = 'domain'
        action = 'count'
        domain = $domain
    }    
    $res = NS-Call $payload
    If ($res.total -eq 1) {
        return $res.total
    }
    else { 
        $res = 0
        Write-Host "Domain does not exist"
        return
    }    
}
Function NS-Call {
    ## Helper function to place API calls
    ## Scopes: Any
    param (
        [Parameter(Mandatory = $true)][Hashtable]$load,
        [Parameter(Mandatory = $false)][String]$type
    )
    # Check if payload submitted
    if (!$load) {
        Write-Host -ForegroundColor Red "Invalid or missing payload. Killing application"
        exit
    }
    # NS token expires in 1 hour. Check if token is still valid. If not, request a new one
    if ((!$apitoken) -or ((get-date) -lt $apitoken.expiration)) {
        Get-Token
    }

    # Check if request is POST or GET. Set GET by default
    if (!$type) { $type = "GET" }

    # Add format descriptor in case it's missing
    if (!$load.format) { $load.add('format', 'json') }

    # Set headers
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Authorization", 'Bearer ' + $apitoken.accesstoken)

    # Set request URL
    $requrl = "https://" + $Config.NetSapiens.fqdn + "/ns-api/"

    $response = Invoke-RestMethod $requrl -Headers $headers -Method $type -Body $load
    return $response
}

###############  Functions  ###################


## Call Center Functions
Function Count-Agents {
    ## Counts agents in a queue. 
    ## Scopes: Office Manager, Call Center Manager, Reseller, Super User
    param (
        [Parameter(Mandatory = $true)][String]$domain,
        [Parameter(Mandatory = $false)][String]$queue #extension number of queue
    )
    Check-Domain $domain
    $payload = @{
        object = 'agent'
        action = 'count'
        domain = $domain
    }
    if($queue){$payload.add('queue', $queue)}
    Try {
        $res = NS-Call $payload
        return $res
    }
    Catch {
        $res = "No data returned"
        return $res
    }
}

## Call Recording Functions
Function Get-CallRecording {
    ## Determine if call recording is enabled on a device
    ## Scopes: Office Manager, Reseller, Super User
    param (
        [Parameter(Mandatory = $true)][String]$domain
    )
    Check-Domain $domain
        $payload = @{
            object = 'device'
            action = 'read'
            domain = $domain
        }      
    Try {
        $res = NS-Call $payload
        $res = $res | Select-Object -Property subscriber_name, sub_fullname, call_processing_rule | Sort-Object subscriber_name | Where-Object{$_.call_processing_rule -match "Record"}
        $res | ForEach-Object {$_.call_processing_rule = "Enabled"}
        $newtblFormat = @{Expression={$_.subscriber_name};Label="User";},
                               @{Expression={$_.sub_fullname};Label="Name";},
                               @{Expression={$_.call_processing_rule};Label="Rec Enabled";}
        return $res | Format-Table $newtblFormat
    }
    Catch {
        $res = "No data returned"
        return $res
    }
}
## Domain Functions
Function Get-Domain {
    ## Reads the properties for a single domain
    ## Scopes: Reseller, Super User
    param (
        [Parameter(Mandatory = $true)][String]$domain
    )
    Check-Domain $domain
    $payload = @{
        object = 'domain'
        action = 'read'
        domain = $domain
    }    
    $res = NS-Call $payload
    If ($res) {
        return $res
    }
    else { 
        $res = "No data returned"
        return $res
    } 

}

## Device Functions
Function Get-Devices {
    ## Returns a list of devices per domain or user.
    ## Scopes: Any
    param (
        [Parameter(Mandatory = $true)][String]$domain,
        [Parameter(Mandatory = $false)][String]$user
    )
    Check-Domain $domain
    $payload = @{
        object = 'device'
        action = 'read'
        domain = $domain
    } 
    If ($user) { $payload.add('user', $user) }
    Try {
        $newtblFormat = @{Expression={$_.subscriber_name};Label="User";},
            @{Expression={$_.mode};Label="Status";},
            @{Expression={$_.aor};Label="Device";},
            @{Expression={$_.model};Label="Model";},
            @{Expression={$_.mac};Label="Mac";},
            @{Expression={$_.received_from};Label="Public IP";},
            @{Expression={$_.contact};Label="Contact IP (Private)";},
            @{Expression={$_.registration_time};Label="Last Registration";}
        $res = NS-Call $payload | Sort-Object "subscriber_name"
        $res | ForEach-Object {
            $_.aor = $_.aor.Substring(4)
            $_.aor = $_.aor -replace $domain
            $_.aor = $_.aor -replace "@"
            $_.aor = $_.aor -replace ".video.bridge"
            $_.aor = $_.aor -replace ".conference-bridge"
            # @TODO Filter Contact IP
            #$_.contact = "stuff"
            #$contact = $_.contact
            #$a = $contact.IndexOf("@")
            #$_.contact = $a
            #$contact = $contact.Substring($a+1)
            #$b = $contact.IndexOf(";")
            #$_.contact = $contact.Substring(0,$b)
        }
        $res = $res | Format-Table $newtblFormat
        return $res
    } Catch {
        $res = "No data returned"
        return $res
    }    
}
## Number functions
Function Get-e911 {
    ## Reads all e911 numbers registered to a domain. Returns list and count of numbers.
    ## Scopes: Office Manager, Reseller, Super User
    param (
        [Parameter(Mandatory = $true)][String]$domain
    )
    Check-Domain $domain
    $payload = @{
        object = 'callidemgr'
        action = 'read'
        domain = $domain
    }
    $res = NS-Call $payload
    $didlist = @()
    $didcount = 0
    Foreach ($num in $res) {
        $curDID = $num.callid
        If ($curDID.length -eq 11) {
            $didlist += $curDID.Substring(1)
        }
        else {
            $didlist += $curDID
        }
    }
    $didlist = $didlist | select -Unique | Sort-Object
    $didcount = $didlist.count
    $didtotals = New-Object -TypeName psobject
    $didtotals | Add-Member -NotePropertyName "e911 Count" -NotePropertyValue $didcount
    $didtotals | Add-Member -NotePropertyName "e911 List" -NotePropertyValue $didlist

    if ($didtotals) { return $didtotals }else {
        $res = "No e911 numbers assigned"
        return $res
    }
}
Function Get-DIDs {
    ## Reads all DIDs in a domain. Returns list of DIDs as well as counts
    ## Scopes: Office Manager, Reseller, Super User
    param (
        [Parameter(Mandatory = $true)][String]$domain
    )
    Check-Domain $domain
    $payload = @{
        object      = 'phonenumber'
        action      = 'read'
        dialplan    = 'DID Table'
        dest_domain = $domain
    }    
    $numlist = NS-Call $payload
    $numlist = $numlist | Select-Object -Property matchrule | Sort-Object matchrule
    $didcount = 0
    $tfncount = 0
    $didlist = @()
    $tfnlist = @()

    Foreach ($num in $numlist) {
        $curDID = $num.matchrule
        If ($curDID -match "sip:1833") {
            $tfncount = $tfncount + 1
            $tfnlist += $curDID.substring(5, 10)
        }
        elseIf ($curDID -match "sip:1844") {
            $tfncount = $tfncount + 1
            $tfnlist += $curDID.substring(5, 10)
        }
        elseIf ($curDID -match "sip:1855") {
            $tfncount = $tfncount + 1
            $tfnlist += $curDID.substring(5, 10)
        }
        elseIf ($curDID -match "sip:1866") {
            $tfncount = $tfncount + 1
            $tfnlist += $curDID.substring(5, 10)
        }
        elseIf ($curDID -match "sip:1877") {
            $tfncount = $tfncount + 1
            $tfnlist += $curDID.substring(5, 10)
        }
        elseIf ($curDID -match "sip:1888") {
            $tfncount = $tfncount + 1
            $tfnlist += $curDID.substring(5, 10)
        }
        elseIf ($curDID -match "sip:1800") {
            $tfncount = $tfncount + 1
            $tfnlist += $curDID.substring(5, 10)
        }
        elseIf ($curDID -match "sip:5555") { }
        elseif ($curDID -match "sip:Conf") { }
        else {
            $didcount = $didcount + 1
            $didlist += $curDID.substring(5, 10)
        }
    }

    $didtotals = New-Object -TypeName psobject
    $didtotals | Add-Member -NotePropertyName "DID" -NotePropertyValue $didcount
    $didtotals | Add-Member -NotePropertyName "TFN" -NotePropertyValue $tfncount
    $didtotals | Add-Member -NotePropertyName "DID List" -NotePropertyValue $didlist
    $didtotals | Add-Member -NotePropertyName "TFN List" -NotePropertyValue $tfnlist

    return $didtotals
}
Function Format-DID {
    ## Helper function to format DIDs into 10 digit format
    ## Scopes: N/A
    param (
        [Parameter(Mandatory = $true)][String]$did
    )
    # Remove special characters from DID
    $did = ($did.Trim()) -replace '[\s()-]', ''
    # Remove any preceeding 1 from DID
    if (($did.Length -eq 11) -and ($did[0] -eq "1")) { $did = $did.Substring(1) }
    # Check if DID is now 10 digits
    if ($did.Length -ne 10) {
        Write-Host "Your entered DID $did is not 10 characters. Please try again."
        return
    }
    return $did
}

## User Functions
Function Get-Users {
    ## Read list of users from domain. Includes various optional filters
    ## Scopes: Office Manager, Reseller, Super User
    param (
        [Parameter(Mandatory = $true)][String]$domain,
        [Parameter(Mandatory = $false)][String]$login,       
        [Parameter(Mandatory = $false)][String]$user,     
        [Parameter(Mandatory = $false)][String]$first_name,    
        [Parameter(Mandatory = $false)][String]$last_name,    
        [Parameter(Mandatory = $false)][String]$email
    )
    Check-Domain $domain
    $payload = @{
        object = 'subscriber'
        action = 'read'
        domain = $domain
    }
    # Check for the presence of additional filters. Add to payload if used
    If ($login) { $payload.Add('login', $login) }
    If ($user) { $payload.Add('user', $user) }
    If ($first_name) { $payload.Add('first_name', $first_name) }
    If ($last_name) { $payload.Add('last_name', $last_name) }
    If ($email) { $payload.Add('email', $email) }
    $res = NS-Call $payload | Format-Table -Property User, dial_policy, Scope, First_name, Last_name, Email, Vmail_enabled, Vmail_notify, Vmail_transcribe


    If ($res) {
        return $res
    }
    else { 
        $res = "No data returned"
        return $res
    }    
}
Function Get-Contacts {
    ## Description of what function accomplishes
    ## Scopes: Basic User, Office Manager, Reseller, Super User
    param (
        [Parameter(Mandatory = $true)][String]$domain,
        [Parameter(Mandatory = $true)][String]$user
    )
    Check-Domain $domain
    $payload = @{
        object = 'contact'
        action = 'read'
        domain = $domain
        user   = $user
    }
    Try {
        $res = NS-Call $payload -type "POST"
        $newtblFormat = @{Expression = { $_.tags }; Label = "Favorites"; },
        @{Expression = { $_.first_name }; Label = "First Name"; },
        @{Expression = { $_.last_name }; Label = "Last Name"; },
        @{Expression = { $_.company }; Label = "Company"; },
        @{Expression = { $_.work_phone }; Label = "Work"; },
        @{Expression = { $_.work_phone }; Label = "Work"; },
        @{Expression = { $_.cell_phone }; Label = "Cell"; },
        @{Expression = { $_.email }; Label = "Email"; }
        return $res | Format-Table $newtblFormat
    }
    Catch {
        $res = "No data returned"
        return $res
    } 
}
Function Get-Transcription {
    ## Returns list and a total number of users with voicemail transcription enabled
    ## Scopes: Office Manager, Reseller, Super User
    param (
        [Parameter(Mandatory = $true)][String]$domain,
        [Parameter(Mandatory = $false)][String]$user
    )
    Check-Domain $domain

    $payload = @{
        object = 'subscriber'
        action = 'read'
        domain = $domain
    }
    if($user){$payload.Add('user', $user)}
    Try {
        $res = NS-Call $payload
        $res = $res | Select-Object -Property user, vmail_transcribe, vmail_notify, srv_code | Sort-Object user | Where-Object{$_.srv_code -eq ""} | Where-Object{$_.vmail_transcribe -ne ""}  | Where-Object{$_.vmail_transcribe -ne "no"}
        $obj = New-Object -TypeName psobject
        $obj | Add-Member -NotePropertyName "Users" -NotePropertyValue $res
        $obj | Add-Member -NotePropertyName "Total" -NotePropertyValue $res.users.count 
        return $obj
    }
    Catch {
        $res = "No data returned"
        return $res
    }
}

## Template Function
Function Template {
    ## Description of what function accomplishes
    ## Scopes: Basic User, Office Manager, Reseller, Super User
    param (
        [Parameter(Mandatory = $true)][String]$domain,
        [Parameter(Mandatory = $false)][String]$var1,
        [Parameter(Mandatory = $false)][String]$var2,
        [Parameter(Mandatory = $false)][String]$var3
    )
    Check-Domain $domain
    $payload = @{
        object = 'domain'
        action = 'read'
        domain = $domain
    }    
    Try {
        $res = NS-Call $payload
        return $res
    }
    Catch {
        $res = "No data returned"
        return $res
    }
}
