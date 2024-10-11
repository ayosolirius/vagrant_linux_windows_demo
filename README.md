# **Hands-on Vagrant: Linux and Windows Server Integration on Apple Silicon**

This documentation provides a comprehensive guide to setting up and managing virtual machines (VMs) using **Vagrant** on Apple Silicon (M1/M2) and Intel Macs. It covers critical steps such as setting up Windows and Linux VMs, integrating Linux machines with Active Directory (AD), and managing networking across VMs. A particular focus is placed on ensuring stable **network connectivity** and configuring **static IP addresses** to prevent domain integration and cross-machine communication issues.

---

## **1. Vagrant on Apple Silicon: Challenges and Solutions**

Apple Silicon introduces some challenges when running specific virtualised environments like **Windows Server** due to the ARM64 architecture. To overcome these issues, choosing the right virtualisation platform is essential.

### **Using UTM for Windows Server on M1 Macs**

Since **Windows Server** does not natively run on Apple Silicon with tools like VMware Fusion or VirtualBox, the recommended solution is to use **UTM**, an open-source virtual machine manager for Apple Silicon. UTM offers emulation capabilities that allow Windows Server to run smoothly on M1/M2 processors.

### **Steps to Install and Configure UTM for Windows Server**

Follow this [guide]([https://tcsfiles.blob.core.windows.net/documents/AIST3720Notes/WindowsServeronanM1Mac.html#:~:text=Configure the VM&text=In UTM choose Create a,for the Windows Server installer .)](https://tcsfiles.blob.core.windows.net/documents/AIST3720Notes/WindowsServeronanM1Mac.html#:~:text=Configure%20the%20VM&text=In%20UTM%20choose%20Create%20a,for%20the%20Windows%20Server%20installer%20.)) to install **Windows Server** on a Mac with an M1 processor using UTM:

1. **Download UTM** from the [official website](https://mac.getutm.app/).
2. Create a new VM in UTM and select the **Windows Server ISO**.
3. Configure the VM with enough **RAM** and **CPU resources** for optimal performance.
4. Follow the instructions to install and configure **Windows Server** within UTM.

### **Why UTM?**

- **Windows Server** is not natively supported on M1 Macs via **VMware Fusion** or **VirtualBox**.
- UTM provides stable emulation for Windows environments but requires proper configuration to avoid issues during setup.

---

## **2. Setting Up Vagrant on M1 for Linux VMs**

For virtualizing Linux on Apple Silicon, **VMware Fusion** is the recommended provider for Vagrant. Below is a sample **Vagrantfile** and a provisioning script to set up and configure multiple **Ubuntu VMs** on M1 while maintaining reliable network connectivity.

### **Vagrantfile for Ubuntu VMs on M1**

```ruby
# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  config.vm.box_check_update = true

  # Use username/password instead of SSH key
  config.ssh.insert_key = false
  config.ssh.username = "vagrant"
  config.ssh.password = "vagrant"

  # Ubuntu clients
  (1..3).each do |i|
    config.vm.define "ubuntu#{i}", autostart: true do |node|
      node.vm.box = "bento/ubuntu-22.04"
      node.vm.hostname = "ubuntu#{i}"
      node.vm.network "public_network", ip: "192.168.0.#{10+i}" # Static IP for each VM
      node.vm.provider "vmware_fusion" do |v|
        v.vmx["memsize"] = "1024"
        v.vmx["numvcpus"] = "1"
        v.gui = true
      end

      # Provision the VM
      node.vm.provision "shell", path: "provision_ubuntu.sh"
    end
  end
end

```

### **Network Considerations:**

- **Public Network:** Each VM is assigned a **static IP** to ensure that it does not change, maintaining a stable connection between VMs and preventing issues with **Active Directory domain joining** or other network services.
- Ensuring VMs can **communicate with each other and external networks** is essential when configuring services like **AD**.

---

## **3. Provisioning Script for Ubuntu VMs (provision_ubuntu.sh)**

The provisioning script sets up each Ubuntu VM, installs required packages, and ensures it can join the **AD domain** while maintaining **network stability**.

```bash
#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_message "Starting provisioning script"

# Update package lists, upgrade packages, and clean up
log_message "Performing full system update"
sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get dist-upgrade -y
sudo apt-get autoremove -y
sudo apt-get autoclean

# Install necessary packages for AD domain join and Kerberos
log_message "Installing prerequisites for AD domain join and Kerberos"
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \\
    sssd-ad sssd-tools realmd adcli samba-common-bin \\
    oddjob oddjob-mkhomedir packagekit \\
    libnss-sss libpam-sss \\
    krb5-user

# Install open-vm-tools for better VMware integration
log_message "Installing open-vm-tools"
sudo apt-get install -y open-vm-tools

# Configure timezone
log_message "Setting timezone to UTC"
sudo timedatectl set-timezone UTC

# Ensure system time is synced
log_message "Installing and configuring chrony for time synchronization"
if ! dpkg -s chrony &> /dev/null; then
    sudo apt-get install -y chrony
fi
sudo systemctl enable chrony
sudo systemctl start chrony

# Set domain controller as DNS server
log_message "Configuring DNS to use domain controller"
if ! grep -q "^DNS=192.168.0.172" /etc/systemd/resolved.conf; then
    sudo sed -i 's/^#DNS=/DNS=192.168.0.172/' /etc/systemd/resolved.conf
    sudo systemctl restart systemd-resolved
fi

# Add domain controller to /etc/hosts
log_message "Adding domain controller to /etc/hosts"
if ! grep -q "192.168.0.172 dc.nextlevel.local dc" /etc/hosts; then
    echo "192.168.0.172 dc.nextlevel.local dc" | sudo tee -a /etc/hosts
fi

# Discover the domain
log_message "Discovering the domain"
realm discover nextlevel.local

# Join the domain if not already joined
if ! realm list | grep -q "nextlevel.local"; then
    log_message "Joining the domain"
    echo "vagrant" | sudo realm join -v -U vagrant nextlevel.local
else
    log_message "Already joined to the domain"
fi

# Configure SSSD
log_message "Configuring SSSD"
sudo tee /etc/sssd/sssd.conf > /dev/null <<EOT
[sssd]
domains = nextlevel.local
config_file_version = 2
services = nss, pam

[domain/nextlevel.local]
default_shell = /bin/bash
krb5_store_password_if_offline = True
cache_credentials = True
krb5_realm = NEXTLEVEL.LOCAL
realmd_tags = manages-system joined-with-adcli
id_provider = ad
fallback_homedir = /home/%u@%d
ad_domain = nextlevel.local
use_fully_qualified_names = True
ldap_id_mapping = True
access_provider = ad
EOT

# Set correct permissions for SSSD configuration
sudo chmod 600 /etc/sssd/sssd.conf

# Restart SSSD service
log_message "Restarting SSSD service"
sudo systemctl restart sssd

# Enable automatic home directory creation if not already enabled
log_message "Enabling automatic home directory creation"
if ! grep -q "pam_mkhomedir.so" /etc/pam.d/common-session; then
    sudo pam-auth-update --enable mkhomedir
fi

# Configure Kerberos
log_message "Configuring Kerberos"
sudo tee /etc/krb5.conf > /dev/null <<EOT
[libdefaults]
    default_realm = NEXTLEVEL.LOCAL
    dns_lookup_realm = true
    dns_lookup_kdc = true
    ticket_lifetime = 24h
    renew_lifetime = 7d
    forwardable = true

[realms]
    NEXTLEVEL.LOCAL = {
        kdc = dc.nextlevel.local
        admin_server = dc.nextlevel.local
    }

[domain_realm]
    .nextlevel.local = NEXTLEVEL.LOCAL
    nextlevel.local = NEXTLEVEL.LOCAL
EOT

log_message "Provisioning complete!"
log_message "You can now login with domain users using the format: user@nextlevel.local"

```

### **Key Network Considerations in Provisioning:**

- The DNS configuration is set to use the **domain controller (192.168.0.172)**, ensuring smooth integration with Active Directory.
- The **static IP address** of the **Windows Server** must remain unchanged to ensure continued connectivity and prevent domain access issues.

---

Apologies for the incomplete response. I'll continue from where I left off and finish the documentation.

---

## **4. Vagrantfile for Windows Server on Intel Macs**

For those using **Intel Macs**, you can run **Windows Server** via Vagrant using **VMware Fusion** or **VirtualBox** as the provider. Below is the Vagrantfile for provisioning a **Windows Server** for **Active Directory and DNS**.

```ruby
# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  config.vm.box_check_update = false

  # Windows Server for AD and DNS
  config.vm.define "dc", primary: true do |dc|
    dc.vm.box = "gusztavvargadr/windows-server"
    dc.vm.hostname = "dc"
    dc.vm.network "public_network", ip: "192.168.0.52"  # Static IP to prevent IP conflicts
    dc.vm.provider "vmware_fusion" do |v|
      v.vmx["memsize"] = "8048"
      v.vmx["numvcpus"] = "2"
      v.gui = true
    end
    dc.vm.provision "shell", path: "scripts/setup_ad.ps1"
  end
end

```

### **Importance of Static IP for Windows Server**

- **Windows Server** must be assigned a **static IP** (`192.168.0.52` in this example) to ensure stable connectivity, especially when acting as a **Domain Controller**.
- Without a static IP, **network services like DNS and AD** may fail to function properly, causing connection issues with other VMs in the environment.

---

## **5. Active Directory Setup Script for Windows Server (setup_ad.ps1)**

The following **PowerShell script** configures **Active Directory** on the Windows Server VM, promoting it to a **Domain Controller**.

```powershell
# Import the Active Directory module
Import-Module ActiveDirectory

# Define the base parameters
$domain = "nextlevel.local"
$usersPath = "CN=Users,DC=nextlevel,DC=local"
$passwordString = "P@ssw0rd123!"
$password = ConvertTo-SecureString $passwordString -AsPlainText -Force

# Function to create a user
function CreateUser($username, $firstname, $lastname) {
    $userPrincipalName = "$username@$domain"

    try {
        # Check if the user already exists
        if (Get-ADUser -Filter {SamAccountName -eq $username} -ErrorAction Stop) {
            Write-Host "User $username already exists. Skipping."
        } else {
            New-ADUser -SamAccountName $username `
                       -UserPrincipalName $userPrincipalName `
                       -Name "$firstname $lastname" `
                       -GivenName $firstname `
                       -Surname $lastname `
                       -Enabled $true `
                       -ChangePasswordAtLogon $false `
                       -Path $usersPath `
                       -AccountPassword $password `
                       -ErrorAction Stop

            Write-Host "User $username created successfully in the Users container."
        }
    } catch {
        Write-Host ("Error creating user {0}: {1}" -f $username, $_.Exception.Message)
    }
}

