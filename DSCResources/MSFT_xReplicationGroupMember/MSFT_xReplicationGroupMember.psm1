function Get-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Collections.Hashtable])]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$ReplicationGroup,

		[parameter(Mandatory = $true)]
		[System.String]
		$FolderName,

		[parameter(Mandatory = $true)]
		[System.String]
		$ContentPath
	)

	#Write-Verbose "Use this cmdlet to deliver information about command processing."

	#Write-Debug "Use this cmdlet to write debug information while troubleshooting."


	<#
	$returnValue = @{
		Ensure = [System.String]
		ReplicationGroup = [System.String]
		ReadOnly = [System.Boolean]
		Credential = [System.Management.Automation.PSCredential]
	}

	$returnValue
	#>
}


function Set-TargetResource
{
	[CmdletBinding()]
	param
	(
		[System.Management.Automation.PSCredential]
		$Credential,

		[ValidateSet("Present","Absent")]
		[System.String]
		$Ensure,

		[System.Boolean]
		$ReadOnly,

		[parameter(Mandatory = $true)]
		[System.String]
		$ReplicationGroup,

		[parameter(Mandatory = $true)]
		[System.String]
		$FolderName,

		[parameter(Mandatory = $true)]
		[System.String]
		$ContentPath
	)

	#Write-Verbose "Use this cmdlet to deliver information about command processing."

	#Write-Debug "Use this cmdlet to write debug information while troubleshooting."

	#Include this line if the resource requires a system reboot.
	#$global:DSCMachineStatus = 1


}


function Test-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Boolean])]
	param
	(
		[System.Management.Automation.PSCredential]
		$Credential,

		[ValidateSet("Present","Absent")]
		[System.String]
		$Ensure,

		[System.Boolean]
		$ReadOnly,

		[parameter(Mandatory = $true)]
		[System.String]
		$ReplicationGroup,

		[parameter(Mandatory = $true)]
		[System.String]
		$FolderName,

		[parameter(Mandatory = $true)]
		[System.String]
		$ContentPath
	)

	#Write-Verbose "Use this cmdlet to deliver information about command processing."

	#Write-Debug "Use this cmdlet to write debug information while troubleshooting."

    if ( -not ( Get-Module -ListAvailable -Name DFSR ) )
    {
        throw "Please ensure that the DFSR Powershell module is installed"
    }

    $params = @{
                    ScriptBlock = { Get-DfsrMembership -GroupName $ReplicationGroup -ComputerName $env:COMPUTERNAME }
               }

    if ( $PSBoundParameters.ContainsKey("Credential") )
    {
        $params.Add("Credential",$Credential)
    }

    $MemberShip = Start-Job @params | Wait-Job | Receive-Job -AutoRemoveJob -ErrorVariable err 2>$null

    if ( -not $MemberShip)
    {
        Write-Verbose "Get-DfsrMembership did not return any objects for group $ReplicationGroup and Computer $($env:COMPUTERNAME)"
        return $false
    }

    try
    {
        if ( -not (Validate-Membership ))
        {

        }
    }
    catch
    {}

    return $true
	<#
	$result = [System.Boolean]
	
	$result
	#>
}

Function Validate-Membership
{
 	[CmdletBinding()]
	[OutputType([System.Boolean])]
    param
    (
		[System.Boolean]
		$ReadOnly,

		[parameter(Mandatory = $true)]
		[System.String]
		$ReplicationGroup,

		[parameter(Mandatory = $true)]
		[System.String]
		$FolderName,

		[parameter(Mandatory = $true)]
		[System.String]
		$ContentPath,
        
        [parameter(Mandatory = $true)]
        [Microsoft.DistributedFileSystemReplication.DfsrMembership[]]
        $Memberships
    )

    $validated = $false

    foreach ( $Membership in $Memberships)
    {
        if ( $MemberShip -isnot [Microsoft.DistributedFileSystemReplication.DfsrMembership] )
        {
            continue
        }

        if ( ($Membership.FolderName -eq $PSBoundParameters["FolderName"]) -and
             ($Membership.GroupName -eq $PSBoundParameters["ReplicationGroup"]) -and
             ($Membership.ContentPath -eq $PSBoundParameters["ContentPath"]) -and
             ($Membership.ReadOnly -eq $PSBoundParameters["ReadOnly"]))
        {
            $validated = $true
            break
        }
    }

    return $validated

}


Export-ModuleMember -Function *-TargetResource

