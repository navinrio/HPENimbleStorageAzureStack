# Volume.ps1: This is an autogenerated file. Part of Nimble Group Management SDK. All edits to this file will be lost!
#
# © Copyright 2017 Hewlett Packard Enterprise Development LP.
function Connect-AZNSVolume
{   [CmdletBinding()]
    param(
        [Parameter(Mandatory = $True)]
        [string] $name,
        [Parameter(Mandatory = $True)]
        [Nullable[long]] $size,
        [string] $description
        ) 
    process
    {   # First lets make sure we are connected to the controller
        $MyLocalIQN=(Get-InitiatorPort | where-object {$_.ConnectionType -like "iSCSI"} ).nodeaddress
        $MyNimUsername=(Get-ItemProperty -Path HKCU:\Software\NimbleStorage\Credentials\DefaultCred).UserName
        $MyNimPassword=(Get-ItemProperty -Path HKCU:\Software\NimbleStorage\Credentials\DefaultCred).Password
        $MyNimIPAddress=(Get-ItemProperty -Path HKCU:\Software\NimbleStorage\Credentials\DefaultCred).IPAddress
        $NimblePasswordObect = ConvertTo-SecureString $MyNimPassword -AsPlainText -force
        $NimbleCredObject = new-object -typename System.Management.Automation.PSCredential -argumentlist $MyNimUsername, $NimblePasswordObect
        Connect-NSGroup -Group $MyNimIPAddress -Credential $NimbleCredObject -IgnoreServerCertificate
        if ( -not $description )
        {   $description = "Autogenerated LUN for AzureStack"
        }
        New-NSVolume -name $name -description $description -size $size
        # Once created, lets retrieve the ID and then map it to the current host
        $NewVolID = (get-nsvolume -name $name).id
        $MyIgroupID = (Get-NSInitiatorGroup -name (hostname)).id
        New-NSAccessControlRecord -initiator_group_id $MyIgroupID -vol_id $NewVolID
        # Now that it is mapped, lets connect the target via iscsi
        Update-IscsiTarget
        get-iscsitarget | where-object {$_.isconnected -ne "True"} | connect-iscsitarget
        # Lets find the disk and format this
        $NNum=(Get-nSVolume -name $name).serial_number
        write-host "The Detected Volume Serial number is $NNum"
        "rescan" | diskpart
        get-disk -serialnumber $NNum | Initialize-Disk -passthru | set-disk -IsOffline $false | New-Partition -UseMaximumSize -assigndriveletter | Format-Volume -filesystem NTFS -NewFileSystemLabel $name -confirm $false
    }
}
