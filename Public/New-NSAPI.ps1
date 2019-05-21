
function New-NSAPI {
    [CmdletBinding()]
    Param(
        [Parameter(ParameterSetName = 'Parameters', Mandatory = $true)]
        [String]$Parameters
    )
    DynamicParam {
        $Script:CreateParameters
    }
    begin {
        if (!$script:NSAPIHeaders) {
            Write-Warning "You must first run Connect-NSAPI before calling any other cmdlets" 
            break 
        }

     }
        process {
            if($PSBoundParameters.OptionalParameters){$payload = $payload + $OptionalParameters }

            $payload = @{
                object = $PSBoundParameters.resource
                action = 'update'
                domain = $script:NSdomain
                format = 'json'
            }
            try {
                Invoke-RestMethod $script:baseurl -Headers $script:NSAPIHeaders -Body $payload -Method POST
            }
            catch {
                $streamReader = [System.IO.StreamReader]::new($_.Exception.Response.GetResponseStream())
                $streamReader.BaseStream.Position = 0
                if ($streamReader.ReadToEnd() -like '*{*') { $ErrResp = $streamReader.ReadToEnd() | ConvertFrom-Json }
                $streamReader.Close()
                if ($ErrResp.errors) { 
                    write-error "API Error: $($ErrResp.errors)" 
                }
                else {
                    write-error "Connecting to the NSAPI failed. $($_.Exception.Message)"
                }
            }

        }
    }

