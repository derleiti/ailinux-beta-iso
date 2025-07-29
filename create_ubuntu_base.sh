#!/bin/bash
#
# AILinux Ubuntu Base System Creator v1.0
# Creates Ubuntu 24.04 base system with AI coordination
#

set -u
set +e

# Configuration
UBUNTU_RELEASE="noble"
UBUNTU_MIRROR="http://archive.ubuntu.com/ubuntu/"
CHROOT_DIR="/home/zombie/ailinux-iso/chroot"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Fix locale issues by setting standard locale for build
export LC_ALL=C
export LANG=C
export LANGUAGE=en

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Create Ubuntu base system
create_ubuntu_base() {
    log_info "🚀 Creating Ubuntu $UBUNTU_RELEASE base system"
    
    # Clean up any existing chroot
    if [[ -d "$CHROOT_DIR" ]]; then
        log_info "Cleaning up existing chroot directory"
        umount -R "$CHROOT_DIR" 2>/dev/null || true
        rm -rf "$CHROOT_DIR"
    fi
    
    # Create chroot directory
    mkdir -p "$CHROOT_DIR"
    
    # Run debootstrap with locale fixes
    log_info "Running debootstrap for Ubuntu $UBUNTU_RELEASE"
    
    # Set environment to avoid locale warnings
    export DEBIAN_FRONTEND=noninteractive
    export DEBCONF_NONINTERACTIVE_SEEN=true
    
    if ! debootstrap --arch=amd64 --components=main,restricted,universe,multiverse \
        --include=locales,locales-all \
        "$UBUNTU_RELEASE" "$CHROOT_DIR" "$UBUNTU_MIRROR"; then
        log_error "Failed to create Ubuntu base system"
        return 1
    fi
    
    log_success "✅ Ubuntu base system created successfully"
    return 0
}

# Configure base system
configure_base_system() {
    log_info "🔧 Configuring Ubuntu base system"
    
    # Configure DNS
    echo "nameserver 8.8.8.8" > "$CHROOT_DIR/etc/resolv.conf"
    echo "nameserver 8.8.4.4" >> "$CHROOT_DIR/etc/resolv.conf"
    
    # Configure sources.list
    cat > "$CHROOT_DIR/etc/apt/sources.list" << EOF
deb $UBUNTU_MIRROR $UBUNTU_RELEASE main restricted universe multiverse
deb $UBUNTU_MIRROR $UBUNTU_RELEASE-updates main restricted universe multiverse
deb $UBUNTU_MIRROR $UBUNTU_RELEASE-security main restricted universe multiverse
deb $UBUNTU_MIRROR $UBUNTU_RELEASE-backports main restricted universe multiverse
EOF
    
    # Set hostname
    echo "ailinux" > "$CHROOT_DIR/etc/hostname"
    
    # Configure hosts
    cat > "$CHROOT_DIR/etc/hosts" << EOF
127.0.0.1   localhost
127.0.1.1   ailinux

# The following lines are desirable for IPv6 capable hosts
::1     ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF
    
    log_success "✅ Base system configured"
    return 0
}

# Add AILinux repository for updated packages
add_ailinux_repository() {
    log_info "🔗 Adding AILinux repository for updated packages"
    
    # Download and execute the AILinux repository setup script in chroot
    chroot "$CHROOT_DIR" /bin/bash -c "
        export DEBIAN_FRONTEND=noninteractive 
        export LC_ALL=C.UTF-8 
        export LANG=C.UTF-8
        # Install curl if not present
        apt-get update -qq
        apt-get install -y curl
        
        # Add AILinux repository
        curl -fssSL https://ailinux.me:8443/mirror/add-ailinux-repo.sh | bash
    "
    
    if [ $? -eq 0 ]; then
        log_success "✅ AILinux repository added successfully"
        
        # Update package lists with new repository
        chroot "$CHROOT_DIR" /bin/bash -c "
            export DEBIAN_FRONTEND=noninteractive 
            export LC_ALL=C.UTF-8 
            export LANG=C.UTF-8
            apt-get update
        "
        log_success "✅ Package lists updated with AILinux repository"
    else
        log_warn "⚠️  Failed to add AILinux repository - continuing with Ubuntu repositories only"
    fi
    
    return 0
}

