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
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    sssd-ad sssd-tools realmd adcli samba-common-bin \
    oddjob oddjob-mkhomedir packagekit \
    libnss-sss libpam-sss \
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