# Create dummy users
CreateUser "jsmith" "John" "Smith"
CreateUser "jdoe" "Jane" "Doe"
CreateUser "bbrown" "Bob" "Brown"
CreateUser "agreen" "Alice" "Green"
CreateUser "mwilson" "Mike" "Wilson"

Write-Host "Dummy user creation process completed."

```

### **Key Considerations:**

- This script configures **Active Directory** and creates **dummy users** for testing purposes.
- The **static IP** for the **Windows Server** allows VMs joining the domain to have a consistent point of reference for DNS and authentication services.

---

## **6. Importance of Network Connectivity on Hypervisors**

### **Static IP Addresses and Network Stability**

When managing VMs in a virtualized environment (whether on M1 or Intel Macs), maintaining **stable network connectivity** is vital. This is particularly crucial when integrating **Active Directory (AD)** and ensuring communication between VMs.

### **Key Points:**

- **Public Network**: Use the `public_network` setting in Vagrant to allow communication between VMs and external networks, such as when the Linux VMs need to access the Windows Server AD services.
- **Static IPs**: Assigning a **static IP address** to the Windows Server ensures that its network identity remains the same, preventing issues with domain services, DNS, and connectivity between VMs.
- **Network Troubleshooting**: Ensure proper firewall configurations on both Windows and Linux machines. Check DNS settings to confirm that the correct IP addresses are being used for domain lookups.

By ensuring proper **network setup** and configuring **static IPs**, you'll avoid common pitfalls in cross-VM communication and maintain a stable virtual environment.

---

## **7. Conclusion**

This documentation provides a comprehensive guide to setting up **Linux and Windows Server VMs** using Vagrant on both **Apple Silicon** and **Intel Macs**, with an emphasis on maintaining **network stability**. Key topics covered include:

- Using **UTM** to run **Windows Server** on Apple Silicon.
- Assigning **static IP addresses** to VMs to avoid issues with **Active Directory**.
- Ensuring that network settings are properly configured for communication between VMs.

### **Key Takeaways:**

- **VMware Fusion** is the recommended provider for Vagrant on **Apple Silicon**.
- **Static IP addresses** are crucial for maintaining **network connectivity**, especially when managing domain services and DNS.
- Properly configuring **network settings** ensures seamless communication between Linux and Windows VMs in a multi-OS environment.
