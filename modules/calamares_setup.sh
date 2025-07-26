#!/bin/bash
#
# Calamares Installer Setup Module for AILinux Build Script
# Provides Calamares installer configuration and branding
#
# This module handles the installation and configuration of the Calamares
# system installer with AILinux-specific customizations and branding.
#

# Global Calamares configuration
declare -g CALAMARES_VERSION="3.3"
declare -g CALAMARES_CONFIG_DIR=""
declare -g CALAMARES_BRANDING_DIR=""
declare -g CALAMARES_MODULES=()
declare -g CALAMARES_CONFIG_FILES=()

# Initialize Calamares setup system
init_calamares_setup() {
    log_info "🔧 Initializing Calamares installer setup..."
    
    # Set up Calamares directories
    setup_calamares_directories
    
    # Configure Calamares modules
    configure_calamares_modules
    
    # Set up branding configuration
    setup_calamares_branding
    
    log_success "Calamares installer setup initialized"
}

# Set up Calamares directories and structure
setup_calamares_directories() {
    local chroot_dir="${AILINUX_BUILD_CHROOT_DIR:-/tmp/ailinux_chroot}"
    
    log_info "📁 Setting up Calamares directories..."
    
    CALAMARES_CONFIG_DIR="$chroot_dir/etc/calamares"
    CALAMARES_BRANDING_DIR="$chroot_dir/usr/share/calamares/branding/ailinux"
    
    # Create essential Calamares directories
    local calamares_dirs=(
        "$CALAMARES_CONFIG_DIR"
        "$CALAMARES_CONFIG_DIR/modules"
        "$CALAMARES_BRANDING_DIR"
        "$chroot_dir/usr/share/applications"
        "$chroot_dir/usr/share/pixmaps"
    )
    
    for dir in "${calamares_dirs[@]}"; do
        if ! mkdir -p "$dir"; then
            log_error "❌ Failed to create Calamares directory: $dir"
            return 1
        fi
    done
    
    log_success "✅ Calamares directories created"
}

# Install Calamares installer
install_calamares() {
    local chroot_dir="${1:-$AILINUX_BUILD_CHROOT_DIR}"
    
    if [ ! -d "$chroot_dir" ]; then
        log_error "❌ Chroot directory not found: $chroot_dir"
        return 1
    fi
    
    log_info "📦 Installing Calamares installer..."
    
    # Update package lists
    enter_chroot_safely "$chroot_dir" "apt-get update" || {
        log_error "❌ Failed to update package lists"
        return 1
    }
    
    # Install Calamares and dependencies
    local calamares_packages="calamares calamares-settings-ubuntu parted gparted"
    local install_cmd="DEBIAN_FRONTEND=noninteractive apt-get install -y $calamares_packages"
    
    if ! enter_chroot_safely "$chroot_dir" "$install_cmd"; then
        log_error "❌ Failed to install Calamares"
        return 1
    fi
    
    log_success "✅ Calamares installer installed successfully"
    
    # Verify installation
    if ! enter_chroot_safely "$chroot_dir" "which calamares" >/dev/null 2>&1; then
        log_error "❌ Calamares installation verification failed"
        return 1
    fi
    
    return 0
}

# Configure Calamares modules
configure_calamares_modules() {
    local chroot_dir="${AILINUX_BUILD_CHROOT_DIR:-/tmp/ailinux_chroot}"
    
    log_info "⚙️  Configuring Calamares modules..."
    
    # Define AILinux-specific module sequence
    CALAMARES_MODULES=(
        "welcome"
        "locale"
        "keyboard" 
        "partition"
        "users"
        "summary"
        "exec"
        "packages"
        "machineid"
        "fstab"
        "mount" 
        "unpackfs"
        "sources-media"
        "shellprocess"
        "initramfs"
        "grubcfg"
        "bootloader"
        "umount"
        "finished"
    )
    
    # Create main Calamares configuration
    create_main_calamares_config "$chroot_dir"
    
    # Configure individual modules
    configure_welcome_module "$chroot_dir"
    configure_partition_module "$chroot_dir"
    configure_users_module "$chroot_dir"
    configure_bootloader_module "$chroot_dir"
    configure_packages_module "$chroot_dir"
    configure_shellprocess_module "$chroot_dir"
    
    log_success "✅ Calamares modules configured"
}

