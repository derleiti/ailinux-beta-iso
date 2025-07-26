#!/bin/bash
#
# Mirror Management Module for AILinux Build Script
# Provides AILinux mirror and GPG key management
#
# This module handles the configuration of AILinux-specific package repositories
# and GPG key management for secure package installation.
#

# Global mirror management configuration
declare -g AILINUX_MIRROR_URL="https://archive.ailinux.me"
declare -g AILINUX_GPG_KEYRING="/usr/share/keyrings/ailinux-keyring.gpg"
declare -g MIRROR_CONFIG_DIR=""
declare -g CONFIGURED_REPOSITORIES=()
declare -g GPG_KEYS_IMPORTED=()

# Initialize mirror management system
init_mirror_management() {
    log_info "🌐 Initializing AILinux mirror management system..."
    
    # Set up mirror configuration
    setup_mirror_configuration
    
    # Configure GPG key management
    configure_gpg_management
    
    # Validate mirror accessibility
    validate_mirror_accessibility
    
    log_success "AILinux mirror management system initialized"
}

# Set up mirror configuration
setup_mirror_configuration() {
    local chroot_dir="${AILINUX_BUILD_CHROOT_DIR:-/tmp/ailinux_chroot}"
    
    MIRROR_CONFIG_DIR="$chroot_dir/etc/apt"
    
    log_info "📁 Setting up mirror configuration directories..."
    
    # Create necessary directories
    local mirror_dirs=(
        "$MIRROR_CONFIG_DIR"
        "$MIRROR_CONFIG_DIR/sources.list.d"
        "$MIRROR_CONFIG_DIR/trusted.gpg.d"
        "$chroot_dir/usr/share/keyrings"
        "$chroot_dir/etc/ailinux"
    )
    
    for dir in "${mirror_dirs[@]}"; do
        if ! mkdir -p "$dir"; then
            log_error "❌ Failed to create mirror directory: $dir"
            return 1
        fi
    done
    
    log_success "✅ Mirror configuration directories created"
}

# Configure GPG key management
configure_gpg_management() {
    log_info "🔐 Configuring GPG key management..."
    
    # Create GPG configuration for AILinux
    local gpg_config_file="$MIRROR_CONFIG_DIR/ailinux-gpg.conf"
    
    cat > "$gpg_config_file" << EOF
# AILinux GPG Configuration
# Generated: $(date)

# AILinux repository GPG key configuration
ailinux_keyring=$AILINUX_GPG_KEYRING
ailinux_key_url=$AILINUX_MIRROR_URL/public.key
ailinux_key_id=AILINUX-REPO-KEY

# GPG verification settings
verify_signatures=true
require_signatures=true
allow_weak_signatures=false
EOF
    
    log_success "✅ GPG key management configured"
}

# Validate mirror accessibility
validate_mirror_accessibility() {
    log_info "🔍 Validating AILinux mirror accessibility..."
    
    # Test main mirror URL
    if wget -q --spider --timeout=10 "$AILINUX_MIRROR_URL" 2>/dev/null; then
        log_success "✅ AILinux main mirror accessible"
        export AILINUX_MIRROR_ACCESSIBLE=true
    else
        log_warn "⚠️  AILinux main mirror not accessible, will use fallback"
        export AILINUX_MIRROR_ACCESSIBLE=false
        
        # Set fallback mirror
        AILINUX_MIRROR_URL="https://packages.ailinux.org"
        
        if wget -q --spider --timeout=10 "$AILINUX_MIRROR_URL" 2>/dev/null; then
            log_success "✅ AILinux fallback mirror accessible"
            export AILINUX_MIRROR_ACCESSIBLE=true
        else
            log_error "❌ No AILinux mirrors accessible"
            export AILINUX_MIRROR_ACCESSIBLE=false
        fi
    fi
    
    # Test package index availability
    if [ "$AILINUX_MIRROR_ACCESSIBLE" = true ]; then
        local release_url="$AILINUX_MIRROR_URL/dists/noble/Release"
        if wget -q --spider --timeout=10 "$release_url" 2>/dev/null; then
            log_success "✅ AILinux package index accessible"
        else
            log_warn "⚠️  AILinux package index not found"
        fi
    fi
}

