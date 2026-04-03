#!/bin/bash
# =============================================================================
# entrypoint.sh — fix volume permissions, then drop to unprivileged user
#
# Docker creates named volumes owned by root. Since the container process
# runs as UID 1001 (gemini), we must chown the mounts before switching user.
# gosu is used for clean privilege drop (no shell wrapper, proper signal handling).
# =============================================================================
set -e

# Generate machine-id if missing (needed for dbus/libsecret keychain)
if [ ! -f /etc/machine-id ]; then
    cat /proc/sys/kernel/random/uuid 2>/dev/null | tr -d '-' > /etc/machine-id || \
    echo "$(dd if=/dev/urandom bs=16 count=1 2>/dev/null | md5sum | cut -d' ' -f1)" > /etc/machine-id
fi

# Fix ownership of Docker-managed volumes (mounted as root by default)
chown -R gemini:gemini /home/gemini/.gemini 2>/dev/null || true
chown -R gemini:gemini /workspace            2>/dev/null || true

# Drop privileges and exec the CMD as gemini user
exec gosu gemini "$@"