# Create main Calamares configuration
create_main_calamares_config() {
    local chroot_dir="$1"
    local config_file="$CALAMARES_CONFIG_DIR/settings.conf"
    
    log_info "📝 Creating main Calamares configuration..."
    
    cat > "$config_file" << EOF
# AILinux Calamares Configuration
# Generated: $(date)

modules-search: [ local ]

instances:
- id:       partition
  module:   partition
  config:   partition.conf
  
- id:       mount
  module:   mount
  config:   mount.conf

sequence:
- show:
  - welcome
  - locale
  - keyboard
  - partition
  - users
  - summary
- exec:
  - partition
  - mount
  - unpackfs
  - machineid
  - fstab
  - locale
  - keyboard
  - users
  - displaymanager
  - networkcfg
  - hwclock
  - services-systemd
  - bootloader
  - grubcfg
  - packages
  - luksbootkeyfile
  - plmouth
  - initramfs
  - sources-media
  - shellprocess
  - umount
- show:
  - finished

branding: ailinux

prompt-install: false
dont-chroot: false
oem-setup: false
disable-cancel: false
disable-cancel-during-exec: false
hide-back-and-next-during-exec: false

quit-at-end: false
EOF
    
    CALAMARES_CONFIG_FILES+=("$config_file")
    log_success "✅ Main Calamares configuration created"
}

# Configure welcome module
configure_welcome_module() {
    local chroot_dir="$1"
    local config_file="$CALAMARES_CONFIG_DIR/modules/welcome.conf"
    
    cat > "$config_file" << EOF
# Welcome module configuration
showSupportUrl:         false
showKnownIssuesUrl:     false
showReleaseNotesUrl:    false
showDonateUrl:          false

requirements:
    requiredStorage:    5.5
    requiredRam:        1.0
    internetCheckUrl:   http://google.com
    checkHasInternet:   false

geoip:
    style:    "none"
    url:      ""
    selector: ""

EOF
    
    CALAMARES_CONFIG_FILES+=("$config_file")
}

# Configure partition module
configure_partition_module() {
    local chroot_dir="$1"
    local config_file="$CALAMARES_CONFIG_DIR/modules/partition.conf"
    
    cat > "$config_file" << EOF
# Partition module configuration
# EFI system partition
efiSystemPartition:     "/boot/efi"
efiSystemPartitionSize: 300M
efiSystemPartitionName: EFI

# User choices
userSwapChoices:
    - none      # No swap
    - small     # Up to 4GB
    - suspend   # At least RAM size
    - file      # Swap file instead of partition

initialPartitioningChoice: none
initialSwapChoice: none

defaultFileSystemType:  "ext4"

availableFileSystemTypes:
    - "ext4"
    - "ext3" 
    - "btrfs"
    - "xfs"
    - "f2fs"
    - "jfs"
    - "reiser4"

drawNestedPartitions:   false
alwaysShowPartitionLabels: true
allowManualPartitioning: true

defaultPartitionTableType: gpt
EOF
    
    CALAMARES_CONFIG_FILES+=("$config_file")
}

# Configure users module
configure_users_module() {
    local chroot_dir="$1"
    local config_file="$CALAMARES_CONFIG_DIR/modules/users.conf"
    
    cat > "$config_file" << EOF
# Users module configuration
defaultGroups:
    - name: users
      must: false
    - name: lpadmin
      must: false
    - name: wheel
      must: false
    - name: audio
      must: false
    - name: video
      must: false
    - name: network
      must: false
    - name: storage
      must: false
    - name: power
      must: false
    - name: adm
      must: false

autologinGroup:  autologin
sudoersGroup:    wheel

setRootPassword: true
doReusePassword: false

passwordRequirements:
    minLength: 4
    maxLength: -1
    
userShell: /bin/bash

hostname:
    location: EtcFile
    writeHostsFile: true
    template: "ailinux-\${cpu}"
    forbidden: [ localhost ]
EOF
    
    CALAMARES_CONFIG_FILES+=("$config_file")
}

# Configure bootloader module
configure_bootloader_module() {
    local chroot_dir="$1"
    local config_file="$CALAMARES_CONFIG_DIR/modules/bootloader.conf"
    
    cat > "$config_file" << EOF
# Bootloader module configuration
efiBootLoader: "grub"
efiBootloaderId: "ailinux"

kernel: "/vmlinuz"
img: "/initrd.img"
fallback: "/initrd.img.fallback"

grubInstall: "grub-install"
grubMkconfig: "grub-mkconfig"
grubCfg: "/boot/grub/grub.cfg"
efiBootMgr: "efibootmgr"

installEFIFallback: true
EOF
    
    CALAMARES_CONFIG_FILES+=("$config_file")
}

