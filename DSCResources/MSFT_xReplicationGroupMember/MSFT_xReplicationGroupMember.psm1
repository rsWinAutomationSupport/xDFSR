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
		$ContentPath,

        [System.String[]]
        $ReplicationPeers,

	[System.Management.Automation.Runspaces.AuthenticationMechanism]
	$AuthenticationMechanism = [System.Management.Automation.Runspaces.AuthenticationMechanism]::Credssp
	)

    if ( -not ( Get-Module -ListAvailable -Name DFSR ) )
    {
        throw "Please ensure that the DFSR Powershell module is installed"
    }

    # TODO: Make this more elegant, i.e. save existing state of CredSSP and restore once done
    If($AuthenticationMechanism -eq [System.Management.Automation.Runspaces.AuthenticationMechanism]::Credssp){
	    Enable-WSManCredSSP -DelegateComputer "$($env:COMPUTERNAME).*" -Role Client -Force | Out-Null
	    Enable-WSManCredSSP -Role Server -Force | Out-Null
    }

    $params = @{
                    ScriptBlock = [scriptblock]::Create("Get-DfsrMembership -GroupName $ReplicationGroup -ComputerName $env:COMPUTERNAME")
               }

    if ( $PSBoundParameters.ContainsKey("Credential") )
    {
        $params.Add("Credential",$PSBoundParameters["Credential"])
    }

    $AllMemberShips = Invoke-Command -ComputerName . -Authentication $AuthenticationMechanism @params #Start-Job @params | Wait-Job | Receive-Job -Wait -AutoRemoveJob -ErrorVariable err 2>$null
    $MemberShip = $AllMemberShips | Where-Object { $_.FolderName -eq $PSBoundParameters["FolderName"] } 


    if ( -not $MemberShip)
    {
        Write-Verbose "Get-TargetResource: Get-DfsrMembership did not return any objects for group $($PSBoundParameters["ReplicationGroup"]), folder name `"$($PSBoundParameters["FolderName"])`" and Computer $($env:COMPUTERNAME)"
    }

    $retObject = @{}

    if ($MemberShip)
    {
        $paramsIncoming = @{
                        ScriptBlock = [scriptblock]::Create("Get-DfsrConnection -GroupName $ReplicationGroup -DestinationComputerName $env:COMPUTERNAME")
        }
        if ( $PSBoundParameters.ContainsKey("Credential") )
        {
            $paramsIncoming.Add("Credential",$PSBoundParameters["Credential"])
        }
        $paramsOutgoing = @{
                        ScriptBlock = [scriptblock]::Create("Get-DfsrConnection -GroupName $ReplicationGroup -SourceComputerName $env:COMPUTERNAME")
        }
        if ( $PSBoundParameters.ContainsKey("Credential") )
        {
            $paramsOutgoing.Add("Credential",$PSBoundParameters["Credential"])
        }

        $IncomingConnections = Invoke-Command -ComputerName . -Authentication $AuthenticationMechanism @paramsIncoming #Start-Job @paramsIncoming | Wait-Job | Receive-Job -Wait -AutoRemoveJob -ErrorVariable err 2>$null
        $OutgoingConnections = Invoke-Command -ComputerName . -Authentication $AuthenticationMechanism @paramsOutgoing #Start-Job @paramsOutgoing | Wait-Job | Receive-Job -Wait -AutoRemoveJob -ErrorVariable err 2>$null
        $SourceServerList = [String[]]($IncomingConnections.SourceComputerName)
        $DestinationServerList = [String[]]($OutgoingConnections.DestinationComputerName)

        $retObject = @{
            "Ensure"                          = "Present";
            "ReplicationGroup"                = $MemberShip.GroupName;
            "FolderName"                      = $MemberShip.FolderName;
            "ContentPath"                     = $MemberShip.ContentPath;
            "ReadOnly"                        = $MemberShip.ReadOnly;
            "IncomingConnectionsSources"      = $SourceServerList;
            "OutgoingConnectionsDestinations" = $DestinationServerList
        }
    }
    else
    {
        $retObject = @{
            "Ensure"            = "Absent"
        }
    }

    # TODO: Make this more elegant, i.e. save existing state of CredSSP and restore once done
    If($AuthenticationMechanism -eq [System.Management.Automation.Runspaces.AuthenticationMechanism]::Credssp){
	    Disable-WSManCredSSP -Role Client | Out-Null
	    Disable-WSManCredSSP -Role Server | Out-Null
    }

    $retObject

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
		$ContentPath,

        [System.String[]]
        $ReplicationPeers,

	[System.Management.Automation.Runspaces.AuthenticationMechanism]
	$AuthenticationMechanism = [System.Management.Automation.Runspaces.AuthenticationMechanism]::Credssp
	)
    $NeedsJoining = $false
    $CurrentResource = Get-TargetResource @PSBoundParameters

    # TODO: Make this more elegant, i.e. save existing state of CredSSP and restore once done
    If($AuthenticationMechanism -eq [System.Management.Automation.Runspaces.AuthenticationMechanism]::Credssp){
	    Enable-WSManCredSSP -DelegateComputer "$($env:COMPUTERNAME).*" -Role Client -Force | Out-Null
	    Enable-WSManCredSSP -Role Server -Force | Out-Null
    }

    Write-Verbose "Ensure: $($PSBoundParameters["Ensure"])"
    if ( $Ensure -eq "Present" )
    {
        Write-Verbose $CurrentResource
        if ( $CurrentResource["Ensure"] -ne "Present" )
        {
            Write-Verbose "Get-TargetResource returned Absent, need to Join machine to Replication Group"
            $NeedsJoining = $true
            $params = @{
                "ScriptBlock" = [scriptblock]::Create("Get-DfsReplicationGroup -GroupName $($PSBoundParameters["ReplicationGroup"])")
            }
            if ( $PSBoundParameters.ContainsKey("Credential") )
            {
                $params.Add("Credential",$PSBoundParameters["Credential"])
            }
            $ExistingReplicationGroup = Invoke-Command -ComputerName . -Authentication $AuthenticationMechanism @params #Start-Job @params | Wait-Job | Receive-Job -Wait -AutoRemoveJob
            if ( -not $ExistingReplicationGroup )
            {
                Write-Verbose "Replication Group specified ($($PSBoundParameters["ReplicationGroup"])) does not exist. Terminating."
                throw "Replication Group specified in Parameters MUST exist"
            }

            $params["ScriptBlock"] = [scriptblock]::Create("Get-DfsReplicatedFolder -GroupName $($PSBoundParameters["ReplicationGroup"]) -FolderName $($PSBoundParameters["FolderName"])")
            $ExistingReplicatedFolder = Invoke-Command -ComputerName . -Authentication $AuthenticationMechanism @params #Start-Job @params | Wait-Job | Receive-Job -Wait -AutoRemoveJob
            if ( -not $ExistingReplicatedFolder )
            {
                Write-Verbose "Replicated Folder specified ($($PSBoundParameters["FolderName"])) does not exist. Terminating."
                throw "FolderName specified in Parameters MUST exist"
            }

            #Adding Member to Replication Group
            $params.ScriptBlock = [scriptblock]::Create("Add-DfsrMember -GroupName $($PSBoundParameters["ReplicationGroup"]) -ComputerName $env:COMPUTERNAME -Description 'Adding as part of DevOps Automation Services'")
            Invoke-Command -ComputerName . -Authentication $AuthenticationMechanism @params | Out-Null #Start-Job @params | Wait-Job | Receive-Job -Wait -AutoRemoveJob | Out-Null
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
            Invoke-Command -ComputerName . -Authentication $AuthenticationMechanism @params | Out-Null #Start-Job @params | Wait-Job | Receive-Job -Wait -AutoRemoveJob | Out-Null
        }
        if ( $PSBoundParameters.ContainsKey("ReplicationPeers"))
        {
            $Command = ""
            foreach ($ReplicationPeer in $ReplicationPeers)
            {
                if ( $CurrentResource.IncomingConnectionsSources -notcontains $ReplicationPeer)
                {
                    Write-Verbose "Adding missing incoming Connection from $ReplicationPeer"
                    $Command += "`nAdd-DfsrConnection -GroupName $($PSBoundParameters["ReplicationGroup"]) -SourceComputerName $ReplicationPeer -DestinationComputerName $env:COMPUTERNAME -CreateOneWay"
                }
                if ( $ReadOnly -and $CurrentResource.OutgoingConnectionsDestinations -contains $ReplicationPeer)
                {
                    Write-Verbose "Adding missing outgoing Connection to $ReplicationPeer"
                    $Command += "`nAdd-DfsrConnection -GroupName $($PSBoundParameters["ReplicationGroup"]) -SourceComputerName $env:COMPUTERNAME -DestinationComputerName $ReplicationPeer -CreateOneWay"
                }
            }
            $params = @{
                "ScriptBlock" = [scriptblock]::Create($Command)
            }
            if ( $PSBoundParameters.ContainsKey("Credential") )
            {
                $params.Add("Credential",$PSBoundParameters["Credential"])
            }
            Invoke-Command -ComputerName . -Authentication $AuthenticationMechanism @params | Out-Null #Start-Job @params | Wait-Job | Receive-Job -Wait -AutoRemoveJob | Out-Null
        }
        if ( -not (Test-Path -Path $ContentPath))
        {
            New-Item -Path $ContentPath -ItemType Directory
        }
        #if ( $NeedsJoining )
        #{
        #    $SyncSource = $ReplicationPeers[(Get-Random -Maximum $ReplicationPeers.Count)]
        #    $params = @{
        #        "ScriptBlock" = [scriptblock]::Create("Sync-DfsReplicationGroup -GroupName $($PSBoundParameters["ReplicationGroup"]) -SourceComputerName $SyncSource -DestinationComputerName $($env:COMPUTERNAME) -DurationInMinutes 60")
        #    }
        #    if ( $PSBoundParameters.ContainsKey("Credential") )
        #    {
        #        $params.Add("Credential",$PSBoundParameters["Credential"])
        #    }
        #    Invoke-Command -ComputerName . -Authentication $AuthenticationMechanism @params | Out-Null #Start-Job @params | Wait-Job | Receive-Job -Wait -AutoRemoveJob | Out-Null
        #}
    }
    else
    {
        $params = @{
            "ScriptBlock" = [scriptblock]::Create("Remove-DfsrMember -GroupName $($PSBoundParameters["ReplicationGroup"]) -ComputerName $env:COMPUTERNAME -Force")
        }
        if ( $PSBoundParameters.ContainsKey("Credential") )
        {
            $params.Add("Credential",$PSBoundParameters["Credential"])
        }
        Invoke-Command -ComputerName . -Authentication $AuthenticationMechanism @params | Out-Null #Start-Job @params | Wait-Job | Receive-Job -Wait -AutoRemoveJob | Out-Null
    }

    # TODO: Make this more elegant, i.e. save existing state of CredSSP and restore once done
    If($AuthenticationMechanism -eq [System.Management.Automation.Runspaces.AuthenticationMechanism]::Credssp){
	    Disable-WSManCredSSP -Role Client | Out-Null
	    Disable-WSManCredSSP -Role Server | Out-Null
    }
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
		$Ensure = "Present",

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

        [System.String[]]
        $ReplicationPeers,

	[System.Management.Automation.Runspaces.AuthenticationMechanism]
	$AuthenticationMechanism = [System.Management.Automation.Runspaces.AuthenticationMechanism]::Credssp
	)

	#Write-Verbose "Use this cmdlet to deliver information about command processing."

	#Write-Debug "Use this cmdlet to write debug information while troubleshooting."

    
    Write-Verbose "Trying to determine Current state of DFSR resource"
    $CurrentResource = Get-TargetResource @PSBoundParameters

    if ( $Ensure -eq "Present" )
    {
        if ( $CurrentResource -eq "Absent" )
        {
            Write-Verbose "No resource matching the specified Parameters found"
            return $false
        }
        if ( $CurrentResource["ContentPath"] -ne $PSBoundParameters["ContentPath"] )
        {
            Write-Verbose "Desired ContentPath ($($PSBoundParameters["ContentPath"])) does not match ContentPath of existing resource ($($CurrentResource["ContentPath"]))"
            return $false
        }
        if ( $PSBoundParameters.ContainsKey("ReadOnly") -and $CurrentResource.ReadOnly -ne $PSBoundParameters["ReadOnly"] )
        {
            Write-Verbose "Desired Value of ReadOnly set to $($PSBoundParameters["ReadOnly"]) but existing resource found with ReadOnly set to $($CurrentResource.ReadOnly)"
            return $false
        }
        if ( $PSBoundParameters.ContainsKey("ReplicationPeers"))
        {
            foreach ($ReplicationPeer in $ReplicationPeers)
            {
                if ( $CurrentResource.IncomingConnectionsSources -notcontains $ReplicationPeer)
                {
                    Write-Verbose "Incoming Connection from $ReplicationPeer is missing"
                    return $false
                }
                if ( (-not $ReadOnly) -and  ($CurrentResource.OutgoingConnectionsDestinations -notcontains $ReplicationPeer) )
                {
                    Write-Verbose "Outgoing Connection to $ReplicationPeer is missing"
                    return $false
                }
            }
        }
        if ( -not (Test-Path -Path $ContentPath) )
        {
            Write-Verbose "Desired ContentPath ($ContentPath) does not exist"
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

Export-ModuleMember -Function *-TargetResource

