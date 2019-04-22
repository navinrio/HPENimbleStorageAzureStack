function Connect-AZNSVolume
{   <#
    .SYNOPSIS
        The Command will create and attach a new Nimble Volume to the current host.
    
    .DESCRIPTION
        The command will retrieve the credentials and IP Address from the Registry for the Nimble Storage Array, and connect to that array. The command with then 
        create a volume on the array to match the passed parameters, and assign access to that volume to the initiator group name that matches the current hostname. 
        Once the mapping has occured, the command will continue to detect newly detected iSCSI volumes until a volume appears that matches the Target ID of the 
        Volume created. Once the iSCSI volume has been detected, it will be connected to persistently, and then refresh the Microsoft VDS (Virtual Disk Service) 
        until that device because available as a WinDisk. The New Windisk that matches the serial number of the Nimble Storage Volume will then be initialized, 
        placed online, a partition created, and then finally formatted. The return opject of this command is the Windows Volume that has been created. 
    
        Additional parameters and more grainular control are available when using the non-Azurestack versions of the commands, i.e. You can set more features using 
        the New-NSVolume Command however, the steps required to automate the attachment or discovery of these volumes is not as automated.
    
    .PARAMETER name
        This mandatory parameter is the name that will be used by both the Nimble Array to define the volume name, but also as the name to use for the 
        Windows Formatted partition. 
    
    .PARAMETER size
        This mandatory parameter is the size in MegaBytes (MB) of the volume to be created. i.e. to create a 100 GigaByte (GB) volume, select 10240 as the size value.
    
    .PARAMETER description
        This commonly a single sentance to descript the contents of this volume. This is stored on the array and can help a storage administrator determine the usage
        of a specific volume. If no value is set, and autogenerated value with be used.
    .EXAMPLE
        PS C:\Users\TestUser> Connect-AZNSVolume -size 10240 -name Test10
        Successfully connected to array 10.1.240.20
    
        DriveLetter FileSystemLabel FileSystem DriveType HealthStatus OperationalStatus SizeRemaining    Size
        ----------- --------------- ---------- --------- ------------ ----------------- -------------    ----
        R           Test10          NTFS       Fixed     Healthy      OK                      9.93 GB 9.97 GB
    
    .NOTES
        This module command assumes that you have installed it via the Unattended installation script for connecting AzureStack to a Nimble Storage Infrastructure. 
        All functions use the Verb-Nouns contruct, but the Noun is always preceeded by AZNS which stands for AzureStack Nimble Storage. This prevents collisions in 
        customer enviornments Additional information about the function or script.
    .LINK
        Please see the GitHUB repository for updated versions of this command. Always use the UnattendedNimbleInstall to install the command as to make the command
        visible you must also alter the HPENimbleStorage PowerShell Toolkit manifest to include this file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $True)]
        [string] $name,
        [Parameter(Mandatory = $True)]
        [Nullable[long]] $size,
        [string] $description= "Autogenerated LUN for AzureStack"
        ) 
    process
    {   write-progress -activity "Connect Nimble Storage Volume" -status "retrieving stored credentials" -PercentComplete 0
        # First lets make sure we are connected to the controller
        $MyLocalIQN=(Get-InitiatorPort | where-object {$_.ConnectionType -like "iSCSI"} ).nodeaddress
        $MyNimUsername=(Get-ItemProperty -Path HKCU:\Software\NimbleStorage\Credentials\DefaultCred).UserName
        $MyNimPassword=(Get-ItemProperty -Path HKCU:\Software\NimbleStorage\Credentials\DefaultCred).Password
        $MyNimIPAddress=(Get-ItemProperty -Path HKCU:\Software\NimbleStorage\Credentials\DefaultCred).IPAddress
        $NimblePasswordObect = ConvertTo-SecureString $MyNimPassword -AsPlainText -force
        $NimbleCredObject = new-object -typename System.Management.Automation.PSCredential -argumentlist $MyNimUsername, $NimblePasswordObect
        start-sleep -seconds 1
        write-progress -activity "Connect Nimble Storage Volume" -status "Connecting to Nimble Storage Target" -PercentComplete 10
        $OutputSuppress = Connect-NSGroup -Group $MyNimIPAddress -Credential $NimbleCredObject -IgnoreServerCertificate
        start-sleep -seconds 1
        write-progress -activity "Connect Nimble Storage Volume" -status "Creating and mapping Nimble Volume" -PercentComplete 20
        $OutputSuppress = New-NSVolume -name $name -description $description -size $size
        $NewVolID = (get-nsvolume -name $name).id
        $MyIgroupID = (Get-NSInitiatorGroup -name (hostname)).id
        $OutputSuppress= New-NSAccessControlRecord -initiator_group_id $MyIgroupID -vol_id $NewVolID | format-table vol_name,initiator_group_name
        $NNum=(Get-nSVolume -name $name).serial_number
        $AM=(Get-nSVolume -name $name).target_name
        start-sleep -seconds 1
        write-progress -activity "Connect Nimble Storage Volume" -status "Detecting Nimble Storage Volume Serial and Target IQN" -PercentComplete 30
        $count=40
        while ( -not (Get-iscsiTarget | where-object {$_.nodeaddress -eq $AM}) ) 
            {   write-progress -activity "Connect Nimble Storage Volume" -status "Refreshing and Detecting hosts new iSCSI Targets" -PercentComplete $count
                Update-IscsiTarget
                $count=$count+3
                start-sleep -seconds 2
            }
        $count=65
        $OutputSuppress = Get-iscsiTarget | where-object {$_.nodeaddress -eq $AM} | connect-iscsitarget -IsPersistent $true
        while ( -not (get-disk -serialnumber $NNum -ErrorAction SilentlyContinue) )
            {   write-progress -activity "Connect Nimble Storage Volume" -status "Discovering Nimble Volume in Windows Volume Disk Service" -PercentComplete $count
                $count=$count+3
                $verbose = "rescan" | diskpart
                start-sleep -Seconds 2
            }
        Stop-Service -Name ShellHWDetection
        start-sleep -seconds 1
        write-progress -activity "Connect Nimble Storage Volume" -status "Initializing the Nimble Volume, Online the Nimble Volume" -PercentComplete 90
        $OutputSuppress=get-disk -serialnumber $NNum | Initialize-Disk -passthru | set-disk -IsOffline $false
        start-sleep -seconds 1
        write-progress -activity "Connect Nimble Storage Volume" -status "Creating Windows Partition and Formatting Nimble Volume" -PercentComplete 95
        $OutputSuppress=get-disk -serialnumber $NNum | New-Partition -UseMaximumSize -assigndriveletter 
        $OutputSuppress=get-disk -serialnumber $NNum | get-partition | where{$_.driveletter} | Format-Volume -NewFileSystemLabel $name
        start-service -Name ShellHWDetection
        start-sleep -seconds 1
        write-progress -activity "Connect Nimble Storage Volume" -status "Complete" -PercentComplete 100
        start-sleep -seconds 1
        return (get-disk -serialnumber $NNum | get-partition | where{$_.driveletter} | get-volume)
    }
}