# Configure packages module
configure_packages_module() {
    local chroot_dir="$1"
    local config_file="$CALAMARES_CONFIG_DIR/modules/packages.conf"
    
    cat > "$config_file" << EOF
# Packages module configuration
backend: apt

operations:
  - install:
    - ailinux-base
    - ailinux-desktop
    - linux-firmware
    - grub-efi-amd64
    - grub-efi-amd64-signed
    - shim-signed
  - remove:
    - calamares
    - ubiquity
    - casper
  - try_install:
    - plymouth-theme-ailinux
    - ailinux-wallpapers
  - try_remove:
    - example-content
EOF
    
    CALAMARES_CONFIG_FILES+=("$config_file")
}

# Configure shellprocess module
configure_shellprocess_module() {
    local chroot_dir="$1"
    local config_file="$CALAMARES_CONFIG_DIR/modules/shellprocess.conf"
    
    cat > "$config_file" << EOF
# Shellprocess module configuration
script:
  - command: "/usr/bin/env"
    timeout: 10
  - "/usr/local/bin/ailinux-postinstall.sh @@ROOT@@"
  - "systemctl enable sddm"
  - "systemctl set-default graphical.target"
  - "update-grub"

dontChroot: false
timeout: 999
EOF
    
    CALAMARES_CONFIG_FILES+=("$config_file")
}

# Set up Calamares branding
setup_calamares_branding() {
    local chroot_dir="${AILINUX_BUILD_CHROOT_DIR:-/tmp/ailinux_chroot}"
    
    log_info "🎨 Setting up AILinux Calamares branding..."
    
    # Create branding configuration
    create_branding_descriptor "$chroot_dir"
    
    # Set up branding resources
    setup_branding_resources "$chroot_dir"
    
    # Configure branding stylesheets
    setup_branding_stylesheets "$chroot_dir"
    
    log_success "✅ Calamares branding configured"
}

# Create branding descriptor
create_branding_descriptor() {
    local chroot_dir="$1"
    local branding_file="$CALAMARES_BRANDING_DIR/branding.desc"
    
    cat > "$branding_file" << EOF
# AILinux Calamares Branding Configuration
---
componentName: ailinux

strings:
    productName:         "AILinux"
    shortProductName:    "AILinux"
    version:             "1.0"
    shortVersion:        "1.0"
    versionedName:       "AILinux 1.0"
    shortVersionedName:  "AILinux 1.0"
    bootloaderEntryName: "AILinux"
    productUrl:          "https://ailinux.org"
    supportUrl:          "https://ailinux.org/support"
    knownIssuesUrl:      "https://ailinux.org/issues"
    releaseNotesUrl:     "https://ailinux.org/releases"
    donateUrl:           "https://ailinux.org/donate"

images:
    productLogo:         "logo.png"
    productIcon:         "icon.png"
    productWallpaper:    "wallpaper.jpg"

style:
   sidebarBackground:    "#1e3a8a"
   sidebarText:          "#ffffff"
   sidebarTextSelect:    "#4a90e2"
   sidebarTextCurrent:   "#ffffff"

slideshow:              "show.qml"

strings:
    welcomeStyleCalamares:   "Welcome to the %1 installer."
    welcomeExpandingCommunity: |
        The %1 community and the %2 team welcome you to %1.

        This installer will help you choose and install %1 on your computer. It is simple to use, and this installer can also preserve the files from your existing operating system. When you are ready to begin, click <strong>Install</strong>.
EOF
    
    CALAMARES_CONFIG_FILES+=("$branding_file")
}

# Set up branding resources
setup_branding_resources() {
    local chroot_dir="$1"
    
    # Create logo (placeholder - simple text-based logo)
    create_placeholder_logo "$CALAMARES_BRANDING_DIR/logo.png"
    
    # Create icon (placeholder)
    create_placeholder_icon "$CALAMARES_BRANDING_DIR/icon.png"
    
    # Create simple slideshow
    create_simple_slideshow "$CALAMARES_BRANDING_DIR/show.qml"
}

# Create placeholder logo
create_placeholder_logo() {
    local logo_file="$1"
    
    # Create a simple text-based logo using ImageMagick if available
    if command -v convert >/dev/null 2>&1; then
        convert -size 300x100 xc:transparent -font Arial -pointsize 36 -fill "#1e3a8a" -gravity center -annotate +0+0 "AILinux" "$logo_file" 2>/dev/null || {
            # Fallback: create empty file
            touch "$logo_file"
        }
    else
        # Create empty placeholder
        touch "$logo_file"
    fi
}

# Create placeholder icon
create_placeholder_icon() {
    local icon_file="$1"
    
    if command -v convert >/dev/null 2>&1; then
        convert -size 64x64 xc:"#1e3a8a" -fill white -gravity center -font Arial -pointsize 20 -annotate +0+0 "AI" "$icon_file" 2>/dev/null || {
            touch "$icon_file"
        }
    else
        touch "$icon_file"
    fi
}

# Create simple slideshow
create_simple_slideshow() {
    local slideshow_file="$1"
    
    cat > "$slideshow_file" << 'EOF'
import QtQuick 2.0;
import calamares.slideshow 1.0;

Presentation
{
    id: presentation

    function nextSlide() {
        console.log("QML Component (default slideshow) Next slide");
        presentation.goToNextSlide();
    }

    Timer {
        id: advanceTimer
        interval: 5000
        running: presentation.activatedInCalamares
        repeat: true
        onTriggered: nextSlide()
    }

    Slide {
        Image {
            id: background1
            source: "wallpaper.jpg"
            width: parent.width; height: parent.height
            horizontalAlignment: Image.AlignCenter
            verticalAlignment: Image.AlignTop
            fillMode: Image.Stretch
            anchors.fill: parent
        }
        Text {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: 0
            font.pixelSize: parent.width *.02
            color: 'white'
            text: qsTr("Welcome to AILinux")
            wrapMode: Text.WordWrap
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
        }
    }

    Slide {
        Image {
            id: background2
            source: "wallpaper.jpg"
            width: parent.width; height: parent.height
            horizontalAlignment: Image.AlignCenter
            verticalAlignment: Image.AlignTop
            fillMode: Image.Stretch
            anchors.fill: parent
        }
        Text {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: 0
            font.pixelSize: parent.width *.02
            color: 'white'
            text: qsTr("AILinux provides AI-powered tools for productivity")
            wrapMode: Text.WordWrap
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
        }
    }

    Slide {
        Image {
            id: background3
            source: "wallpaper.jpg"
            width: parent.width; height: parent.height
            horizontalAlignment: Image.AlignCenter
            verticalAlignment: Image.AlignTop
            fillMode: Image.Stretch
            anchors.fill: parent
        }
        Text {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: 0
            font.pixελSize: parent.width *.02
            color: 'white'
            text: qsTr("Installation is complete! Enjoy AILinux!")
            wrapMode: Text.WordWrap
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
EOF
}

# Set up branding stylesheets
setup_branding_stylesheets() {
    local chroot_dir="$1"
    local stylesheet_file="$CALAMARES_BRANDING_DIR/stylesheet.qss"
    
    cat > "$stylesheet_file" << EOF
/* AILinux Calamares Stylesheet */

/* Main window styling */
#mainApp {
    background-color: #f8fafc;
}

/* Sidebar styling */
#sidebarApp {
    background-color: #1e3a8a;
    border: none;
}

#sidebarMenuApp QListWidget {
    background-color: #1e3a8a;
    border: none;
}

#sidebarMenuApp QListWidget::item {
    color: #ffffff;
    padding: 10px;
    border-bottom: 1px solid #2563eb;
}

#sidebarMenuApp QListWidget::item:selected {
    background-color: #3b82f6;
    color: #ffffff;
}

#sidebarMenuApp QListWidget::item:hover {
    background-color: #2563eb;
}

/* Button styling */
QPushButton {
    background-color: #3b82f6;
    color: white;
    border: none;
    padding: 8px 16px;
    border-radius: 4px;
    font-weight: bold;
}

QPushButton:hover {
    background-color: #2563eb;
}

QPushButton:pressed {
    background-color: #1d4ed8;
}

QPushButton:disabled {
    background-color: #9ca3af;
    color: #6b7280;
}

/* Progress bar styling */
QProgressBar {
    border: 2px solid #e5e7eb;
    border-radius: 5px;
    text-align: center;
    background-color: #f3f4f6;
}

QProgressBar::chunk {
    background-color: #3b82f6;
    border-radius: 3px;
}

/* Text styling */
QLabel {
    color: #1f2937;
}

/* Input field styling */
QLineEdit, QTextEdit {
    background-color: white;
    border: 2px solid #d1d5db;
    border-radius: 4px;
    padding: 8px;
    color: #1f2937;
}

QLineEdit:focus, QTextEdit:focus {
    border-color: #3b82f6;
}
EOF
    
    CALAMARES_CONFIG_FILES+=("$stylesheet_file")
}

# Validate Calamares installation
validate_calamares_install() {
    local chroot_dir="${1:-$AILINUX_BUILD_CHROOT_DIR}"
    
    log_info "🔍 Validating Calamares installation..."
    
    local validation_errors=0
    
    # Check if Calamares is installed
    if ! enter_chroot_safely "$chroot_dir" "which calamares" >/dev/null 2>&1; then
        log_error "❌ Calamares executable not found"
        ((validation_errors++))
    fi
    
    # Check main configuration file
    if [ ! -f "$CALAMARES_CONFIG_DIR/settings.conf" ]; then
        log_error "❌ Main Calamares configuration missing"
        ((validation_errors++))
    fi
    
    # Check branding configuration
    if [ ! -f "$CALAMARES_BRANDING_DIR/branding.desc" ]; then
        log_error "❌ Calamares branding configuration missing"
        ((validation_errors++))
    fi
    
    # Check essential module configurations
    local essential_modules=("welcome.conf" "partition.conf" "users.conf" "bootloader.conf")
    
    for module_config in "${essential_modules[@]}"; do
        if [ ! -f "$CALAMARES_CONFIG_DIR/modules/$module_config" ]; then
            log_error "❌ Essential module configuration missing: $module_config"
            ((validation_errors++))
        fi
    done
    
    # Validate configuration syntax (basic check)
    if command -v python3 >/dev/null && command -v yaml >/dev/null 2>&1; then
        for config_file in "${CALAMARES_CONFIG_FILES[@]}"; do
            if [[ "$config_file" == *.conf ]]; then
                # Simple YAML validation would go here
                continue
            fi
        done
    fi
    
    if [ $validation_errors -eq 0 ]; then
        log_success "✅ Calamares installation validation passed"
        return 0
    else
        log_error "❌ Calamares installation validation failed with $validation_errors errors"
        return 1
    fi
}

# Create Calamares desktop entry
create_calamares_desktop_entry() {
    local chroot_dir="${1:-$AILINUX_BUILD_CHROOT_DIR}"
    
    log_info "🖥️  Creating Calamares desktop entry..."
    
    local desktop_file="$chroot_dir/usr/share/applications/calamares.desktop"
    
    cat > "$desktop_file" << EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=Install AILinux
GenericName=System Installer
Keywords=calamares;system;installer;
TryExec=calamares
Exec=pkexec calamares
Comment=Calamares — System Installer
Icon=calamares
Terminal=false
StartupNotify=true
Categories=Qt;System;
X-AppStream-Ignore=true
EOF
    
    # Create autostart entry for live session
    local autostart_dir="$chroot_dir/etc/skel/.config/autostart"
    mkdir -p "$autostart_dir"
    
    local autostart_file="$autostart_dir/calamares.desktop"
    
    cat > "$autostart_file" << EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=Install AILinux
GenericName=System Installer
Keywords=calamares;system;installer;
TryExec=calamares
Exec=calamares
Comment=Calamares — System Installer
Icon=calamares
Terminal=false
StartupNotify=true
Categories=Qt;System;
X-AppStream-Ignore=true
Hidden=false
X-GNOME-Autostart-enabled=true
EOF
    
    log_success "✅ Calamares desktop entries created"
}

# Clean up Calamares setup resources
cleanup_calamares_setup() {
    log_info "🧹 Cleaning up Calamares setup resources..."
    
    # Generate installation report
    create_calamares_setup_report
    
    log_success "Calamares setup cleanup completed"
}

# Create Calamares setup report
create_calamares_setup_report() {
    local report_file="/tmp/ailinux_calamares_setup_report_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "# AILinux Calamares Setup Report"
        echo "# Generated: $(date)"
        echo "# Version: $CALAMARES_VERSION"
        echo ""
        
        echo "== CONFIGURATION FILES =="
        printf '%s\n' "${CALAMARES_CONFIG_FILES[@]}"
        echo ""
        
        echo "== MODULES CONFIGURED =="
        printf '%s\n' "${CALAMARES_MODULES[@]}"
        echo ""
        
        echo "== BRANDING =="
        echo "Branding Directory: $CALAMARES_BRANDING_DIR"
        echo "Config Directory: $CALAMARES_CONFIG_DIR"
        echo ""
        
    } > "$report_file"
    
    log_success "📄 Calamares setup report created: $report_file"
    
    # Coordinate through swarm
    swarm_coordinate "calamares_setup" "Calamares installer configured successfully" "success" "installation" || true
}

# Export functions for use in other modules
export -f init_calamares_setup
export -f install_calamares
export -f configure_calamares_modules
export -f setup_calamares_branding
export -f validate_calamares_install
export -f create_calamares_desktop_entry
export -f cleanup_calamares_setup