# Setup AILinux mirror repository
setup_ailinux_mirror() {
    local chroot_dir="${1:-$AILINUX_BUILD_CHROOT_DIR}"
    
    if [ ! -d "$chroot_dir" ]; then
        log_error "❌ Chroot directory not found: $chroot_dir"
        return 1
    fi
    
    log_info "🌐 Setting up AILinux mirror repository..."
    
    # Create AILinux repository configuration
    create_ailinux_repository_config "$chroot_dir"
    
    # Import GPG keys
    import_ailinux_gpg_keys "$chroot_dir"
    
    # Update package lists
    update_repository_lists "$chroot_dir"
    
    log_success "✅ AILinux mirror repository configured"
    
    CONFIGURED_REPOSITORIES+=("ailinux-main")
}

# Create AILinux repository configuration
create_ailinux_repository_config() {
    local chroot_dir="$1"
    
    log_info "📝 Creating AILinux repository configuration..."
    
    # Create main AILinux repository source
    local ailinux_sources="$chroot_dir/etc/apt/sources.list.d/ailinux.list"
    
    if [ "$AILINUX_MIRROR_ACCESSIBLE" = true ]; then
        cat > "$ailinux_sources" << EOF
# AILinux Official Repository
# Added: $(date)
deb [signed-by=$AILINUX_GPG_KEYRING arch=amd64] $AILINUX_MIRROR_URL noble main
deb-src [signed-by=$AILINUX_GPG_KEYRING arch=amd64] $AILINUX_MIRROR_URL noble main

# AILinux Updates Repository  
deb [signed-by=$AILINUX_GPG_KEYRING arch=amd64] $AILINUX_MIRROR_URL noble-updates main
deb-src [signed-by=$AILINUX_GPG_KEYRING arch=amd64] $AILINUX_MIRROR_URL noble-updates main

# AILinux Security Repository
deb [signed-by=$AILINUX_GPG_KEYRING arch=amd64] $AILINUX_MIRROR_URL noble-security main
deb-src [signed-by=$AILINUX_GPG_KEYRING arch=amd64] $AILINUX_MIRROR_URL noble-security main
EOF
    else
        log_warn "⚠️  AILinux mirror not accessible, creating placeholder configuration"
        cat > "$ailinux_sources" << EOF
# AILinux Repository Configuration (Placeholder)
# Mirror not accessible during build - configuration preserved for post-install
# deb [signed-by=$AILINUX_GPG_KEYRING arch=amd64] $AILINUX_MIRROR_URL noble main
# deb-src [signed-by=$AILINUX_GPG_KEYRING arch=amd64] $AILINUX_MIRROR_URL noble main
EOF
    fi
    
    log_success "✅ AILinux repository configuration created"
}

# Import AILinux GPG keys
import_ailinux_gpg_keys() {
    local chroot_dir="$1"
    
    log_info "🔐 Importing AILinux GPG keys..."
    
    # Create AILinux GPG keyring
    local keyring_file="$chroot_dir$AILINUX_GPG_KEYRING"
    
    # Try to download the official AILinux GPG key
    local temp_key="/tmp/ailinux_public_key_$$"
    
    if [ "$AILINUX_MIRROR_ACCESSIBLE" = true ]; then
        if wget -q -O "$temp_key" "$AILINUX_MIRROR_URL/public.key" --timeout=10 2>/dev/null; then
            log_success "✅ AILinux GPG key downloaded"
            
            # Import key into keyring
            if gpg --dearmor < "$temp_key" > "$keyring_file" 2>/dev/null; then
                log_success "✅ AILinux GPG key imported to keyring"
                GPG_KEYS_IMPORTED+=("ailinux-official")
            else
                log_error "❌ Failed to import AILinux GPG key"
                create_placeholder_keyring "$keyring_file"
            fi
            
            rm -f "$temp_key"
        else
            log_warn "⚠️  Could not download AILinux GPG key, creating placeholder"
            create_placeholder_keyring "$keyring_file"
        fi
    else
        log_warn "⚠️  Mirror not accessible, creating placeholder keyring"
        create_placeholder_keyring "$keyring_file"
    fi
    
    # Set proper permissions
    chmod 644 "$keyring_file"
    
    # Create key management script for post-install
    create_key_management_script "$chroot_dir"
}

