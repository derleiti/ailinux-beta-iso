#!/bin/bash
#
# AILinux Build Cleanup Script
# Safely unmounts chroot and cleans up interrupted builds
#

set -u
set +e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

CHROOT_DIR="/home/zombie/ailinux-iso/chroot"

echo -e "${YELLOW}🧹 AILinux Build Cleanup Script${NC}"
echo "================================="

# Function to safely unmount
safe_unmount() {
    local mount_point="$1"
    if mountpoint -q "$mount_point" 2>/dev/null; then
        echo -e "${YELLOW}Unmounting: $mount_point${NC}"
        if ! umount -l "$mount_point" 2>/dev/null; then
            echo -e "${RED}Failed to unmount $mount_point${NC}"
            return 1
        fi
        echo -e "${GREEN}✅ Unmounted: $mount_point${NC}"
    else
        echo -e "${GREEN}Not mounted: $mount_point${NC}"
    fi
    return 0
}

# Kill any processes using the chroot
if [ -d "$CHROOT_DIR" ]; then
    echo -e "${YELLOW}Checking for processes using chroot...${NC}"
    
    # Find and kill processes
    for pid in $(fuser "$CHROOT_DIR" 2>/dev/null); do
        if [ -n "$pid" ]; then
            echo -e "${YELLOW}Killing process $pid using chroot${NC}"
            kill -TERM "$pid" 2>/dev/null || true
            sleep 1
            kill -KILL "$pid" 2>/dev/null || true
        fi
    done
fi

# Unmount chroot filesystems in reverse order
if [ -d "$CHROOT_DIR" ]; then
    safe_unmount "$CHROOT_DIR/run"
    safe_unmount "$CHROOT_DIR/dev/pts"
    safe_unmount "$CHROOT_DIR/dev"
    safe_unmount "$CHROOT_DIR/sys"
    safe_unmount "$CHROOT_DIR/proc"
    
    # Wait a moment and try again for any stubborn mounts
    sleep 2
    
    # Force unmount if needed
    for mount in $(mount | grep "$CHROOT_DIR" | awk '{print $3}' | sort -r); do
        echo -e "${YELLOW}Force unmounting: $mount${NC}"
        umount -lf "$mount" 2>/dev/null || true
    done
fi

# Optional: Remove chroot directory completely
read -p "Do you want to remove the chroot directory completely? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    if [ -d "$CHROOT_DIR" ]; then
        echo -e "${YELLOW}Removing chroot directory...${NC}"
        rm -rf "$CHROOT_DIR"
        echo -e "${GREEN}✅ Chroot directory removed${NC}"
    fi
fi

# Clean up temporary files
echo -e "${YELLOW}Cleaning up temporary files...${NC}"
rm -f /tmp/ailinux-* 2>/dev/null || true
rm -f ./*.pid 2>/dev/null || true

echo -e "${GREEN}🎉 Cleanup completed!${NC}"
echo "You can now restart the build process."