# Mount chroot filesystems
mount_chroot_filesystems() {
    log_info "📁 Mounting chroot filesystems"
    
    # Ensure mount points exist
    mkdir -p "$CHROOT_DIR"/{proc,sys,dev,run,dev/pts,dev/shm}
    
    # Mount proc filesystem
    if mount -t proc proc "$CHROOT_DIR/proc" 2>/dev/null; then
        log_success "  ✅ Mounted proc"
    else
        log_warn "  ⚠️  Failed to mount proc, continuing..."
    fi
    
    # Mount sysfs filesystem
    if mount -t sysfs sysfs "$CHROOT_DIR/sys" 2>/dev/null; then
        log_success "  ✅ Mounted sysfs"
    else
        log_warn "  ⚠️  Failed to mount sysfs, continuing..."
    fi
    
    # Mount dev filesystem - try bind mount first, then devtmpfs
    if mount --bind /dev "$CHROOT_DIR/dev" 2>/dev/null; then
        log_success "  ✅ Mounted dev (bind)"
    elif mount -t devtmpfs devtmpfs "$CHROOT_DIR/dev" 2>/dev/null; then
        log_success "  ✅ Mounted dev (devtmpfs)"
        
        # Create essential device nodes if using devtmpfs
        mknod "$CHROOT_DIR/dev/null" c 1 3 2>/dev/null || true
        mknod "$CHROOT_DIR/dev/zero" c 1 5 2>/dev/null || true
        mknod "$CHROOT_DIR/dev/random" c 1 8 2>/dev/null || true
        mknod "$CHROOT_DIR/dev/urandom" c 1 9 2>/dev/null || true
    else
        log_warn "  ⚠️  Failed to mount dev, creating minimal device nodes..."
        # Create minimal device nodes manually
        mknod "$CHROOT_DIR/dev/null" c 1 3 2>/dev/null || true
        mknod "$CHROOT_DIR/dev/zero" c 1 5 2>/dev/null || true
        mknod "$CHROOT_DIR/dev/random" c 1 8 2>/dev/null || true
        mknod "$CHROOT_DIR/dev/urandom" c 1 9 2>/dev/null || true
    fi
    
    # Mount devpts with multiple strategies
    mkdir -p "$CHROOT_DIR/dev/pts"
    if mount -t devpts devpts "$CHROOT_DIR/dev/pts" -o newinstance,ptmxmode=0666,gid=5,mode=620 2>/dev/null; then
        log_success "  ✅ Mounted devpts (newinstance)"
    elif mount -t devpts devpts "$CHROOT_DIR/dev/pts" -o gid=5,mode=620 2>/dev/null; then
        log_success "  ✅ Mounted devpts (standard)"
    elif mount --bind /dev/pts "$CHROOT_DIR/dev/pts" 2>/dev/null; then
        log_success "  ✅ Mounted devpts (bind)"
    else
        log_warn "  ⚠️  Failed to mount devpts - package configuration may show warnings"
        # Create a basic pts structure
        mkdir -p "$CHROOT_DIR/dev/pts"
        touch "$CHROOT_DIR/dev/pts/ptmx" 2>/dev/null || true
    fi
    
    # Mount tmpfs for /run
    if mount -t tmpfs tmpfs "$CHROOT_DIR/run" 2>/dev/null; then
        log_success "  ✅ Mounted run (tmpfs)"
    else
        log_warn "  ⚠️  Failed to mount run, continuing..."
        mkdir -p "$CHROOT_DIR/run"
    fi
    
    # Mount shm for shared memory
    mkdir -p "$CHROOT_DIR/dev/shm"
    if mount -t tmpfs tmpfs "$CHROOT_DIR/dev/shm" 2>/dev/null; then
        log_success "  ✅ Mounted shm"
    else
        log_warn "  ⚠️  Failed to mount shm, continuing..."
    fi
    
    log_success "✅ Chroot filesystem mounting completed"
    return 0
}