# Create placeholder keyring when real key is not available
create_placeholder_keyring() {
    local keyring_file="$1"
    
    log_info "📝 Creating placeholder GPG keyring..."
    
    # Create a minimal GPG keyring structure
    # This is a placeholder that can be replaced post-install
    touch "$keyring_file"
    
    # Create a note about the missing key
    cat > "$(dirname "$keyring_file")/ailinux-key-note.txt" << EOF
AILinux GPG Key Placeholder
============================

This keyring file is a placeholder created during the build process.
The actual AILinux GPG key should be installed post-installation.

To manually install the AILinux GPG key:
1. Download: wget -O /tmp/ailinux.key $AILINUX_MIRROR_URL/public.key
2. Import: sudo gpg --dearmor < /tmp/ailinux.key > $AILINUX_GPG_KEYRING
3. Update: sudo apt update

Generated: $(date)
EOF
    
    log_info "📄 Placeholder keyring and instructions created"
}

# Create key management script for post-install setup
create_key_management_script() {
    local chroot_dir="$1"
    
    log_info "📝 Creating key management script..."
    
    local script_file="$chroot_dir/usr/local/bin/ailinux-setup-keys"
    
    cat > "$script_file" << EOF
#!/bin/bash
#
# AILinux GPG Key Setup Script
# Automatically sets up AILinux repository keys
#

AILINUX_MIRROR_URL="$AILINUX_MIRROR_URL"
AILINUX_GPG_KEYRING="$AILINUX_GPG_KEYRING"

setup_ailinux_keys() {
    echo "Setting up AILinux repository keys..."
    
    # Create keyring directory if it doesn't exist
    mkdir -p "\$(dirname "\$AILINUX_GPG_KEYRING")"
    
    # Download and import AILinux GPG key
    local temp_key="/tmp/ailinux_key_\$\$"
    
    if wget -q -O "\$temp_key" "\$AILINUX_MIRROR_URL/public.key" --timeout=15; then
        if gpg --dearmor < "\$temp_key" > "\$AILINUX_GPG_KEYRING"; then
            echo "✅ AILinux GPG key imported successfully"
            chmod 644 "\$AILINUX_GPG_KEYRING"
            
            # Update package lists
            apt update
            echo "✅ Package lists updated"
        else
            echo "❌ Failed to import AILinux GPG key"
            return 1
        fi
        
        rm -f "\$temp_key"
    else
        echo "❌ Could not download AILinux GPG key"
        return 1
    fi
}

# Check if running as root
if [ "\$EUID" -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
fi

# Check if key already exists and is valid
if [ -f "\$AILINUX_GPG_KEYRING" ] && [ -s "\$AILINUX_GPG_KEYRING" ]; then
    echo "AILinux GPG key already exists and appears valid"
    exit 0
fi

# Set up keys
setup_ailinux_keys
EOF
    
    chmod +x "$script_file"
    
    log_success "✅ Key management script created"
}

# Update repository package lists
update_repository_lists() {
    local chroot_dir="$1"
    
    log_info "📦 Updating repository package lists..."
    
    # Update package lists in chroot
    if enter_chroot_safely "$chroot_dir" "apt-get update" 2>/dev/null; then
        log_success "✅ Package lists updated successfully"
    else
        log_warn "⚠️  Package list update had issues (expected if AILinux mirror unavailable)"
    fi
    
    # Check if AILinux packages are available
    if [ "$AILINUX_MIRROR_ACCESSIBLE" = true ]; then
        check_ailinux_packages_availability "$chroot_dir"
    fi
}

# Check availability of AILinux-specific packages
check_ailinux_packages_availability() {
    local chroot_dir="$1"
    
    log_info "🔍 Checking AILinux package availability..."
    
    # List of expected AILinux packages
    local ailinux_packages=(
        "ailinux-base"
        "ailinux-desktop"
        "ailinux-wallpapers"
        "ailinux-welcome"
        "ailinux-tools"
    )
    
    local available_packages=0
    
    for package in "${ailinux_packages[@]}"; do
        if enter_chroot_safely "$chroot_dir" "apt-cache show $package" >/dev/null 2>&1; then
            log_success "✅ Package available: $package"
            ((available_packages++))
        else
            log_warn "⚠️  Package not available: $package"
        fi
    done
    
    log_info "📊 AILinux packages available: $available_packages/${#ailinux_packages[@]}"
    
    if [ $available_packages -eq 0 ]; then
        log_warn "⚠️  No AILinux-specific packages found in repository"
    fi
}

# Configure GPG keys for package verification
configure_gpg_keys() {
    local chroot_dir="${1:-$AILINUX_BUILD_CHROOT_DIR}"
    
    log_info "🔐 Configuring GPG keys for package verification..."
    
    # Set up GPG verification preferences
    local gpg_prefs="$chroot_dir/etc/apt/apt.conf.d/99ailinux-gpg"
    
    cat > "$gpg_prefs" << EOF
// AILinux GPG Configuration
// Generated: $(date)

// Require signature verification for AILinux packages
APT::Get::AllowUnauthenticated "false";
APT::Authentication::TrustCDROM "false";

// GPG key management
Acquire::gpgv::Options {
    "--keyring";
    "$AILINUX_GPG_KEYRING";
};

// Repository specific settings
Acquire::https::archive.ailinux.me::Verify-Peer "true";
Acquire::https::archive.ailinux.me::Verify-Host "true";
EOF
    
    log_success "✅ GPG verification configured"
}

# Validate repository configuration
validate_repository() {
    local chroot_dir="${1:-$AILINUX_BUILD_CHROOT_DIR}"
    
    log_info "🔍 Validating repository configuration..."
    
    local validation_errors=0
    
    # Check if sources.list.d exists
    if [ ! -d "$chroot_dir/etc/apt/sources.list.d" ]; then
        log_error "❌ APT sources directory missing"
        ((validation_errors++))
    fi
    
    # Check if AILinux repository file exists
    if [ ! -f "$chroot_dir/etc/apt/sources.list.d/ailinux.list" ]; then
        log_error "❌ AILinux repository configuration missing"
        ((validation_errors++))
    fi
    
    # Check keyring directory
    if [ ! -d "$chroot_dir/usr/share/keyrings" ]; then
        log_error "❌ GPG keyring directory missing"
        ((validation_errors++))
    fi
    
    # Check if key management script exists
    if [ ! -f "$chroot_dir/usr/local/bin/ailinux-setup-keys" ]; then
        log_error "❌ Key management script missing"
        ((validation_errors++))
    fi
    
    # Test repository accessibility (if possible)
    if [ "$AILINUX_MIRROR_ACCESSIBLE" = true ]; then
        if ! enter_chroot_safely "$chroot_dir" "apt-cache policy" >/dev/null 2>&1; then
            log_warn "⚠️  Repository policy check failed"
        else
            log_success "✅ Repository policy check passed"
        fi
    fi
    
    if [ $validation_errors -eq 0 ]; then
        log_success "✅ Repository configuration validation passed"
        return 0
    else
        log_error "❌ Repository configuration validation failed with $validation_errors errors"
        return 1
    fi
}

# Manage APT sources for optimal performance
manage_sources() {
    local chroot_dir="${1:-$AILINUX_BUILD_CHROOT_DIR}"
    
    log_info "📋 Managing APT sources configuration..."
    
    # Back up original sources.list
    local original_sources="$chroot_dir/etc/apt/sources.list"
    if [ -f "$original_sources" ]; then
        cp "$original_sources" "$original_sources.ailinux.backup"
    fi
    
    # Create optimized sources.list
    create_optimized_sources_list "$chroot_dir"
    
    # Set up source priorities
    setup_source_priorities "$chroot_dir"
    
    log_success "✅ APT sources management completed"
}

# Create optimized sources.list
create_optimized_sources_list() {
    local chroot_dir="$1"
    local sources_file="$chroot_dir/etc/apt/sources.list"
    
    log_info "📝 Creating optimized sources.list..."
    
    cat > "$sources_file" << EOF
# AILinux Optimized Sources List
# Generated: $(date)

# Ubuntu Noble (24.04) repositories
deb http://archive.ubuntu.com/ubuntu/ noble main restricted universe multiverse
deb-src http://archive.ubuntu.com/ubuntu/ noble main restricted universe multiverse

# Ubuntu Noble Updates
deb http://archive.ubuntu.com/ubuntu/ noble-updates main restricted universe multiverse
deb-src http://archive.ubuntu.com/ubuntu/ noble-updates main restricted universe multiverse

# Ubuntu Noble Security
deb http://security.ubuntu.com/ubuntu/ noble-security main restricted universe multiverse
deb-src http://security.ubuntu.com/ubuntu/ noble-security main restricted universe multiverse

# Ubuntu Noble Backports
deb http://archive.ubuntu.com/ubuntu/ noble-backports main restricted universe multiverse
deb-src http://archive.ubuntu.com/ubuntu/ noble-backports main restricted universe multiverse
EOF
    
    log_success "✅ Optimized sources.list created"
}

# Set up source priorities  
setup_source_priorities() {
    local chroot_dir="$1"
    local preferences_file="$chroot_dir/etc/apt/preferences.d/ailinux-priorities"
    
    log_info "⚖️  Setting up source priorities..."
    
    cat > "$preferences_file" << EOF
# AILinux Package Priorities
# Generated: $(date)

# Prefer AILinux packages when available
Package: ailinux-*
Pin: origin archive.ailinux.me
Pin-Priority: 1000

# Standard Ubuntu packages
Package: *
Pin: origin archive.ubuntu.com
Pin-Priority: 500

# Ubuntu security updates
Package: *
Pin: origin security.ubuntu.com
Pin-Priority: 990
EOF
    
    log_success "✅ Source priorities configured"
}

# Clean up mirror management resources
cleanup_mirror_management() {
    log_info "🧹 Cleaning up mirror management resources..."
    
    # Generate mirror management report
    create_mirror_management_report
    
    # Clean up temporary files
    rm -f /tmp/ailinux_public_key_*
    
    log_success "Mirror management cleanup completed"
}

# Create mirror management report
create_mirror_management_report() {
    local report_file="/tmp/ailinux_mirror_management_report_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "# AILinux Mirror Management Report"
        echo "# Generated: $(date)"
        echo ""
        
        echo "== MIRROR CONFIGURATION =="
        echo "Primary Mirror: $AILINUX_MIRROR_URL"
        echo "Mirror Accessible: $AILINUX_MIRROR_ACCESSIBLE"
        echo "GPG Keyring: $AILINUX_GPG_KEYRING"
        echo ""
        
        echo "== CONFIGURED REPOSITORIES =="
        printf '%s\n' "${CONFIGURED_REPOSITORIES[@]}"
        echo ""
        
        echo "== IMPORTED GPG KEYS =="
        printf '%s\n' "${GPG_KEYS_IMPORTED[@]}"
        echo ""
        
        echo "== CONFIGURATION STATUS =="
        if [ "$AILINUX_MIRROR_ACCESSIBLE" = true ]; then
            echo "✅ Mirror accessible and configured"
        else
            echo "⚠️  Mirror not accessible - placeholder configuration created"
        fi
        
    } > "$report_file"
    
    log_success "📄 Mirror management report created: $report_file"
    
    # Coordinate through swarm
    swarm_coordinate "mirror_management" "AILinux mirror configuration completed" "success" "configuration" || true
}

# Export functions for use in other modules
export -f init_mirror_management
export -f setup_ailinux_mirror
export -f configure_gpg_keys
export -f validate_repository
export -f manage_sources
export -f cleanup_mirror_management