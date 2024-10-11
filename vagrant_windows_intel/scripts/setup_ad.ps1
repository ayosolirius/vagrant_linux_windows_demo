# Install Active Directory Domain Services
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools

# Import the ADDSDeployment module
Import-Module ADDSDeployment

# Set up variables
$DomainName = "nextlevel.local"
$NetbiosName = "NEXTLEVEL"
$SafeModeAdministratorPassword = ConvertTo-SecureString "V@gr@ntSup£rP@ssw0rd1" -AsPlainText -Force

# Install a new forest, create a domain, and promote to a domain controller
Install-ADDSForest `
    -CreateDnsDelegation:$false `
    -DatabasePath "C:\Windows\NTDS" `
    -DomainMode "WinThreshold" `
    -DomainName $DomainName `
    -DomainNetbiosName $NetbiosName `
    -ForestMode "WinThreshold" `
    -InstallDns:$true `
    -LogPath "C:\Windows\NTDS" `
    -NoRebootOnCompletion:$false `
    -SysvolPath "C:\Windows\SYSVOL" `
    -SafeModeAdministratorPassword $SafeModeAdministratorPassword `
    -Force:$true

# The server will restart automatically after the promotion is complete