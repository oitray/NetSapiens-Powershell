function New-ResourceDynamicParameter
(
    [Parameter(Mandatory = $true)][string]$ParameterType
) {
    $ParameterName = "Resource"
    $RuntimeParameterDictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
    $AttributeCollection = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
    $ParameterAttribute = New-Object System.Management.Automation.ParameterAttribute
    $ParameterAttribute.Mandatory = $true
    $AttributeCollection.Add($ParameterAttribute)
    if (!$Script:APIDOC) { $Script:APIDOC = (get-content "$($MyInvocation.MyCommand.Module.ModuleBase)\api_doc_collection.json" -raw | ConvertFrom-Json).item }
    $Script:Queries = foreach ($Resource in $Script:APIDOC) {
        $options = $resource.item.Request.url
        foreach ($Option in $options) {
      
            [PSCustomObject]@{
                Name   = ($Option -split "=" -split '&')[1]
                Action = ($Option -split "=" -split '&')[3]
            }
        }
    }
    $ResourceList = foreach ($query in  $Queries | where-object { $_.Action -eq $ParameterType }  ) {
        $query.name
       
    }
    $ValidateSetAttribute = New-Object System.Management.Automation.ValidateSetAttribute($ResourceList)
    $AttributeCollection.Add($ValidateSetAttribute)
    $RuntimeParameter = New-Object System.Management.Automation.RuntimeDefinedParameter($ParameterName, [string], $AttributeCollection)
    $RuntimeParameterDictionary.Add($ParameterName, $RuntimeParameter)
    return $RuntimeParameterDictionary
}
<#
.SYNOPSIS
    Sets the API authentication information.
.DESCRIPTION
 Sets the API Authentication headers.
.EXAMPLE
    PS C:\> Connect-NSAPI -credentials $Creds -ClientId "Hello" -Secret "AlsoHello" -baseurl "Manage.oitvoip.com"
    Creates header information for Autotask API.
.INPUTS
    -ApiIntegrationcode: The API Integration code found in Autotask
    -Credentials : The API user credentials
.OUTPUTS
    none
.NOTES
    Function might be changed at release of new API.
#>
function Connect-NSAPI (
    [Parameter(Mandatory = $true)]$baseurl,
    [Parameter(Mandatory = $true)]$ClientID,
    [Parameter(Mandatory = $true)]$Secret,
    [Parameter(Mandatory = $false)]$Domain,
    [Parameter(Mandatory = $true)][PSCredential]$credentials
) {
    $Script:BaseURL = $baseurl
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($credentials.Password)
    $DecryptedPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($BSTR)
    $username = $credentials.UserName
    write-host "Connecting to the API" -ForegroundColor Green
    try {
        $tokenURL = "$baseurl/oauth2/token/?grant_type=password&client_id=$($ClientID)&client_secret=$($Secret)&username=$($Username)&password=$($DecryptedPassword)"
        $Token = Invoke-RestMethod $tokenURL
        if(!$Domain) { $script:NSDomain = $token.domain} else { $script:NSDomain = $Domain}
        $script:NSAPIHeaders = @{"Authorization" = "Bearer $($token.access_token)" }
        write-host "Successfully connected to $baseurl"  -ForegroundColor Green
        write-host "Retrieving API resources. This might take a moment" -ForegroundColor Green
        $Script:ReadParameters = New-ResourceDynamicParameter -ParameterType 'read'
        $Script:DeleteParameters = New-ResourceDynamicParameter -ParameterType 'delete'
        $Script:UpdateParameters = New-ResourceDynamicParameter -ParameterType 'update'
        $Script:CreateParameters = New-ResourceDynamicParameter -ParameterType 'create'
    }
    catch {
        write-host "Could not succesfully connect to API. $($_.Exception.Message)" -ForegroundColor red
    }

}
