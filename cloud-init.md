# Cloud Init
Deb-family Install Cloud Init
```bash
apt update -y
apt install -y cloud-init xmlstarlet
```
prep config
```bash
touch /etc/cloud/cloud-init.disabled
cat <<'EOF' > /etc/cloud/cloud.cfg.d/99-custom-ovf.cfg
#cloud-config

# Explicitly define datasource_list to include OVF for VMware vApp options.
datasource_list: [ OVF, NoCloud, VMware, Ec2, OpenStack, CloudStack, AltCloud, GCE, Azure, Oracle, Exoscale, None ]

# Write a script to retrieve OVF properties and configure the OS
write_files:
  - path: /usr/local/bin/configure_vm_from_ovf.sh
    permissions: '0755'
    owner: root:root
    content: |
      #!/bin/bash
      set -euo pipefail # Exit immediately if a command exits with a non-zero status. Exit if an unset variable is used. Pipefail.

      LOG_FILE="/var/log/ovf_customization.log"
      # Redirect all output to the log file and stdout for visibility
      exec > >(tee -a "$LOG_FILE") 2>&1
      echo "--- $(date) --- Starting OVF Customization Script ---"
      OVF_ENV_XML=$(vmtoolsd --cmd "info-get guestinfo.ovfEnv")
      
      obfuscate_password() {
        local password="$1"
        local prefix=2
        local suffix=2
        local min_total=$((prefix + suffix + 1)) # +1 to require middle to exist
        local len=${#password}

        if (( len < min_total )); then
          echo '***'
        else
          local visible_start="${password:0:prefix}"
          local visible_end="${password: -suffix}"
          echo "${visible_start}***${visible_end}"
        fi
      }

      get_env() {
        local key="$1"
        VALUE=$(echo "$OVF_ENV_XML" | xmlstarlet sel -N oe="http://schemas.dmtf.org/ovf/environment/1" -t -v "//oe:Property[@oe:key='${key}']/@oe:value")
        echo "$VALUE" # Return the value
      }
      
      # Retrieve values from OVF properties
      # These variable names (vm_hostname, vm_username, etc.) MUST match the Key IDs you set in vCenter vApp Options.
      VM_HOSTNAME=$(get_env "vm_hostname")
      VM_DOMAIN=$(get_env "vm_domain")
      VM_USERNAME=$(get_env "vm_username")
      VM_PASSWORD=$(get_env "vm_password")
      VM_SSH_KEY=$(get_env "vm_ssh_key")
      if [[ -n "$VM_DOMAIN" ]]; then
        VM_DOMAIN="pss.net"
      fi
      echo "hostname: $VM_HOSTNAME"
      echo "domain: $VM_DOMAIN"
      echo "username: $VM_USERNAME"
      echo "password: $(obfuscate_password $VM_PASSWORD)"
      echo "vm_ssh_key: $VM_SSH_KEY"

      echo "Configuring OS properties based on OVF inputs..."

      # 1. Set Hostname
      if [[ -n "$VM_HOSTNAME" ]]; then
          echo "Setting hostname to: $VM_HOSTNAME"
          hostnamectl set-hostname "$VM_HOSTNAME"
          echo "$VM_HOSTNAME" > /etc/hostname # Update /etc/hostname
          /usr/bin/hostname $VM_HOSTNAME
          # Update /etc/hosts to reflect the new hostname for local resolution
          sed -i "/^127\.0\.1\.1/s/.*/127.0.1.1\t${VM_HOSTNAME}.${VM_DOMAIN}\t${VM_HOSTNAME}/" /etc/hosts 2>/dev/null
          echo "Hostname successfully set."
      else
          echo "Hostname (vm_hostname OVF property) not provided or empty. Skipping hostname configuration."
      fi

      # 2. Create User and Set Password
      if [[ -n "$VM_USERNAME" ]]; then
          echo "Processing user '$VM_USERNAME'..."
          if id "$VM_USERNAME" &>/dev/null; then
              echo "User '$VM_USERNAME' already exists. Updating password and SSH key."
          else
              echo "Creating new user '$VM_USERNAME'..."
              useradd -m -s /bin/bash "$VM_USERNAME" # Create user with home directory and bash shell
              usermod -aG sudo "$VM_USERNAME" # Add user to the sudo group for administrative privileges
              echo "User '$VM_USERNAME' created and added to sudoers."
          fi

          if [[ -n "$VM_PASSWORD" ]]; then
              # Hash the plaintext password provided via OVF using openssl (SHA-512 crypt method)
              # Then set the password using chpasswd
              echo "Setting password for user '$VM_USERNAME'..."
              HASHED_PASSWORD=$(openssl passwd -6 "$VM_PASSWORD")
              echo "${VM_USERNAME}:${HASHED_PASSWORD}" | chpasswd -e
              echo "Password successfully set for user: $VM_USERNAME"
          else
              echo "Password (vm_password OVF property) not provided for user '$VM_USERNAME'. User will be created without a password (or existing password will remain)."
          fi

          # 3. Add SSH Key
          if [[ -n "$VM_SSH_KEY" ]]; then
              echo "Adding SSH key for user '$VM_USERNAME'..."
              HOME_DIR=$(eval echo "~$VM_USERNAME") # Get the home directory of the user
              SSH_DIR="$HOME_DIR/.ssh"
              AUTHORIZED_KEYS_FILE="$SSH_DIR/authorized_keys"

              mkdir -p "$SSH_DIR" # Create .ssh directory if it doesn't exist
              echo "$VM_SSH_KEY" > "$AUTHORIZED_KEYS_FILE" # Write the SSH key
              chmod 600 "$AUTHORIZED_KEYS_FILE" # Set correct permissions for authorized_keys (read/write by owner only)
              chown -R "$VM_USERNAME":"$VM_USERNAME" "$SSH_DIR" # Set correct ownership for .ssh directory and its contents
              echo "SSH key successfully added for user: $VM_USERNAME"
              echo "PasswordAuthentication no" > /etc/ssh/sshd_config.d/PasswordAuthentication.conf
              echo "SSH Password authentication disabled."
          else
              echo "SSH key (vm_ssh_key OVF property) not provided for user '$VM_USERNAME'. Skipping SSH key addition."
          fi
      else
          echo "Username (vm_username OVF property) not provided. Skipping user creation and related configurations."
      fi
      
      ls -ld /var/lib/cloud/ || true
      mkdir -p /var/lib/cloud/data
      mkdir -p /var/lib/cloud/instance
      ls -ld /var/lib/cloud/data || true
      ls -ld /var/lib/cloud/instance || true

      # 4. Regenerate SSH Host Keys
      # This is crucial for security and preventing warnings when cloning/deploying VMs from a template.
      # It ensures each deployed VM has unique host keys.
      echo Regenerating keys...
      rm -f /etc/ssh/ssh_host_* # Remove existing host keys
      dpkg-reconfigure openssh-server 2>/dev/null # Command to regenerate new host keys on Debian
      rm -f /etc/machine-id
      rm -f /var/lib/dbus/machine-id
      rm -f /var/lib/systemd/random-seed
      rm -f /etc/udev/rules.d/70-persistent-net.rules
      /usr/bin/systemd-machine-id-setup 2>/dev/null
      rm -f /root/.bash_history
      rm -f /home/*/.bash_history

      echo "--- $(date) --- OVF Customization Script Finished ---"

# Execute the script on first boot
runcmd:
  - /usr/local/bin/configure_vm_from_ovf.sh
  - /usr/bin/touch /etc/cloud/cloud-init.disabled
  - rm -f /usr/local/bin/configure_vm_from_ovf.sh
EOF
```
enable cloud init
```bash
rm /etc/cloud/cloud-init.disabled
```