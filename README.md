# **Hands-on Vagrant - Linux and Windows Server Integration on Apple Silicon and Intel Macs**

This comprehensive guide will help you create and manage virtual machines (VMs) using **Vagrant** on **Apple Silicon (M1/M2)** and **Intel Macs**. You'll learn how to configure **Linux and Windows Server environments**, integrate Linux VMs into a **Windows Active Directory (AD) domain**, maintain **network connectivity**, and configure **static IPs** to ensure stability and consistent communication between VMs.

By the end of this guide, you will:

1. Understand what Vagrant is and why you should use it.
2. Install and configure Vagrant and necessary providers on your machine.
3. Set up and manage virtual environments for both Linux and Windows.
4. Configure and integrate Linux VMs with Windows AD.
5. Maintain stable network connectivity using static IP addresses.
6. Troubleshoot common issues.

---

## **1. What is Vagrant?**

**Vagrant** is an open-source tool for building and managing virtualised development environments. It allows you to automate the setup of virtual machines, ensuring that your development environment is consistent across different machines and platforms.

### **Why Use Vagrant?**

- **Automation**: It simplifies the creation of virtual machines by automating the setup process.
- **Consistency**: Ensures that the same environment is recreated every time, preventing "it works on my machine" issues.
- **Portability**: Vagrant can create and manage virtual machines with multiple providers, such as VMware Fusion, VirtualBox, and UTM.

---

## **2. Installing Vagrant and Providers**

Before creating virtual machines, you need to install Vagrant and a **provider**—the software that Vagrant uses to create and manage VMs. The choice of provider depends on whether you’re using an **Apple Silicon** Mac or an **Intel Mac**.

### **A. Installing Vagrant**

### **Steps to Install Vagrant on macOS:**

1. **Install Homebrew** (a package manager for macOS) if you don’t already have it:
    
    ```bash
    /bin/bash -c "$(curl -fsSL <https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh>)"
    
    ```
    
2. **Install Vagrant**:
    
    ```bash
    brew install vagrant
    
    ```
    
3. **Verify the installation**:
    
    ```bash
    vagrant --version
    
    ```
    
    You should see the version of Vagrant installed, confirming that it’s ready to use.
    

---

### **B. Choosing a Provider**

A **provider** is the tool Vagrant uses to create and manage your virtual machines. The choice of provider depends on whether you are using an **Apple Silicon** or **Intel** Mac.

### **1. For Apple Silicon (M1/M2 Macs): Use VMware Fusion or UTM**

- **VMware Fusion** is widely used on Apple Silicon but does not fully support **Windows Server**.
- **UTM** is recommended for emulating **Windows Server** on Apple Silicon because it can handle x86 emulation on ARM-based systems.

### **Installing VMware Fusion (for Apple Silicon)**:

1. **Install VMware Fusion** via Homebrew:
    
    ```bash
    brew install vmware-fusion
    
    ```
    
2. **Install the Vagrant plugin** for VMware Fusion:
    
    ```bash
    vagrant plugin install vagrant-vmware-desktop
    
    ```
    
    You’re now ready to use **VMware Fusion** with Vagrant on Apple Silicon.
    

### **Using UTM for Windows Server on Apple Silicon**:

