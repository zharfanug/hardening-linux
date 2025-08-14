#!/bin/bash

# Script to tar workspace excluding gitignore files and scp to target
# Usage: ./copy_repo.sh <target_host> [target_path] [tar_name]
# Example: ./copy_repo.sh user@192.168.1.100 /home/user/backups cakra-images-backup.tar.gz

set -e

# Configuration
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
WORKSPACE_DIR=$(dirname "$SCRIPT_DIR")
GITIGNORE_FILE="$WORKSPACE_DIR/.gitignore"
TEMP_DIR="/tmp"

# Check arguments
if [ $# -lt 1 ]; then
    echo "Usage: $0 <target_host> [target_path] [tar_name]"
    echo "Example: $0 user@192.168.1.100 /home/user/backups cakra-images-backup.tar.gz"
    exit 1
fi

TARGET_HOST="$1"
TARGET_PATH="${2:-/tmp}"
TAR_NAME="${3:-cakra-images-$(date +%Y%m%d_%H%M%S).tar.gz}"

# Ensure tar name ends with .tar.gz
if [[ ! "$TAR_NAME" =~ \.tar\.gz$ ]]; then
    TAR_NAME="${TAR_NAME}.tar.gz"
fi

LOCAL_TAR_PATH="$TEMP_DIR/$TAR_NAME"

echo "Starting backup process..."
echo "Workspace: $WORKSPACE_DIR"
echo "Target: $TARGET_HOST:$TARGET_PATH/$TAR_NAME"

# Change to workspace directory
cd "$WORKSPACE_DIR"

# Create exclude file from .gitignore
EXCLUDE_FILE="$TEMP_DIR/tar_exclude_$(date +%s)"
if [ -f "$GITIGNORE_FILE" ]; then
    echo "Processing .gitignore file..."
    # Convert .gitignore patterns to tar exclude patterns
    while IFS= read -r line; do
        # Skip empty lines and comments
        if [[ -n "$line" && ! "$line" =~ ^[[:space:]]*# ]]; then
            # Remove leading/trailing whitespace
            line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            
            # Handle different gitignore patterns
            if [[ "$line" =~ ^/ ]]; then
                # Absolute path from root
                echo "${line#/}" >> "$EXCLUDE_FILE"
            elif [[ "$line" =~ /$ ]]; then
                # Directory pattern
                echo "$line" >> "$EXCLUDE_FILE"
                echo "${line%/}" >> "$EXCLUDE_FILE"
            else
                # File or pattern
                echo "$line" >> "$EXCLUDE_FILE"
                echo "*/$line" >> "$EXCLUDE_FILE"
            fi
        fi
    done < "$GITIGNORE_FILE"
    
    # Add .git directory to exclude list
    echo ".git" >> "$EXCLUDE_FILE"
    echo ".git/*" >> "$EXCLUDE_FILE"
    
    echo "Exclude patterns prepared from .gitignore"
else
    echo "Warning: No .gitignore file found"
    # Just exclude .git
    echo ".git" > "$EXCLUDE_FILE"
    echo ".git/*" >> "$EXCLUDE_FILE"
fi

# Create tar archive
echo "Creating tar archive..."
if [ -f "$EXCLUDE_FILE" ]; then
    tar -czf "$LOCAL_TAR_PATH" \
        --exclude-from="$EXCLUDE_FILE" \
        -C "$(dirname "$WORKSPACE_DIR")" \
        "$(basename "$WORKSPACE_DIR")"
else
    tar -czf "$LOCAL_TAR_PATH" \
        --exclude=".git" \
        -C "$(dirname "$WORKSPACE_DIR")" \
        "$(basename "$WORKSPACE_DIR")"
fi

# Check if tar was created successfully
if [ ! -f "$LOCAL_TAR_PATH" ]; then
    echo "Error: Failed to create tar archive"
    rm -f "$EXCLUDE_FILE"
    exit 1
fi

TAR_SIZE=$(du -h "$LOCAL_TAR_PATH" | cut -f1)
echo "Tar archive created: $LOCAL_TAR_PATH ($TAR_SIZE)"

# SCP to target
echo "Copying to target host..."
if scp "$LOCAL_TAR_PATH" "$TARGET_HOST:$TARGET_PATH/$TAR_NAME"; then
    echo "Successfully copied to $TARGET_HOST:$TARGET_PATH/$TAR_NAME"
    
    # Verify on remote host
    echo "Verifying on remote host..."
    ssh "$TARGET_HOST" "ls -lh $TARGET_PATH/$TAR_NAME" && echo "Verification successful"
else
    echo "Error: Failed to copy to target host"
    rm -f "$LOCAL_TAR_PATH" "$EXCLUDE_FILE"
    exit 1
fi

# Cleanup
echo "Cleaning up temporary files..."
rm -f "$LOCAL_TAR_PATH" "$EXCLUDE_FILE"

echo "Backup completed successfully!"
echo "Remote file: $TARGET_HOST:$TARGET_PATH/$TAR_NAME"
