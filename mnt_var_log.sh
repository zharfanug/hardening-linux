#!/bin/sh

apt-get update -y
apt-get install -y rsync

# sudo systemctl stop systemd-journald.socket
# sudo systemctl stop systemd-journald-dev-log.socket
# sudo systemctl stop systemd-journald-audit.socket
# sudo systemctl stop systemd-journald.service

# sudo journalctl --flush
# sudo journalctl --rotate

sudo mkdir -p /var/mnt/log

sudo rsync -aXS /var/log/ /var/mnt/log/

if ! mountpoint -q /var/log; then
  sudo mv /var/log /var/log.bak
  sudo mkdir -p /var/log

  sudo mount --bind /var/mnt/log /var/log
  sudo mount -o remount,bind,nodev,nosuid,noexec /var/log
fi

FSTAB_LINE='/var/mnt/log /var/log none bind,nodev,nosuid,noexec 0 0'

grep -qxF "$FSTAB_LINE" /etc/fstab || \
  echo "$FSTAB_LINE" | sudo tee -a /etc/fstab >/dev/null
