# NetSapiens Powershell

PowerShell wrapper for NetSapiens platform management. For use by resellers, subscribers and other users of our UCaaS network.

## Build status

Continually in development.

## Tech/framework used

<b>Built with</b>

- [PowerShell v5](https://docs.microsoft.com/en-us/powershell/scripting/overview?view=powershell-6)
- [NetSapiens](https://api.netsapiens.com)
- [OITVOIP](https://www.oitvoip.com)

## Features

Several commands for daily management of the platform. Most require the $domain parameter. Check comments for details

## Code Example

Get-CallRecording -domain "oitdemo.20463.service"

## Installation

Clone Git
Edit the config.json file. Enter your PBX portal, Client ID and Client Secret.

## How to use?

Run netsapiens.ps1 via PowerShell command line or ISE v3.0+
You will be prompted for your PBX user name and password.

## Support

Email - dev@oit.co

## Credits

Ray Orsini

[copyright OIT, LLC](https://www.oit.co)
