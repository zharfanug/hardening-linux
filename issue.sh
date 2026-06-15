#!/bin/sh

set -eu

timestamp() {
  date +"%Y%m%d_%H%M%S"
}

make_backup() {
  SOURCE_FILE="$1"
  BACKUP_DIR=$(dirname "$SOURCE_FILE")

  latest_backup=""

  base_name=$(basename "$SOURCE_FILE")
  escaped_base_name=$(printf '%s\n' "$base_name" | sed 's/[.]/\\&/g')
  pattern="^${escaped_base_name}_backup_[0-9]\\{8\\}_[0-9]\\{6\\}$"

  for file in "${SOURCE_FILE}"_backup_*; do
    [ -f "$file" ] || continue
    base=$(basename "$file")
    echo "$base" | grep -q "$pattern" || continue
    latest_backup="$file"
  done

  backup_file="${SOURCE_FILE}_backup_$(timestamp)"
  # No valid backup found
  if [ -z "$latest_backup" ]; then
    # echo "No existing backup found"
    cp -p "$SOURCE_FILE" "$backup_file"
    echo "Created backup: $backup_file"
  else
    echo "Latest backup: $latest_backup"
    # Compare current file with latest backup
    if cmp -s "$SOURCE_FILE" "$latest_backup"; then
      echo "Current ${SOURCE_FILE} is identical to latest backup"
    else
      echo "Current ${SOURCE_FILE} differs from latest backup"
      cp -p "$SOURCE_FILE" "$backup_file"
      echo "Created backup: $backup_file"
    fi
  fi
}

make_backup /etc/issue.net
  
cat <<EOF > /etc/issue.net
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

chown root:root /etc/issue.net
chmod 644 /etc/issue.net

make_backup /etc/issue

rm /etc/issue
  
cat <<EOF > /etc/issue
\n on \l at \d \t
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

chown root:root /etc/issue
chmod 644 /etc/issue

cat >/usr/local/bin/stat <<'EOF'
#!/bin/sh

REAL_STAT=/usr/bin/stat

if [ "$1" = "-L" ]; then
  case "$2" in
    *%n*)
      shift 2
      exec "$REAL_STAT" -L -c "%N" "$@"
      ;;
  esac
fi

exec "$REAL_STAT" "$@"
EOF

chmod +x /usr/local/bin/stat
