# hardening-linux

Update & Install Packages

```bash
apt update -y
apt dist-upgrade -y
apt install -y gnupg apt-transport-https net-tools traceroute git curl wget xfsprogs nftables fail2ban

curl -s https://raw.githubusercontent.com/zharfanug/zn-motd/latest/install.sh | sh
systemctl enable sysstat
systemctl start sysstat
```
For qemu hypervisor
```bash
apt install -y qemu-guest-agent
systemctl start qemu-guest-agent
```
For OpenVM
```bash
apt install -y open-vm-tools
```
Initialize Banner, SSH, Nftables, Fail2ban
```bash
mkdir -p ~/.backup/home
cp ~/.bashrc ~/.backup/home/
cp /etc/skel/.bashrc ~/.bashrc

cat <<EOF > /etc/legalnotice
------------------------------------------------------------
| This system is for authorized use only.                  |
|                                                          |
| By accessing this system, you acknowledge and consent    |
| to monitoring and recording by authorized personnel.     |
| Unauthorized access or use is prohibited and may result  |
| in disciplinary action, civil liability, or criminal     |
| prosecution.                                             |
------------------------------------------------------------
EOF

mkdir -p ~/.backup/etc/ssh/sshd_config.d/
cp /etc/ssh/sshd_config.d/* ~/.backup/etc/ssh/sshd_config.d/ 2>/dev/null || true
cat > "/etc/ssh/sshd_config.d/Banner.conf" <<- EOF
Banner /etc/legalnotice
EOF

mkdir -p ~/.backup/etc
cp /etc/issue ~/.backup/etc/
rm /etc/issue
ln -s /etc/legalnotice /etc/issue

# ssh -Q cipher
cat <<EOF > "/etc/ssh/sshd_config.d/Ciphers.conf"
Ciphers aes128-gcm@openssh.com,aes256-gcm@openssh.com,chacha20-poly1305@openssh.com
EOF
# ssh -Q kex
cat <<EOF > "/etc/ssh/sshd_config.d/KexAlgorithms.conf"
KexAlgorithms curve25519-sha256,sntrup761x25519-sha512,sntrup761x25519-sha512@openssh.com,ecdh-sha2-nistp256
EOF
# ssh -Q key
cat <<EOF > "/etc/ssh/sshd_config.d/KeyTypes.conf"
PubkeyAcceptedKeyTypes ssh-ed25519,ssh-ed25519-cert-v01@openssh.com,sk-ssh-ed25519@openssh.com,sk-ssh-ed25519-cert-v01@openssh.com
EOF
# ssh -Q mac
cat <<EOF > "/etc/ssh/sshd_config.d/MACs.conf"
MACs hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com,hmac-sha2-512-etm@openssh.com
EOF

cat <<EOF > "/etc/ssh/sshd_config.d/Port.conf"
Port 10022
EOF

echo 'export TMOUT=1200' > /etc/profile.d/tmout.sh
chmod 644 /etc/profile.d/tmout.sh

cat <<EOF > /etc/nftables.conf
#!/usr/sbin/nft -f
# nft-base v1.3.0
# THIS FILE IS MANAGED BY ADMINISTRATOR
# DO NOT DIRECTLY EDIT THIS FILE AS IT WILL BE REPLACED UPON UPDATE!
# EDIT /etc/nftables.d/custom-input.nft INSTEAD.

# Flush the current ruleset
table inet base-nft
flush table inet base-nft

include "/etc/nftables.d/custom-define.nft"

include "/etc/nftables.d/std-define.nft"

table inet base-nft {
  include "/etc/nftables.d/custom-sets.nft"

  chain custom_input {
    include "/etc/nftables.d/custom-input.nft"

  }

  include "/etc/nftables.d/std-sets.nft"

  chain standard_input {
    include "/etc/nftables.d/std-input.nft"

  }

  # Inbound traffic policy
  chain input {
    # Drop all incoming traffic by default
    type filter hook input priority 0; policy drop;
    # Allow incoming traffic related to established connections
    ct state invalid drop
    ct state {established, related} accept

    jump custom_input

    jump standard_input

  }
}
EOF

mkdir -p /etc/nftables.d/
touch /etc/nftables.d/custom-define.nft
touch /etc/nftables.d/custom-sets.nft 
cat > /etc/nftables.d/custom-input.nft <<- EOF
# sample
# ip saddr @net_locals tcp dport 22 accept
EOF

cat <<EOF > /etc/nftables.d/std-define.nft
# std-define v1.2.1

define rfc1918_24 = 10.0.0.0/8
define rfc1918_20 = 172.16.0.0/12
define rfc1918_16 = 192.168.0.0/16

define rfc6598 = 100.64.0.0/10
EOF

cat <<'EOF' > /etc/nftables.d/std-input.nft
# std-input v1.2.3

# Block attacker ip from fail2ban
ip saddr @f2b-sshd drop

# Allow SSH traffic from local
ip saddr @net_locals tcp dport 10022 accept

# Allow DHCP client traffic from local
ip saddr @net_locals udp dport 68 accept

# Allow incoming icmp/ping
ip protocol icmp icmp type { echo-request } accept

# Allow localhost to access local
iifname "lo" accept
EOF

cat <<'EOF' > /etc/nftables.d/std-sets.nft
# std-sets v1.2.1

set net_locals {
  type ipv4_addr; flags interval;
  elements = { $rfc1918_24 , $rfc1918_20 , $rfc1918_16 , $rfc6598 }
}
set f2b-sshd {
  type ipv4_addr
  flags timeout
}
EOF

systemctl enable nftables
systemctl start nftables
systemctl restart nftables

echo "" > /etc/motd
rm /etc/update-motd.d/* 2>/dev/null || true 

cat <<'EOF' > /etc/fail2ban/jail.d/ssh-nft.conf
#ssh-nft-f2b v1.0.1
[DEFAULT]
# Ban for 1 hour, escalate exponentially up to 7 days with randomization
bantime = 1h
bantime.increment = true
bantime.factor = 2
bantime.rndtime = 30m
bantime.maxtime = 7d
# Monitoring window & thresholds
findtime = 10m
maxretry = 5

# Do not ban localhost or trusted IPs
ignoreip = 127.0.0.1/8 ::1/128

# Use systemd journal & nftables for banning
backend = systemd
banaction = nftables-multiport
banaction_allports = nftables-allports

# Email notifications (optional)
# destemail = alerts@your-domain.com
# sender = fail2ban@your-domain.com
# action = %(action_mwl)s

[sshd]
enabled = true
port = 10022
logpath = %(sshd_log)s
mode = normal
EOF

mkdir -p /etc/systemd/system/fail2ban.service.d/
cat <<EOF > /etc/systemd/system/fail2ban.service.d/nft.conf
# /etc/systemd/system/fail2ban.service.d/nft.conf
[Unit]
Requires=nftables.service
After=nftables.service
EOF

systemctl restart ssh

systemctl daemon-reload
systemctl enable fail2ban
systemctl start fail2ban
systemctl restart fail2ban
```
Update hosts via networking service
```bash
cat <<'EOF' > /usr/local/bin/update-hosts
#!/bin/sh

HOSTS_FILE="/etc/hosts"

# Gather values
MAIN_IP=
count=0
while [ -z "$MAIN_IP" ] && [ "$count" -lt 60 ]; do
  MAIN_IP=$(ip route get 1.1.1.1 2>/dev/null | awk 'NR==1 {print $7}')
  [ -z "$MAIN_IP" ] && sleep 1
  count=$((count + 1))
done

if [ -z "$MAIN_IP" ]; then
  echo "Failed after 60 attempts" >&2
  exit 1
fi

HOSTNAME=$(awk '{print $1}' /etc/hostname)
DOMAIN=$(awk '/^domain/ {print $2}' /etc/resolv.conf)
FQDN="$HOSTNAME"
if [ -n "$DOMAIN" ]; then
  FQDN="${HOSTNAME}.${DOMAIN}"
fi

# Find the line number of 127.0.0.1\tlocalhost
LOCALHOST_LINE=$(grep -n '^127\.0\.0\.1[[:space:]]\+localhost' "$HOSTS_FILE" | cut -d: -f1)

# Only proceed if the line was found
if [ -n "$LOCALHOST_LINE" ]; then
  TARGET_LINE=$(expr "$LOCALHOST_LINE" + 1)

  # Use awk to replace the line
  awk -v line="$TARGET_LINE" -v ip="$MAIN_IP" -v fqdn="$FQDN" -v hn="$HOSTNAME" '
    NR == line { print ip "\t" fqdn "\t" hn; next }
    { print }
  ' "$HOSTS_FILE" > "${HOSTS_FILE}.tmp" && mv "${HOSTS_FILE}.tmp" "$HOSTS_FILE"
else
  echo "127.0.0.1 localhost not found in $HOSTS_FILE" >&2
  exit 1
fi
EOF
mkdir -p /etc/systemd/system/networking.service.d
cat <<EOF > /etc/systemd/system/networking.service.d/override.conf
[Service]
ExecStartPost=/bin/sh -c 'sleep 5 && /usr/local/bin/update-hosts &'
EOF
chmod +x /usr/local/bin/update-hosts
systemctl daemon-reload
systemctl restart networking
```
