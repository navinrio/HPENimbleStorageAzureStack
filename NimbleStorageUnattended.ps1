function Set-NSASSecurityProtocolOverride
{   # Will override the behavior of Invoke-WebRequest to allow access without a Certificate. 
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    if (-not ([System.Management.Automation.PSTypeName]'ServerCertificateValidationCallback').Type)
    {   $certCallback = @"
            using System;
            using System.Net;
            using System.Net.Security;
            using System.Security.Cryptography.X509Certificates;
            public class ServerCertificateValidationCallback
            {   public static void Ignore()
                {   if(ServicePointManager.ServerCertificateValidationCallback ==null)
                    {   ServicePointManager.ServerCertificateValidationCallback += delegate (   Object obj, 
                                                                                                X509Certificate certificate, 
                                                                                              X509Chain chain, 
                                                                                             SslPolicyErrors errors
                                                                                           )
                        {   return true;
                        };
                    }
                }
            }
"@
        Add-Type $certCallback
    }
    [ServerCertificateValidationCallback]::Ignore()
}
function PostEvent([String]$TextField, [string]$EventType)
{   # Subroutine to Post Events to Log/Screen/EventLog
    $outfile = "C:\NimbleStorage\Logs\NimbleInstall.log" 
    if (! (test-path $outfile))
        {   mkdir c:\NimbleStorage -erroraction SilentlyContinue
            mkdir c:\NimbleStorage\Logs -erroraction SilentlyContinue
        }
    if (! (test-path HKLM:\SYSTEM\CurrentControlSet\Services\Eventlog\application\NimbleStorage) )
        {   New-Eventlog -LogName Application -source NimbleStorage
            PostEvent "Creating Eventlog\Application\NimbleStorage Eventlog Source" "Warning"
        } else
        {   switch -wildcard ($Eventtype)
                {   "Info*"     { $color="gray" }
                    "Warn*"     { $color="green" }
                    "Err*"      { $color="yellow" }
                    "Cri*"      { $color="red"
                                  $EventType="Error" }
                    default     { $color="gray" }
                }
            write-host "- "$textfield -foregroundcolor $color
            Write-Eventlog -LogName Application -Source NimbleStorage -EventID 1 -Message $TextField -EntryType $EventType -Computername "." -category 0
            $TextField | out-file -filepath $outfile -append
        }
} 
function Load-NSASAzureModules
{   # Loads all of the Nimble Storage Azure Stack specific PowerShell Modules
    if (-not (Get-Module -name AzureRM.Storage) )
    {   postevent "The required AzureStack Powershell are being Installed" "Info"
        Set-PSRepository -name "PSGallery" -InstallationPolicy Trusted
            postevent "Set-PSRepository -name PSGallery -InstallationPolicy Trusted" "Info"
        Import-Module -Name PowerShellGet
            postevent "Import-Module -Name PowerShellGet" "Info"
        Set-PSRepository -name "PSGallery" -InstallationPolicy TrustedImport-Module -Name PackageManagement  
            postevent "Set-PSRepository -name PSGallery -InstallationPolicy TrustedImport-Module -Name PackageManagement" "Info"
        Register-PsRepository -Default -ErrorAction SilentlyContinue
            postevent "Register-PsRepository -Default -ErrorAction SilentlyContinue" "Info"
        Install-Packageprovider -name NuGet -MinimumVersion 2.8.5.201
            postevent "Install-Packageprovider -name NuGet -MinimumVersion 2.8.5.201" "Info"
        register-psrepository -default -ErrorAction SilentlyContinue
            postevent "register-psrepository -default -ErrorAction SilentlyContinue" "Info"
        install-module AzureRM -RequiredVersion 2.4.0
            postevent "install-module AzureRM -RequiredVersion 2.4.0" "Info"
        Install-Module -name AzureStack -RequiredVersion 1.7.1
            postevent "Install-Module -name AzureStack -RequiredVersion 1.7.1" "Info"
        # Install the Azure.Storage module version 4.5.0
        Install-Module -Name Azure.Storage -RequiredVersion 4.5.0 -Force -AllowClobber
            postevent "Install-Module -Name Azure.Storage -RequiredVersion 4.5.0 -Force -AllowClobber" "Info"
        # Install the AzureRm.Storage module version 5.0.4
        Install-Module -Name AzureRM.Storage -RequiredVersion 5.0.4 -Force -AllowClobber
            postevent "Install-Module -Name AzureRM.Storage -RequiredVersion 5.0.4 -Force -AllowClobber" "Info"
        # Remove incompatible storage module installed by AzureRM.Storage
        Uninstall-Module Azure.Storage -RequiredVersion 4.6.1 -Force
            postevent "Uninstall-Module Azure.Storage -RequiredVersion 4.6.1 -Force" "Info"
        # Load the modules explicitly specifying the versions
        Import-Module -Name Azure.Storage -RequiredVersion 4.5.0
            postevent "Import-Module -Name Azure.Storage -RequiredVersion 4.5.0" "Info"
        Import-Module -Name AzureRM.Storage -RequiredVersion 5.0.4
            postevent "Import-Module -Name AzureRM.Storage -RequiredVersion 5.0.4" "Info"
    } else 
    {   postevent "The required AzureStack Powershell Modules have been detected" "Info"        
    }
}
function Load-NimblePSTKModules
{   # Loads the Nimble PowerShell Toolkit from the GitHub Site identifed in the Global Variables
    if ( Test-Path 'C:\Windows\System32\WindowsPowerShell\v1.0\Modules\HPENimblePowerShellToolkit' -PathType Container )
    {   PostEvent "The HPE NimbleStorage PowerShell Toolkit is installed" "Information"
    } else 
    {   PostEvent "Now Installing the Nimble PowerShell Toolkit" "Warning"
        invoke-webrequest -uri $NimblePSTKuri -outfile "C:\NimbleStorage\HPENimblePowerShellToolkit.210.zip"
        $PSMPath="C:\Windows\System32\WindowsPowerShell\v1.0\Modules"
        expand-archive -path "C:\NimbleStorage\HPENimblePowerShellToolkit.210.zip" -DestinationPath $WindowsPowerShellModulePath
    }

}
function Load-WindowsMPIOFeature
{   # Load the Windows MPIO feature. Returns True if a Reboot is required.
    if( (get-WindowsFeature -name "Multipath-io").installed )
    {   PostEvent "The Windows Multipath IO Feature is already Insatlled" "Information"
        if ( (get-windowsFeature -name "Multipath-io").InstallState -ne "Installed")
            {   PostEvent "Reboot is required after a Windows Multipath IO Feature Installation" "Warning"
                $ForceReboot=$True
                return $True
            } else 
            {   postevent "The Windows Multipath IO Feature does not require a reboot" "Information"
                return $false                
            }
    } else 
    {  # Step 1a Install MPIO if not installed
        add-WindowsFeature -name "Multipath-io"
        PostEvent "The Windows Multipath IO Feature is not installed, Installing Now!" "Warning"
        PostEvent "Reboot is required after a Windows Multipath IO Feature Installation" "Warning"
        $ForceReboot=$True
        return $true
    }
}
function Load-NWTPackage
{   # Download and instlal the Nimble Windows Toolkit. If already installed, return false, otherwise install and request a reboot.
    $NWTsoftware="Nimble Windows Toolkit"
    $installed = (Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Where { $_.DisplayName -eq $NWTsoftware }) -ne $null
    if ($installed)
    {   PostEvent "The Nimble Windows Toolkit is already installed" "Information"
        return $false
    } else
    {   # If NWT not installed, silent install it
        invoke-webrequest -uri $NWTuri -outfile "C:\NimbleStorage\Setup-NimbleNWT-x64.5.0.0.7991.exe"
        $NWTEXE = "C:\NimbleStorage\Setup-NimbleNWT-x64.5.0.0.7991.exe"
        $NWTArg1 = "EULAACCEPTED=Yes"
        $NWTArg2 = "HOTFIXPASS=Yes"
        $NWTArg3 = "RebootYesNo=Yes"
        $NWTArg4 = "NIMBLEVSSPORT=Yes"
        $NWTArg5 = "/silent"
        & $NWTEXE $NWTArg1 $NWTArg2 $NWTArg3 $NWTArg4 $NWTArg5
        # Invoke-Command -ScriptBlock "C:\NimbleStorage\Setup-NimbleNWTx64.0.0.0.XXX.exe EULAACCEPTED=Yes HOTFIXPASS=Yes RebootYesNo=Yes NIMBLEVSSPORT=Yes /silent"
        PostEvent "Initiating download and Silent Installation of the Nimble Windows Toolkit" "Warning"
        return $true
    }
}

