function Get-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Collections.Hashtable])]
	param
	(
        [System.Management.Automation.PSCredential]
        $Credential,

		[ValidateSet("Present","Absent")]
		[System.String]
		$Ensure = "Present",

		[System.Boolean]
		$ReadOnly = $false,

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

    if ( -not ( Get-Module -ListAvailable -Name DFSR ) )
    {
        throw "Please ensure that the DFSR Powershell module is installed"
    }

    $params = @{
                    ScriptBlock = [scriptblock]::Create("Get-DfsrMembership -GroupName $ReplicationGroup -ComputerName $env:COMPUTERNAME")
               }

    if ( $PSBoundParameters.ContainsKey("Credential") )
    {
        $params.Add("Credential",$PSBoundParameters["Credential"])
    }

    $AllMemberShips = Start-Job @params | Wait-Job | Receive-Job -Wait -AutoRemoveJob -ErrorVariable err 2>$null
    $MemberShip = $AllMemberShips | Where-Object { $_.FolderName -eq $PSBoundParameters["FolderName"] } 


    if ( -not $MemberShip)
    {
        Write-Verbose "Get-TargetResource: Get-DfsrMembership did not return any objects for group $($PSBoundParameters["ReplicationGroup"]), folder name `"$($PSBoundParameters["FolderName"])`" and Computer $($env:COMPUTERNAME)"
    }

    #$ParamsToValidate = @{
    #    "Memberships"      = $MemberShip;
    #    "ReplicationGroup" = $PSBoundParameters["ReplicationGroup"];
    #    "FolderName"       = $PSBoundParameters["FolderName"];
    #    "ContentPath"      = $PSBoundParameters["ContentPath"];
    #    "ReadOnly"         = $PSBoundParameters["ReadOnly"]
    #}
    #
    #$Validated = Validate-Membership @ParamsToValidate

    $retObject = @{}

    if ($MemberShip)
    {
        $retObject = @{
            "Ensure"           = "Present";
            "ReplicationGroup" = $MemberShip.GroupName;
            "FolderName"       = $MemberShip.FolderName;
            "ContentPath"      = $MemberShip.ContentPath;
            "ReadOnly"         = $MemberShip.ReadOnly
        }
    }
    else
    {
        $retObject = @{
            "Ensure"            = "Absent"
        }
    }


    $retObject

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
		$Ensure = "Present",

		[System.Boolean]
		$ReadOnly = $false,

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

    $CurrentResource = Get-TargetResource @PSBoundParameters
    Write-Verbose "Ensure: $($PSBoundParameters["Ensure"])"
    if ( $Ensure -eq "Present" )
    {
        Write-Verbose $CurrentResource
        if ( $CurrentResource["Ensure"] -ne "Present" )
        {
            Write-Verbose "Get-TargetResource returned Absent, need to Join machine to Replication Group"
            $params = @{
                "ScriptBlock" = [scriptblock]::Create("Get-DfsReplicationGroup -GroupName $($PSBoundParameters["ReplicationGroup"])")
            }
            if ( $PSBoundParameters.ContainsKey("Credential") )
            {
                $params.Add("Credential",$PSBoundParameters["Credential"])
            }
            $ExistingReplicationGroup = Start-Job @params | Wait-Job | Receive-Job -Wait -AutoRemoveJob
            if ( -not $ExistingReplicationGroup )
            {
                Write-Verbose "Replication Group specified ($($PSBoundParameters["ReplicationGroup"])) does not exist. Terminating."
                throw "Replication Group specified in Parameters MUST exist"
            }

            $params["ScriptBlock"] = [scriptblock]::Create("Get-DfsReplicatedFolder -GroupName $($PSBoundParameters["ReplicationGroup"]) -FolderName $($PSBoundParameters["FolderName"])")
            $ExistingReplicatedFolder = Start-Job @params | Wait-Job | Receive-Job -Wait -AutoRemoveJob
            if ( -not $ExistingReplicatedFolder )
            {
                Write-Verbose "Replicated Folder specified ($($PSBoundParameters["FolderName"])) does not exist. Terminating."
                throw "FolderName specified in Parameters MUST exist"
            }

            #Adding Member to Replication Group
            $params.ScriptBlock = [scriptblock]::Create("Add-DfsrMember -GroupName $($PSBoundParameters["ReplicationGroup"]) -ComputerName $env:COMPUTERNAME -Description 'Adding as part of DevOps Automation Services'")
            Start-Job @params | Wait-Job | Receive-Job -Wait -AutoRemoveJob
        }
        Write-Verbose "$($PSBoundParameters["ContentPath"]) - $($CurrentResource["ContentPath"])"
        if ( $CurrentResource["ContentPath"] -ne $PSBoundParameters["ContentPath"] -or ( $PSBoundParameters.ContainsKey("ReadOnly") -and $CurrentResource["ReadOnly"] -ne $PSBoundParameters["ReadOnly"]) )
        {
            Write-Verbose "Fixing Content Path"
            $params = @{
                "ScriptBlock" = [scriptblock]::Create("Set-DfsrMembership -ComputerName $env:COMPUTERNAME -GroupName $($PSBoundParameters["ReplicationGroup"]) -FolderName $($PSBoundParameters["FolderName"]) -ContentPath $($PSBoundParameters["ContentPath"]) $( If ($PSBoundParameters.ContainsKey("ReadOnly")) {"-ReadOnly `$$($PSBoundParameters["ReadOnly"])"}) -Force")
            }
            if ( $PSBoundParameters.ContainsKey("Credential") )
            {
                $params.Add("Credential",$PSBoundParameters["Credential"])
            }
            $params
            Start-Job @params | Wait-Job | Receive-Job -Wait -AutoRemoveJob


        }
    }

    
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

    
    $CurrentResource = Get-TargetResource @PSBoundParameters

    if ( $PSBoundParameters["Ensure"] -eq "Present" )
    {
        if ( $CurrentResource -eq "Absent" )
        {
            return $false
        }
        if ( $CurrentResource["ContentPath"] -ne $PSBoundParameters["ContentPath"] )
        {
            return $false
        }
        if ( $PSBoundParameters.ContainsKey("ReadOnly") -and $CurrentResource.ReadOnly -ne $PSBoundParameters["ReadOnly"] )
        {
            return $false
        }
    }
    else
    {
        if ( $CurrentResource -eq "Present" )
        {
            return $false
        }
    }

    return $true
}
    #if ( -not ( Get-Module -ListAvailable -Name DFSR ) )
    #{
    #    throw "Please ensure that the DFSR Powershell module is installed"
    #}
    #
    #$params = @{
    #                ScriptBlock = [scriptblock]::Create("Get-DfsrMembership -GroupName $ReplicationGroup -ComputerName $env:COMPUTERNAME")
    #           }
    #
    #if ( $PSBoundParameters.ContainsKey("Credential") )
    #{
    #    $params.Add("Credential",$Credential)
    #}
    #
    #$MemberShip = Start-Job @params | Wait-Job | Receive-Job -Wait -AutoRemoveJob -ErrorVariable err 2>$null
    #
    #if ( -not $MemberShip)
    #{
    #    Write-Verbose "Get-DfsrMembership did not return any objects for group $ReplicationGroup and Computer $($env:COMPUTERNAME)"
    #    return $false
    #}
    #
    #try
    #{
    #    if ( -not (Validate-Membership -ReplicationGroup $PSBoundParameters["ReplicationGroup"] -FolderName $PSBoundParameters["FolderName"] -ContentPath $PSBoundParameters["ContentPath"] -Memberships $MemberShip -ReadOnly $PSBoundParameters["ReadOnly"]))
    #    {
    #        return $false
    #    }
    #}
    #catch
    #{}

    #return $true
	<#
	$result = [System.Boolean]
	
	$result
	#>
    #}

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
        $Memberships
    )


    foreach ( $Membership in $Memberships)
    {
        if ( ($Membership.FolderName -eq $PSBoundParameters["FolderName"]) -and
             ($Membership.GroupName -eq $PSBoundParameters["ReplicationGroup"]) -and
             ($Membership.ContentPath -eq $PSBoundParameters["ContentPath"]) -and
             ($Membership.ReadOnly -eq $PSBoundParameters["ReadOnly"]))
        {
            return $Membership
        }
    }

    return $null

}


Export-ModuleMember -Function *-TargetResource

