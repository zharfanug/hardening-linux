#!/bin/sh

apt-get update -y
apt-get install -y rsync auditd audispd-plugins

sudo mkdir -p /var/mnt/log/audit
sudo mkdir -p /var/log/audit

sudo rsync -aXS /var/log/audit/ /var/mnt/log/audit/

if ! mountpoint -q /var/log/audit; then
  sudo mv /var/log/audit /var/log/audit.bak
  sudo mkdir -p /var/log/audit

  sudo mount --bind /var/mnt/log/audit /var/log/audit
  sudo mount -o remount,bind,nodev,nosuid,noexec /var/log/audit
fi

FSTAB_LINE='/var/mnt/log/audit /var/log/audit none bind,nodev,nosuid,noexec 0 0'

grep -qxF "$FSTAB_LINE" /etc/fstab || \
  echo "$FSTAB_LINE" | sudo tee -a /etc/fstab >/dev/null

cat <<EOF > /etc/audit/rules.d/local.rules
# Identity management
-a always,exit -F arch=b64 -F path=/etc/passwd -F perm=wa -F key=identity
-a always,exit -F arch=b64 -F path=/etc/group -F perm=wa -F key=identity
-a always,exit -F arch=b64 -F path=/etc/shadow -F perm=wa -F key=identity

# Sudo configuration
-a always,exit -F arch=b64 -F path=/etc/sudoers -F perm=wa -F key=sudoers
-a always,exit -F arch=b64 -F dir=/etc/sudoers.d -F perm=wa -F key=sudoers

# SSH configuration
-a always,exit -F arch=b64 -F path=/etc/ssh/sshd_config -F perm=wa -F key=ssh

# Privileged commands
-a always,exit -F arch=b64 -F path=/usr/bin/sudo -F perm=x -F key=privileged
-a always,exit -F arch=b64 -F path=/usr/bin/su -F perm=x -F key=privileged

# Package management
-a always,exit -F arch=b64 -F path=/usr/bin/apt -F perm=x -F key=software
-a always,exit -F arch=b64 -F path=/usr/bin/dpkg -F perm=x -F key=software

# Systemd configuration
-a always,exit -F arch=b64 -F dir=/etc/systemd -F perm=wa -F key=systemd
EOF