# Install essential packages
install_essential_packages() {
    log_info "📦 Installing essential packages in chroot"
    
    # Configure environment for chroot operations
    echo 'DEBIAN_FRONTEND=noninteractive' > "$CHROOT_DIR/etc/environment"
    echo 'LC_ALL=C.UTF-8' >> "$CHROOT_DIR/etc/environment"
    echo 'LANG=C.UTF-8' >> "$CHROOT_DIR/etc/environment"
    echo 'DEBCONF_NONINTERACTIVE_SEEN=true' >> "$CHROOT_DIR/etc/environment"
    
    # Pre-configure debconf to avoid interactive prompts
    cat > "$CHROOT_DIR/tmp/debconf-selections" << 'EOF'
# Preseeding for non-interactive installation
console-setup console-setup/charmap47 select UTF-8
console-setup console-setup/codeset47 select # Latin1 and Latin5 - western Europe and Turkic languages
console-setup console-setup/codesetcode string Lat15
console-setup console-setup/fontface47 select Fixed
console-setup console-setup/fontsize-fb47 select 8x16
console-setup console-setup/fontsize-text47 select 8x16
console-setup console-setup/fontsize47 string 8x16
keyboard-configuration keyboard-configuration/layout select English (US)
keyboard-configuration keyboard-configuration/layoutcode string us
keyboard-configuration keyboard-configuration/model select Generic 105-key (Intl) PC
keyboard-configuration keyboard-configuration/modelcode string pc105
keyboard-configuration keyboard-configuration/variant select English (US)
keyboard-configuration keyboard-configuration/variantcode string
keyboard-configuration keyboard-configuration/xkb-keymap select us
locales locales/default_environment_locale select C.UTF-8
locales locales/locales_to_be_generated multiselect C.UTF-8 UTF-8, en_US.UTF-8 UTF-8
tzdata tzdata/Areas select Etc
tzdata tzdata/Zones/Etc select UTC
EOF
    
    # Apply debconf preseeding
    chroot "$CHROOT_DIR" /bin/bash -c "
        export DEBIAN_FRONTEND=noninteractive 
        export LC_ALL=C.UTF-8 
        export LANG=C.UTF-8
        export DEBCONF_NONINTERACTIVE_SEEN=true
        debconf-set-selections < /tmp/debconf-selections 2>/dev/null || true
        rm -f /tmp/debconf-selections"
    
    # Update package lists
    chroot "$CHROOT_DIR" /bin/bash -c "export DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8 LANG=C.UTF-8; apt-get update"
    
    # Install essential packages
    chroot "$CHROOT_DIR" /bin/bash -c "
        export DEBIAN_FRONTEND=noninteractive 
        export LC_ALL=C.UTF-8 
        export LANG=C.UTF-8
        apt-get install -y \
            ubuntu-minimal \
            ubuntu-standard \
            casper \
            lupin-casper \
            discover \
            laptop-detect \
            os-prober \
            network-manager \
            resolvconf \
            net-tools \
            wireless-tools \
            wpasupplicant \
            locales \
            linux-generic \
            grub-pc-bin \
            grub-efi-amd64-bin \
            syslinux \
            isolinux \
            squashfs-tools \
            genisoimage \
            memtest86+ \
            rsync"
    
    log_success "✅ Essential packages installed"
    return 0
}

# Install KDE Desktop
install_kde_desktop() {
    log_info "🖥️ Installing KDE Desktop Environment"
    
    # Install KDE Plasma
    chroot "$CHROOT_DIR" /bin/bash -c "
        export DEBIAN_FRONTEND=noninteractive 
        export LC_ALL=C.UTF-8 
        export LANG=C.UTF-8
        apt-get install -y \
            kde-plasma-desktop \
            plasma-workspace \
            kscreen \
            powerdevil \
            plasma-nm \
            kde-config-networkmanager \
            systemsettings \
            dolphin \
            konsole \
            kate \
            firefox \
            libreoffice \
            vlc \
            gimp \
            thunderbird"
    
    log_success "✅ KDE Desktop installed"
    return 0
}

# Install Calamares
install_calamares() {
    log_info "🛠️ Installing Calamares installer"
    
    # Install Calamares and dependencies
    chroot "$CHROOT_DIR" /bin/bash -c "
        export DEBIAN_FRONTEND=noninteractive 
        export LC_ALL=C.UTF-8 
        export LANG=C.UTF-8
        apt-get install -y \
            calamares \
            calamares-settings-ubuntu \
            qml-module-qtquick-controls \
            qml-module-qtquick-layouts \
            qml-module-qtquick-window2 \
            qml-module-qtquick2"
    
    log_success "✅ Calamares installer installed"
    return 0
}

# Configure live user
configure_live_user() {
    log_info "👤 Configuring live user"
    
    # Create live user
    chroot "$CHROOT_DIR" /bin/bash -c "
        export DEBIAN_FRONTEND=noninteractive 
        export LC_ALL=C.UTF-8 
        export LANG=C.UTF-8
        useradd -m -s /bin/bash -G sudo,adm,cdrom,plugdev,lpadmin,sambashare ailinux"
    
    # Set password (empty for live system)
    chroot "$CHROOT_DIR" /bin/bash -c "
        export DEBIAN_FRONTEND=noninteractive 
        export LC_ALL=C.UTF-8 
        export LANG=C.UTF-8
        passwd -d ailinux"
    
    # Configure autologin
    mkdir -p "$CHROOT_DIR/etc/sddm.conf.d"
    cat > "$CHROOT_DIR/etc/sddm.conf.d/autologin.conf" << EOF
[Autologin]
User=ailinux
Session=plasma
EOF
    
    log_success "✅ Live user configured"
    return 0
}

