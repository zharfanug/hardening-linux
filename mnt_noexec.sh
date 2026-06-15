#!/bin/sh

apt-get update -y
apt-get install -y rsync

if [ -z "$BASE_PATH" ] || [ -z "$BIND_PATH" ]; then
  echo "BASE_PATH or BIND_PATH not set" >&2
  exit 1
fi

sudo mkdir -p "$BASE_PATH"

sudo rsync -aXS "$BIND_PATH"/ "$BASE_PATH"/

if ! mountpoint -q "$BIND_PATH"; then
  sudo mv "$BIND_PATH" "$BIND_PATH.bak"
  sudo mkdir -p "$BIND_PATH"

  sudo mount --bind "$BASE_PATH" "$BIND_PATH"
  sudo mount -o remount,bind,nodev,nosuid,noexec "$BIND_PATH"
fi

FSTAB_LINE="$BASE_PATH $BIND_PATH none bind,nodev,nosuid,noexec 0 0"

grep -qxF "$FSTAB_LINE" /etc/fstab || echo "$FSTAB_LINE" | sudo tee -a /etc/fstab >/dev/null