#####################################################################################################################################################
# MAIN Unattended Installation Script for Nimble Storag on Azure Stack.                                                                             #
#####################################################################################################################################################
# Set the Global Variables needed for the script to operate
    # $InitialPulluri='https://raw.githubusercontent.com/chris-lionetti/HPENimbleStorageAzureStack/master/HPENimbleStorage.ps1'
    
    $NWTuri='https://github.com/chris-lionetti/HPENimbleStorageAzureStack/raw/master/Setup-NimbleNWT-x64.5.0.0.7991.exe'
    
    $NimblePSTKuri='https://github.com/chris-lionetti/HPENimbleStorageAzureStack/raw/master/HPENimblePowerShellToolkit.210.zip'
        
    $WindowsPowerShellModulePath="C:\Windows\System32\WindowsPowerShell\v1.0\Modules"
    
    $NimbleArrayIP="10.1.240.20"
    
    $NimbleUser="admin"
    
    $NimblePassword="admin"

# Step 1. Load the Azure Stack Specific PowerShell modules
    Load-NSASAzureModules 
# Step 2. All all Invoke-Web* commands to operate without a certificate. 
    Set-NSASSecurityProtocolOverride
# Step 3. Download and install the Nimble PowerShell Toolkit
    Load-NimblePSTKModules
# step 3b. TODO: Use secrets to discover array and log into array 

# Step 4. Ensure that iSCSI is started;
    Start-Service msiscsi
    Set-Service msiscsi -startuptype "automatic"
    PostEvent "Ensuring that the iSCSI Initiator Service is started, and setting it to start automatically" "Warning"
# Step 5. Detect if MPIO is installed. If it needs reboot, set the flag as the return
    $ForceReboot=Load-WindowsMPIOFeature
# Step 6. If NWT not downloaded, download it. If it is downloaded and installed require reboot, otherwise to do not set reboot flag
    if (-not $ForceReboot) 
        {   $ForceReboot=Load-NWTPackage
        }
# Step 7. If the ForceReboot flag is set, make this script run at the next reboot, otherise exit successfully/complete.
    if ($ForceReboot)
        {   $RunOnce="HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce"
            #set-itemproperty $RunOnce "NextRun" ('C:\Windows\System32\WindowsPowerShell\v1.0\Powershell.exe -executionPolicy Unrestricted -File ' + 'C:\NimbleStorage\NimbleStorageUnattended.ps1')
            PostEvent "This Installation Script is set to run again once the server has been rebooted. Please Reboot this server" "Error"
        } else 
        {   PostEvent "This Script has verified that all required software is installed, and that no reboot is needed" "Information"
            PostEvent "This script will NOT be re-run on reboot" "warning"        
        }