**UTM** is an open-source virtual machine manager for Apple Silicon that emulates x86 environments like **Windows Server**. To set up and configure **Windows Server** on UTM, follow [this guide](https://tcsfiles.blob.core.windows.net/documents/AIST3720Notes/WindowsServeronanM1Mac.html).

---

### **2. For Intel Macs: Use VMware Fusion or VirtualBox**

- Intel-based Macs support both **VMware Fusion** and **VirtualBox**, and both work well with Vagrant.

### **Installing VirtualBox (for Intel Macs)**:

1. **Install VirtualBox**:
    
    ```bash
    brew install --cask virtualbox
    
    ```
    
2. **Verify the installation**:
    
    ```bash
    vboxmanage --version
    
    ```
    
    This will confirm that VirtualBox is installed and ready to use with Vagrant.
    

---

## **3. Creating Virtual Machines (VMs) with Vagrant**

With **Vagrant** and a provider installed, you can now create and manage virtual machines. We’ll set up both **Linux and Windows Server VMs**, configure network settings, and ensure that they work together seamlessly.

### **A. Writing Your First Vagrantfile**

The **Vagrantfile** is the configuration file that tells Vagrant how to set up your virtual machines. Below is an example **Vagrantfile** that creates three **Ubuntu VMs** and networks them together. These VMs will have static IP addresses, allowing them to communicate with each other and the Windows Server domain.

```ruby
# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  config.vm.box_check_update = true

  # Use username/password instead of SSH key
  config.ssh.insert_key = false
  config.ssh.username = "vagrant"
  config.ssh.password = "vagrant"

  # Define Ubuntu clients
  (1..3).each do |i|
    config.vm.define "ubuntu#{i}", autostart: true do |node|
      node.vm.box = "bento/ubuntu-22.04"
      node.vm.hostname = "ubuntu#{i}"
      node.vm.network "public_network", ip: "192.168.0.#{10+i}"  # Static IP for each VM
      node.vm.provider "vmware_fusion" do |v|
        v.vmx["memsize"] = "1024"
        v.vmx["numvcpus"] = "1"
        v.gui = true
      end

      # Provision the VM (we’ll add the provisioning script later)
      node.vm.provision "shell", path: "provision_ubuntu.sh"
    end
  end
end

```

### **Explanation of Key Parts**:

- **Vagrant.configure("2")**: This defines the Vagrant configuration language version.
- **config.vm.define**: Defines the virtual machines, here named `ubuntu1`, `ubuntu2`, and `ubuntu3`.
- **Static IPs**: Each VM is given a static IP (e.g., `192.168.0.11`, `192.168.0.12`, etc.) to ensure stable connectivity, which is essential for services like **Active Directory**.
- **VM Provider**: The provider is specified as **VMware Fusion** in this example, but you can use **VirtualBox** if running on an Intel Mac.

### **B. Running the VMs**

To create and start your VMs based on the configuration in your **Vagrantfile**, run the following command:

```bash
vagrant up

```

Once the VMs are running, you can access them using SSH:

```bash
vagrant ssh ubuntu1

```

This will log you into the first Ubuntu VM.

---

## **4. Automating Configuration with Provisioning**

To make the process of setting up the VMs faster and easier, we can automate configuration using a **provisioning script**. This script will:

- Update the system.
- Install necessary packages for joining an **Active Directory** domain.
- Configure **DNS** to point to the **Windows Server** domain controller.

### **Provisioning Script (provision_ubuntu.sh)**

Here’s the provisioning script that will configure your Ubuntu VMs to join the AD domain.

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
sudo apt-get install -y sssd-ad sssd-tools realmd adcli samba-common-bin \\
    oddjob oddjob-mkhomedir packagekit libnss-sss libpam-sss krb5-user

# Install open-vm-tools for better VMware integration
log_message "Installing open-vm-tools"
sudo apt-get install -y open-vm-tools

# Configure timezone
log_message "Setting timezone to UTC"
sudo timedatectl set-timezone UTC

# Ensure system time is synced
log_message "Installing and configuring chrony for time synchronization"
sudo apt-get install -y chrony
sudo systemctl enable chrony
sudo systemctl start chrony

# Configure

 DNS to use domain controller (example IP)
log_message "Configuring DNS to use domain controller"
sudo sed -i 's/^#DNS=/DNS=192.168.0.52/' /etc/systemd/resolved.conf
sudo systemctl restart systemd-resolved

# Add domain controller to /etc/hosts
log_message "Adding domain controller to /etc/hosts"
echo "192.168.0.52 dc.nextlevel.local dc" | sudo tee -a /etc/hosts

# Discover and join the domain
log_message "Discovering and joining the domain"
realm discover nextlevel.local
realm join -v -U Administrator nextlevel.local

# Restart services
log_message "Restarting services"
sudo systemctl restart sssd

```

### **Key Features of the Script**:

- **System Update**: Ensures the VM is fully up-to-date.
- **Package Installation**: Installs the tools needed to join an **Active Directory domain** (e.g., **realmd**, **SSSD**).
- **DNS Configuration**: Sets the DNS to use the **Windows Server** domain controller’s static IP (`192.168.0.52`).
- **Domain Joining**: Automates the process of joining the Ubuntu VM to the **AD domain**.

### **Running the Provisioning Script**

Once you’ve set up the provisioning script, Vagrant will automatically run it when you start the VMs:

```bash
vagrant up

```

If you modify the script and need to re-run it on existing VMs, you can use:

```bash
vagrant provision

```

---

## **5. Creating Windows Server VMs for Active Directory**

Next, we’ll create a **Windows Server VM** to act as the **Domain Controller (DC)** for **Active Directory**. This server will manage domain authentication for the Linux VMs.

### **A. Vagrantfile for Windows Server on Intel Mac**

Here’s the **Vagrantfile** for provisioning a **Windows Server** VM with a static IP for **AD** and **DNS**.

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

### **Key Points**:

- **Static IP**: The Windows Server is assigned a static IP (`192.168.0.52`) to ensure that other VMs can reliably connect to it for domain services.
- **Memory and CPU**: The VM is allocated **8048MB of RAM** and **2 CPUs** to ensure smooth operation as a domain controller.

### **B. Active Directory Setup Script (setup_ad.ps1)**

This **PowerShell script** configures the Windows Server as an **Active Directory Domain Controller** and adds **dummy users** for testing.

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

### **Key Features**:

- **Active Directory Setup**: Configures the Windows Server as a **Domain Controller** for Active Directory.
- **User Creation**: Adds dummy users to the domain for testing purposes.

### **Running the Windows Server VM**

To start the **Windows Server VM**, run:

```bash
vagrant up dc

```

The provisioning script will automatically configure **Active Directory** and create the dummy users.

---

## **6. Network Connectivity and Troubleshooting**

### **A. Importance of Static IPs**

To maintain stable communication between the VMs, it is critical to assign **static IP addresses** to each machine, especially the **Windows Server** acting as a **Domain Controller**. Static IPs ensure that:

- Linux VMs can reliably connect to the **Windows Server** for **DNS resolution** and **Active Directory authentication**.
- Network services remain stable without interruptions caused by IP address changes.

### **B. Configuring the Public Network**

For VMs to communicate with each other and external networks, they must be configured to use the **public network**. This is achieved in the **Vagrantfile** with:

```ruby
config.vm.network "public_network", ip: "192.168.0.XX"

```

### **C. Common Issues and Troubleshooting Tips**

1. **DNS Issues**: Ensure that the Ubuntu VMs are configured to use the Windows Server’s static IP as the **DNS server**.
2. **Network Connectivity**: Check firewall settings on both **Windows Server** and **Linux VMs** to ensure that essential ports (e.g., **LDAP**, **DNS**, **SMB**) are open and traffic is allowed.
3. **Domain Joining Issues**: If the Linux VMs cannot join the domain, check the **realm discover** command output for any configuration errors related to DNS or network settings.

---

## **7. Closing remarks**

By following this guide, you now have the knowledge to:

1. Install **Vagrant** and set up virtual machine providers.
2. Create and manage **Linux** and **Windows Server** VMs.
3. Configure **static IP addresses** and ensure network stability.
4. Set up **Active Directory** and join Linux clients to a Windows Server domain.
5. Troubleshoot common networking and domain integration issues.

### **Key Takeaways**:

- **Vagrant** provides a simple and automated way to manage development environments.
- Proper **network configuration** (static IPs, DNS) is critical to maintaining connectivity between VMs.
- Ensuring firewall and security configurations are correct will prevent many networking issues, especially when joining Linux machines to **Active Directory**.

Now you’re ready to tackle more advanced configurations and workflows using Vagrant, whether it’s integrating more complex services, setting up continuous integration pipelines, or managing large-scale environments!