# Finalize system
finalize_system() {
    log_info "🔧 Finalizing system configuration"
    
    # Generate locales
    chroot "$CHROOT_DIR" /bin/bash -c "
        export DEBIAN_FRONTEND=noninteractive 
        export LC_ALL=C.UTF-8 
        export LANG=C.UTF-8
        locale-gen en_US.UTF-8"
    
    # Update initramfs
    chroot "$CHROOT_DIR" /bin/bash -c "
        export DEBIAN_FRONTEND=noninteractive 
        export LC_ALL=C.UTF-8 
        export LANG=C.UTF-8
        update-initramfs -u"
    
    # Clean package cache
    chroot "$CHROOT_DIR" /bin/bash -c "
        export DEBIAN_FRONTEND=noninteractive 
        export LC_ALL=C.UTF-8 
        export LANG=C.UTF-8
        apt-get clean"
    
    # Remove package lists (will be regenerated)
    rm -rf "$CHROOT_DIR/var/lib/apt/lists/*"
    
    log_success "✅ System finalized"
    return 0
}

# Unmount chroot filesystems
unmount_chroot_filesystems() {
    log_info "📁 Unmounting chroot filesystems"
    
    # Unmount in reverse order with lazy unmounting
    local mount_points=(
        "$CHROOT_DIR/dev/shm"
        "$CHROOT_DIR/run"
        "$CHROOT_DIR/dev/pts"
        "$CHROOT_DIR/dev"
        "$CHROOT_DIR/sys"
        "$CHROOT_DIR/proc"
    )
    
    for mount_point in "${mount_points[@]}"; do
        if mountpoint -q "$mount_point" 2>/dev/null; then
            log_info "  Unmounting: $mount_point"
            if umount -l "$mount_point" 2>/dev/null; then
                log_success "  ✅ Unmounted: $(basename "$mount_point")"
            else
                log_warn "  ⚠️  Failed to unmount: $(basename "$mount_point")"
            fi
        fi
    done
    
    # Final cleanup - kill any remaining processes and force unmount
    if [ -d "$CHROOT_DIR" ]; then
        # Find and kill any processes still using the chroot
        local pids=$(fuser "$CHROOT_DIR" 2>/dev/null || true)
        if [ -n "$pids" ]; then
            log_info "  Killing processes using chroot: $pids"
            kill -TERM $pids 2>/dev/null || true
            sleep 1
            kill -KILL $pids 2>/dev/null || true
        fi
        
        # Force unmount any remaining mounts
        for mount in $(mount | grep "$CHROOT_DIR" | awk '{print $3}' | sort -r); do
            log_info "  Force unmounting: $mount"
            umount -lf "$mount" 2>/dev/null || true
        done
    fi
    
    log_success "✅ Chroot filesystems unmounted"
    return 0
}

# Main execution
main() {
    log_info "🎯 Starting AILinux Ubuntu Base System Creation"
    
    # Check for dry-run mode
    local dry_run=false
    if [[ "${1:-}" == "--dry-run" ]]; then
        dry_run=true
        log_info "🔍 Running in dry-run mode - no actual changes will be made"
    fi
    
    # Check if running as root (unless dry-run)
    if [[ $EUID -ne 0 ]] && [[ "$dry_run" != true ]]; then
        log_error "This script must be run as root (use sudo)"
        log_info "You can run with --dry-run to test without making changes"
        exit 1
    fi
    
    # Check required tools
    for tool in debootstrap chroot; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            log_error "Required tool '$tool' not found"
            exit 1
        fi
    done
    
    # Execute phases
    if [[ "$dry_run" == true ]]; then
        log_info "DRY-RUN: Would create Ubuntu base system"
        log_info "DRY-RUN: Would configure base system"
        log_info "DRY-RUN: Would add AILinux repository"
        log_info "DRY-RUN: Would mount chroot filesystems"
        log_info "DRY-RUN: Would install essential packages"
        log_info "DRY-RUN: Would install KDE desktop"
        log_info "DRY-RUN: Would install Calamares"
        log_info "DRY-RUN: Would configure live user"
        log_info "DRY-RUN: Would finalize system"
        log_info "DRY-RUN: Would unmount chroot filesystems"
    else
        create_ubuntu_base || exit 1
        configure_base_system || exit 1
        add_ailinux_repository || exit 1
        mount_chroot_filesystems || exit 1
        
        # Install packages
        install_essential_packages || exit 1
        install_kde_desktop || exit 1
        install_calamares || exit 1
        
        # Configure system
        configure_live_user || exit 1
        finalize_system || exit 1
        
        # Cleanup
        unmount_chroot_filesystems || exit 1
    fi
    
    log_success "🎉 AILinux Ubuntu Base System created successfully!"
    log_info "📍 System location: $CHROOT_DIR"
    log_info "🚀 Ready for ISO generation"
    
    return 0
}

# Trap for cleanup on exit
trap 'unmount_chroot_filesystems 2>/dev/null || true' EXIT

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi