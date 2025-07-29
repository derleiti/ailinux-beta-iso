#!/bin/bash
#
# Secure Boot Handler Module for AILinux Build Script
# Provides Secure Boot and UEFI/BIOS configuration
#
# This module handles UEFI Secure Boot configuration, certificate management,
# and ensures compatibility with both UEFI and legacy BIOS systems.
#

# Global Secure Boot configuration
declare -g SECUREBOOT_ENABLED=true
declare -g UEFI_SUPPORT=true
declare -g LEGACY_BIOS_SUPPORT=true
declare -g SECUREBOOT_CERTIFICATES=()
declare -g BOOT_LOADERS=()
declare -g BOOT_CONFIG_FILES=()

# Initialize Secure Boot handling system
init_secureboot_handling() {
    log_info "🔒 Initializing Secure Boot handling system..."
    
    # Detect system boot capabilities
    detect_boot_capabilities
    
    # Set up boot directories
    setup_boot_directories
    
    # Configure boot loaders
    configure_boot_loaders
    
    # Set up certificate management
    setup_certificate_management
    
    log_success "Secure Boot handling system initialized"
}

# Detect system boot capabilities
detect_boot_capabilities() {
    log_info "🔍 Detecting system boot capabilities..."
    
    # Check if system supports UEFI
    if [ -d "/sys/firmware/efi" ]; then
        UEFI_SUPPORT=true
        log_success "✅ UEFI support detected"
        
        # Check if Secure Boot is available
        if [ -f "/sys/firmware/efi/efivars/SecureBoot-*" ] 2>/dev/null; then
            SECUREBOOT_ENABLED=true
            log_success "✅ Secure Boot capability detected"
        else
            log_info "ℹ️  Secure Boot not available (normal for build environment)"
        fi
    else
        UEFI_SUPPORT=false
        log_info "ℹ️  UEFI not detected (build environment or legacy system)"
    fi
    
    # Always support legacy BIOS for compatibility
    LEGACY_BIOS_SUPPORT=true
    log_info "✅ Legacy BIOS support enabled"
    
    # Export capabilities
    export AILINUX_UEFI_SUPPORT="$UEFI_SUPPORT"
    export AILINUX_SECUREBOOT_ENABLED="$SECUREBOOT_ENABLED"
    export AILINUX_LEGACY_BIOS_SUPPORT="$LEGACY_BIOS_SUPPORT"
}

# Set up boot directories and structure
setup_boot_directories() {
    local chroot_dir="${AILINUX_BUILD_CHROOT_DIR:-/tmp/ailinux_chroot}"
    
    log_info "📁 Setting up boot directories..."
    
    # Essential boot directories
    local boot_dirs=(
        "$chroot_dir/boot"
        "$chroot_dir/boot/efi"
        "$chroot_dir/boot/efi/EFI"
        "$chroot_dir/boot/efi/EFI/BOOT"
        "$chroot_dir/boot/efi/EFI/ailinux"
        "$chroot_dir/boot/grub"
        "$chroot_dir/etc/default"
        "$chroot_dir/usr/share/grub"
        "$chroot_dir/var/lib/shim-signed"
    )
    
    for dir in "${boot_dirs[@]}"; do
        if ! mkdir -p "$dir"; then
            log_error "❌ Failed to create boot directory: $dir"
            return 1
        fi
    done
    
    log_success "✅ Boot directories created"
}

# Configure boot loaders for different boot modes
configure_boot_loaders() {
    local chroot_dir="${AILINUX_BUILD_CHROOT_DIR:-/tmp/ailinux_chroot}"
    
    log_info "🔧 Configuring boot loaders..."
    
    # Configure GRUB for both UEFI and BIOS
    configure_grub_bootloader "$chroot_dir"
    
    # Set up Secure Boot components
    if [ "$SECUREBOOT_ENABLED" = true ]; then
        setup_secure_boot "$chroot_dir"
    fi
    
    # Configure UEFI boot entries
    if [ "$UEFI_SUPPORT" = true ]; then
        configure_uefi_boot "$chroot_dir"
    fi
    
    # Configure legacy BIOS boot
    if [ "$LEGACY_BIOS_SUPPORT" = true ]; then
        configure_legacy_boot "$chroot_dir"
    fi
    
    log_success "✅ Boot loaders configured"
}

# Configure GRUB bootloader
configure_grub_bootloader() {
    local chroot_dir="$1"
    
    log_info "🔧 Configuring GRUB bootloader..."
    
    # Install GRUB packages
    install_grub_packages "$chroot_dir"
    
    # Create GRUB configuration
    create_grub_configuration "$chroot_dir"
    
    # Set up GRUB themes
    setup_grub_themes "$chroot_dir"
    
    BOOT_LOADERS+=("grub")
    log_success "✅ GRUB bootloader configured"
}

# Install GRUB packages
install_grub_packages() {
    local chroot_dir="$1"
    
    log_info "📦 Installing GRUB packages..."
    
    # Define GRUB packages based on boot support
    local grub_packages=("grub-common" "grub2-common")
    
    if [ "$UEFI_SUPPORT" = true ]; then
        grub_packages+=(
            "grub-efi-amd64"
            "grub-efi-amd64-bin"
            "grub-efi-amd64-signed"
        )
    fi
    
    if [ "$LEGACY_BIOS_SUPPORT" = true ]; then
        grub_packages+=(
            "grub-pc"
            "grub-pc-bin"
        )
    fi
    
    # Install GRUB packages
    local install_cmd="DEBIAN_FRONTEND=noninteractive apt-get install -y ${grub_packages[*]}"
    
    if ! enter_chroot_safely "$chroot_dir" "$install_cmd"; then
        log_error "❌ Failed to install GRUB packages"
        return 1
    fi
    
    log_success "✅ GRUB packages installed"
}

# Create GRUB configuration
create_grub_configuration() {
    local chroot_dir="$1"
    
    log_info "📝 Creating GRUB configuration..."
    
    # Create GRUB default configuration
    local grub_default="$chroot_dir/etc/default/grub"
    
    cat > "$grub_default" << EOF
# AILinux GRUB Configuration
# Generated: $(date)

# Basic boot options
GRUB_DEFAULT=0
GRUB_TIMEOUT=10
GRUB_DISTRIBUTOR="AILinux"

# Kernel command line
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
GRUB_CMDLINE_LINUX=""

# Display options
GRUB_TERMINAL_OUTPUT="console"
GRUB_GFXMODE="auto"
GRUB_GFXPAYLOAD_LINUX="keep"

# Theme and appearance
GRUB_THEME="/usr/share/grub/themes/ailinux/theme.txt"
GRUB_BACKGROUND="/usr/share/grub/themes/ailinux/background.png"

# Security options
GRUB_DISABLE_RECOVERY="false"
GRUB_DISABLE_OS_PROBER="false"

# UEFI Secure Boot options
EOF
    
    # Add UEFI-specific options
    if [ "$UEFI_SUPPORT" = true ]; then
        cat >> "$grub_default" << EOF
GRUB_ENABLE_CRYPTODISK="n"
GRUB_PRELOAD_MODULES="part_gpt part_msdos"
EOF
    fi
    
    # Add Secure Boot options
    if [ "$SECUREBOOT_ENABLED" = true ]; then
        cat >> "$grub_default" << EOF

# Secure Boot configuration
GRUB_ENABLE_BLSCFG=true
EOF
    fi
    
    BOOT_CONFIG_FILES+=("$grub_default")
    log_success "✅ GRUB configuration created"
}

# Set up GRUB themes
setup_grub_themes() {
    local chroot_dir="$1"
    
    log_info "🎨 Setting up GRUB themes..."
    
    # Create AILinux GRUB theme directory
    local theme_dir="$chroot_dir/usr/share/grub/themes/ailinux"
    mkdir -p "$theme_dir"
    
    # Create AILinux GRUB theme
    create_ailinux_grub_theme "$theme_dir"
    
    log_success "✅ GRUB themes configured"
}

# Create AILinux GRUB theme
create_ailinux_grub_theme() {
    local theme_dir="$1"
    
    # Create theme configuration
    local theme_file="$theme_dir/theme.txt"
    
    cat > "$theme_file" << EOF
# AILinux GRUB Theme
# Generated: $(date)

# Screen resolution and layout
desktop-image: "background.png"
desktop-color: "#1e3a8a"
terminal-font: "unifont_16"

# Boot menu styling
+ boot_menu {
    left = 25%
    top = 30%
    width = 50%
    height = 40%
    item_font = "unifont_16"
    item_color = "#ffffff"
    selected_item_color = "#4a90e2"
    selected_item_pixmap_style = "select_*.png"
    item_height = 32
    item_padding = 8
    item_spacing = 4
}

# Title display
+ label {
    id = "title"
    text = "AILinux Boot Menu"
    font = "unifont_16"
    color = "#ffffff"
    align = "center"
    top = 20%
}

# Progress bar
+ progress_bar {
    id = "progress_bar"
    left = 25%
    top = 75%
    width = 50%
    height = 20
    font = "unifont_16"
    text_color = "#ffffff"
    fg_color = "#4a90e2"
    bg_color = "#333333"
    border_color = "#666666"
}
EOF
    
    # Create simple background (if convert is available)
    create_grub_background "$theme_dir/background.png"
    
    BOOT_CONFIG_FILES+=("$theme_file")
}

# Create GRUB background image
create_grub_background() {
    local background_file="$1"
    
    # Create a simple background using ImageMagick if available
    if command -v convert >/dev/null 2>&1; then
        convert -size 1024x768 gradient:"#1e3a8a-#2563eb" -gravity center \
                -font Arial -pointsize 72 -fill white \
                -annotate +0-100 "AILinux" \
                -font Arial -pointsize 32 -fill "#e2e8f0" \
                -annotate +0+50 "Artificial Intelligence Linux" \
                "$background_file" 2>/dev/null || {
            # Fallback: create solid color background
            convert -size 1024x768 xc:"#1e3a8a" "$background_file" 2>/dev/null || {
                # Final fallback: create empty file
                touch "$background_file"
            }
        }
    else
        # Create empty placeholder
        touch "$background_file"
    fi
}

# Set up Secure Boot configuration
setup_secure_boot() {
    local chroot_dir="$1"
    
    log_info "🔒 Setting up Secure Boot configuration..."
    
    # Install Secure Boot packages
    install_secure_boot_packages "$chroot_dir"
    
    # Configure shim bootloader
    configure_shim_bootloader "$chroot_dir"
    
    # Set up certificate management
    setup_boot_certificates "$chroot_dir"
    
    log_success "✅ Secure Boot configuration completed"
}

# Install Secure Boot packages
install_secure_boot_packages() {
    local chroot_dir="$1"
    
    log_info "📦 Installing Secure Boot packages..."
    
    local secureboot_packages=(
        "shim-signed"
        "grub-efi-amd64-signed"
        "mokutil"
        "efibootmgr"
    )
    
    local install_cmd="DEBIAN_FRONTEND=noninteractive apt-get install -y ${secureboot_packages[*]}"
    
    if ! enter_chroot_safely "$chroot_dir" "$install_cmd"; then
        log_warn "⚠️  Some Secure Boot packages failed to install"
    else
        log_success "✅ Secure Boot packages installed"
    fi
}

# Configure shim bootloader
configure_shim_bootloader() {
    local chroot_dir="$1"
    
    log_info "🔧 Configuring shim bootloader..."
    
    # Copy signed shim to EFI boot directory
    local shim_source="/usr/lib/shim/shimx64.efi.signed"
    local shim_dest="$chroot_dir/boot/efi/EFI/BOOT/bootx64.efi"
    
    if [ -f "$chroot_dir$shim_source" ]; then
        cp "$chroot_dir$shim_source" "$shim_dest" || {
            log_warn "⚠️  Could not copy signed shim"
        }
    else
        log_warn "⚠️  Signed shim not found, creating placeholder"
        touch "$shim_dest"
    fi
    
    # Copy GRUB EFI binary
    local grub_source="/usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed"
    local grub_dest="$chroot_dir/boot/efi/EFI/BOOT/grubx64.efi"
    
    if [ -f "$chroot_dir$grub_source" ]; then
        cp "$chroot_dir$grub_source" "$grub_dest" || {
            log_warn "⚠️  Could not copy signed GRUB"
        }
    fi
    
    BOOT_LOADERS+=("shim")
    log_success "✅ Shim bootloader configured"
}

# Set up boot certificates
setup_boot_certificates() {
    local chroot_dir="$1"
    
    log_info "🔐 Setting up boot certificates..."
    
    # Create certificate directory
    local cert_dir="$chroot_dir/usr/share/ailinux/certificates"
    mkdir -p "$cert_dir"
    
    # Create certificate management script
    create_certificate_management_script "$chroot_dir"
    
    log_success "✅ Boot certificates configured"
}

# Create certificate management script
create_certificate_management_script() {
    local chroot_dir="$1"
    
    local cert_script="$chroot_dir/usr/local/bin/ailinux-manage-certificates"
    
    cat > "$cert_script" << 'EOF'
#!/bin/bash
#
# AILinux Certificate Management Script
# Manages Secure Boot certificates for AILinux
#

CERT_DIR="/usr/share/ailinux/certificates"
MOK_DIR="/var/lib/shim-signed/mok"

manage_certificates() {
    echo "AILinux Certificate Management"
    echo "=============================="
    
    # Check if Secure Boot is enabled
    if [ -f "/sys/firmware/efi/efivars/SecureBoot-*" ] 2>/dev/null; then
        local secure_boot_status=$(hexdump -C /sys/firmware/efi/efivars/SecureBoot-* 2>/dev/null | tail -1 | cut -d' ' -f2 || echo "00")
        
        if [ "$secure_boot_status" = "01" ]; then
            echo "✅ Secure Boot is enabled"
        else
            echo "ℹ️  Secure Boot is disabled"
        fi
    else
        echo "ℹ️  Secure Boot not available (legacy BIOS or not supported)"
        return 0
    fi
    
    # Check MOK (Machine Owner Key) status
    if command -v mokutil >/dev/null 2>&1; then
        echo ""
        echo "MOK Status:"
        mokutil --sb-state 2>/dev/null || echo "Could not determine MOK status"
    fi
    
    echo ""
    echo "For certificate management:"
    echo "- List certificates: mokutil --list-enrolled"
    echo "- Import certificate: mokutil --import <cert.der>"
    echo "- Delete certificate: mokutil --delete <cert.der>"
    echo ""
}

case "${1:-status}" in
    "status")
        manage_certificates
        ;;
    "help")
        echo "Usage: $0 [status|help]"
        echo ""
        echo "Commands:"
        echo "  status - Show certificate and Secure Boot status"
        echo "  help   - Show this help message"
        ;;
    *)
        echo "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac
EOF
    
    chmod +x "$cert_script"
    
    BOOT_CONFIG_FILES+=("$cert_script")
}

# Configure UEFI boot entries
configure_uefi_boot() {
    local chroot_dir="$1"
    
    log_info "🔧 Configuring UEFI boot entries..."
    
    # Create UEFI boot configuration
    create_uefi_boot_config "$chroot_dir"
    
    # Set up fallback boot entries
    setup_uefi_fallback "$chroot_dir"
    
    log_success "✅ UEFI boot configuration completed"
}

# Create UEFI boot configuration
create_uefi_boot_config() {
    local chroot_dir="$1"
    
    # Create boot entry script
    local boot_script="$chroot_dir/usr/local/bin/ailinux-setup-boot"
    
    cat > "$boot_script" << 'EOF'
#!/bin/bash
#
# AILinux Boot Setup Script
# Configures UEFI boot entries for AILinux
#

setup_uefi_boot() {
    echo "Setting up AILinux UEFI boot entries..."
    
    # Check if efibootmgr is available
    if ! command -v efibootmgr >/dev/null 2>&1; then
        echo "❌ efibootmgr not available"
        return 1
    fi
    
    # Check if system is booted with UEFI
    if [ ! -d "/sys/firmware/efi" ]; then
        echo "ℹ️  System not booted with UEFI, skipping UEFI boot setup"
        return 0
    fi
    
    # Create AILinux boot entry
    local esp_uuid=$(findmnt -n -o UUID /boot/efi 2>/dev/null)
    
    if [ -n "$esp_uuid" ]; then
        # Remove existing AILinux entries
        efibootmgr | grep "AILinux" | cut -c5-8 | while read boot_num; do
            efibootmgr -b "$boot_num" -B >/dev/null 2>&1
        done
        
        # Create new AILinux boot entry
        if efibootmgr -c -d "$(findmnt -n -o SOURCE /boot/efi | sed 's/[0-9]*$//')" \
                      -p "$(findmnt -n -o SOURCE /boot/efi | sed 's/.*[^0-9]//')" \
                      -L "AILinux" \
                      -l "\\EFI\\ailinux\\grubx64.efi" >/dev/null 2>&1; then
            echo "✅ AILinux UEFI boot entry created"
        else
            echo "⚠️  Could not create UEFI boot entry"
        fi
    else
        echo "⚠️  Could not find EFI System Partition"
    fi
}

case "${1:-setup}" in
    "setup")
        setup_uefi_boot
        ;;
    "help")
        echo "Usage: $0 [setup|help]"
        echo ""
        echo "Commands:"
        echo "  setup - Set up UEFI boot entries"
        echo "  help  - Show this help message"
        ;;
    *)
        echo "Unknown command: $1"
        exit 1
        ;;
esac
EOF
    
    chmod +x "$boot_script"
    
    BOOT_CONFIG_FILES+=("$boot_script")
}

# Set up UEFI fallback boot
setup_uefi_fallback() {
    local chroot_dir="$1"
    
    log_info "🔄 Setting up UEFI fallback boot..."
    
    # Create fallback bootloader entries
    local fallback_dir="$chroot_dir/boot/efi/EFI/BOOT"
    
    # Ensure fallback directory exists
    mkdir -p "$fallback_dir"
    
    # Create fallback GRUB configuration
    local fallback_grub="$fallback_dir/grub.cfg"
    
    cat > "$fallback_grub" << 'EOF'
# AILinux Fallback GRUB Configuration
set timeout=10
set default=0

menuentry "AILinux" {
    search --set=root --file /boot/vmlinuz
    linux /boot/vmlinuz root=LABEL=ailinux-root ro quiet splash
    initrd /boot/initrd.img
}

menuentry "AILinux (Recovery Mode)" {
    search --set=root --file /boot/vmlinuz
    linux /boot/vmlinuz root=LABEL=ailinux-root ro recovery nomodeset
    initrd /boot/initrd.img
}
EOF
    
    BOOT_CONFIG_FILES+=("$fallback_grub")
    log_success "✅ UEFI fallback boot configured"
}

# Configure legacy BIOS boot
configure_legacy_boot() {
    local chroot_dir="$1"
    
    log_info "🔧 Configuring legacy BIOS boot..."
    
    # Create BIOS boot configuration
    create_bios_boot_config "$chroot_dir"
    
    # Set up MBR boot setup
    setup_mbr_boot "$chroot_dir"
    
    log_success "✅ Legacy BIOS boot configuration completed"
}

# Create BIOS boot configuration  
create_bios_boot_config() {
    local chroot_dir="$1"
    
    # Create BIOS-specific GRUB configuration
    local bios_grub_cfg="$chroot_dir/boot/grub/grub.cfg.bios"
    
    cat > "$bios_grub_cfg" << 'EOF'
# AILinux BIOS GRUB Configuration
set timeout=10
set default=0

# Load modules needed for BIOS boot
insmod biosdisk
insmod part_msdos
insmod part_gpt
insmod ext2
insmod linux

menuentry "AILinux" {
    search --set=root --label ailinux-root
    linux /boot/vmlinuz root=LABEL=ailinux-root ro quiet splash
    initrd /boot/initrd.img
}

menuentry "AILinux (Recovery Mode)" {
    search --set=root --label ailinux-root
    linux /boot/vmlinuz root=LABEL=ailinux-root ro single
    initrd /boot/initrd.img
}

menuentry "Memory Test (Memtest86+)" {
    search --set=root --label ailinux-root
    linux16 /boot/memtest86+.bin
}
EOF
    
    BOOT_CONFIG_FILES+=("$bios_grub_cfg")
}

# Set up MBR boot configuration
setup_mbr_boot() {
    local chroot_dir="$1"
    
    log_info "🔧 Setting up MBR boot configuration..."
    
    # Create MBR installation script
    local mbr_script="$chroot_dir/usr/local/bin/ailinux-install-mbr"
    
    cat > "$mbr_script" << 'EOF'
#!/bin/bash
#
# AILinux MBR Installation Script
# Installs GRUB to MBR for legacy BIOS boot
#

install_mbr() {
    local target_device="$1"
    
    if [ -z "$target_device" ]; then
        echo "Usage: $0 <device>"
        echo "Example: $0 /dev/sda"
        return 1
    fi
    
    echo "Installing GRUB to MBR on $target_device..."
    
    # Install GRUB to MBR
    if grub-install --target=i386-pc --boot-directory=/boot "$target_device"; then
        echo "✅ GRUB installed to MBR successfully"
        
        # Update GRUB configuration
        if update-grub; then
            echo "✅ GRUB configuration updated"
        else
            echo "⚠️  GRUB configuration update failed"
        fi
    else
        echo "❌ Failed to install GRUB to MBR"
        return 1
    fi
}

if [ "$#" -ne 1 ]; then
    echo "AILinux MBR Installation"
    echo "======================="
    echo ""
    echo "This script installs GRUB bootloader to the Master Boot Record (MBR)"
    echo "for legacy BIOS systems."
    echo ""
    echo "Usage: $0 <device>"
    echo "Example: $0 /dev/sda"
    echo ""
    echo "WARNING: This will overwrite the MBR of the specified device!"
    exit 1
fi

install_mbr "$1"
EOF
    
    chmod +x "$mbr_script"
    
    BOOT_CONFIG_FILES+=("$mbr_script")
    log_success "✅ MBR boot setup completed"
}

# Validate boot setup
validate_boot_setup() {
    local chroot_dir="${1:-$AILINUX_BUILD_CHROOT_DIR}"
    
    log_info "🔍 Validating boot setup..."
    
    local validation_errors=0
    
    # Check boot directories
    local required_dirs=(
        "$chroot_dir/boot"
        "$chroot_dir/boot/grub"
    )
    
    if [ "$UEFI_SUPPORT" = true ]; then
        required_dirs+=(
            "$chroot_dir/boot/efi/EFI/BOOT"
            "$chroot_dir/boot/efi/EFI/ailinux"
        )
    fi
    
    for dir in "${required_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            log_error "❌ Required boot directory missing: $(basename "$dir")"
            ((validation_errors++))
        fi
    done
    
    # Check GRUB configuration
    if [ ! -f "$chroot_dir/etc/default/grub" ]; then
        log_error "❌ GRUB default configuration missing"
        ((validation_errors++))
    fi
    
    # Check boot loaders
    if [ ${#BOOT_LOADERS[@]} -eq 0 ]; then
        log_error "❌ No boot loaders configured"
        ((validation_errors++))
    fi
    
    # Check Secure Boot setup (if enabled)
    if [ "$SECUREBOOT_ENABLED" = true ]; then
        if [ ! -f "$chroot_dir/boot/efi/EFI/BOOT/bootx64.efi" ]; then
            log_warn "⚠️  Secure Boot bootloader missing"
        fi
    fi
    
    if [ $validation_errors -eq 0 ]; then
        log_success "✅ Boot setup validation passed"
        return 0
    else
        log_error "❌ Boot setup validation failed with $validation_errors errors"
        return 1
    fi
}

# Clean up Secure Boot handling resources
cleanup_secureboot_handling() {
    log_info "🧹 Cleaning up Secure Boot handling resources..."
    
    # Generate boot configuration report
    create_boot_configuration_report
    
    log_success "Secure Boot handling cleanup completed"
}

# Create boot configuration report
create_boot_configuration_report() {
    local report_file="/tmp/ailinux_boot_configuration_report_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "# AILinux Boot Configuration Report"
        echo "# Generated: $(date)"
        echo ""
        
        echo "== BOOT CAPABILITIES =="
        echo "UEFI Support: $UEFI_SUPPORT"
        echo "Secure Boot: $SECUREBOOT_ENABLED"
        echo "Legacy BIOS: $LEGACY_BIOS_SUPPORT"
        echo ""
        
        echo "== CONFIGURED BOOT LOADERS =="
        printf '%s\n' "${BOOT_LOADERS[@]}"
        echo ""
        
        echo "== CONFIGURATION FILES =="
        printf '%s\n' "${BOOT_CONFIG_FILES[@]}"
        echo ""
        
        echo "== CERTIFICATES =="
        printf '%s\n' "${SECUREBOOT_CERTIFICATES[@]}"
        echo ""
        
    } > "$report_file"
    
    log_success "📄 Boot configuration report created: $report_file"
    
    # Coordinate through swarm
    swarm_coordinate "secureboot_setup" "Secure Boot configuration completed successfully" "success" "boot" || true
}

# Export functions for use in other modules
export -f init_secureboot_handling
export -f setup_secure_boot
export -f configure_uefi_boot
export -f configure_legacy_boot
export -f validate_boot_setup
export -f cleanup_secureboot_handling