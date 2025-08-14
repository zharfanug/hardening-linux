# Reset & Cleanup
reset keys
```bash
rm -f /etc/ssh/ssh_host_*
/usr/sbin/dpkg-reconfigure openssh-server 2>/dev/null
rm -f /etc/machine-id
rm -f /var/lib/dbus/machine-id
/usr/bin/systemd-machine-id-setup 2>/dev/null
rm -f /var/lib/systemd/random-seed
rm -f /etc/udev/rules.d/70-persistent-net.rules
```
cleanup debian family
```bash
# Clean apt caches
apt update -y
apt dist-upgrade -y
apt clean
apt autoclean
apt autoremove --purge -y

# Remove APT lists (optional, rebuilt on next update)
rm -rf /var/lib/apt/lists/*
```
clean up logs and history
```bash
# Clear logs
find /var/log -type f -exec truncate -s 0 {} \;

unset HISTFILE && \
rm -f /home/*/.bash_history && \
rm -f /root/.bash_history
```