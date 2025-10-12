#!/bin/bash

set -ouex pipefail

ln -s /var/opt /opt 

### optfix.service

# define directories
LIB_EXEC_DIR="/usr/libexec/optfix"
SYSTEMD_DIR="/usr/lib/systemd/system"

# optfix.sh script
mkdir -p "${LIB_EXEC_DIR}"
cat << 'EOF' > "${LIB_EXEC_DIR}/optfix.sh"
#!/usr/bin/env bash

set -euo pipefail

SOURCE_DIR="/opt/"
TARGET_DIR="/var/opt/"

# Ensure the target directory exists
mkdir -p "$TARGET_DIR"

# Loop through directories in the source directory
for dir in "$SOURCE_DIR"*/; do
  if [ -d "$dir" ]; then
    # Get the base name of the directory
    dir_name=$(basename "$dir")
    
    # Check if the symlink already exists in the target directory
    if [ -L "$TARGET_DIR/$dir_name" ]; then
      echo "Symlink already exists for $dir_name, skipping."
      continue
    fi
    
    # Create the symlink
    ln -s "$dir" "$TARGET_DIR/$dir_name"
    echo "Created symlink for $dir_name"
  fi
done
EOF
chmod +x "${LIB_EXEC_DIR}/optfix.sh"

# systemd service
cat << 'EOF' > "${SYSTEMD_DIR}/optfix.service"
[Unit]
Description=Create symbolic links for directories in /usr/lib/opt/ to /var/opt/
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/libexec/optfix/optfix.sh
RemainAfterExit=no

[Install]
WantedBy=default.target
EOF

systemctl --system enable optfix.service