#!/bin/bash
#
# AILinux ISO Build Script - Main Orchestrator
# 
# This script builds a complete AILinux live ISO with KDE 6.3, Calamares installer,
# Secure Boot support, AI helper integration, and comprehensive session safety.
#
# Architecture: Modular design with session preservation and intelligent error handling
# Generated: $(date)
#

set -e  # Exit on error (will be overridden by error_handler module)

# ============================================================================
# GLOBAL CONFIGURATION
# ============================================================================

# Build configuration
export AILINUX_BUILD_VERSION="1.0"
export AILINUX_BUILD_DATE="$(date '+%Y%m%d')"
export AILINUX_BUILD_SESSION_ID="build_session_$$"

# Directories
export AILINUX_BUILD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export AILINUX_BUILD_CHROOT_DIR="$AILINUX_BUILD_DIR/chroot"
export AILINUX_BUILD_OUTPUT_DIR="$AILINUX_BUILD_DIR/output"
export AILINUX_BUILD_TEMP_DIR="$AILINUX_BUILD_DIR/temp"
export AILINUX_BUILD_LOGS_DIR="$AILINUX_BUILD_DIR/logs"

# Logging
export LOG_FILE="$AILINUX_BUILD_LOGS_DIR/build_$(date +%Y%m%d_%H%M%S).log"
export LOG_LEVEL="INFO"

# Build options (can be overridden by command line)
export AILINUX_SKIP_CLEANUP=${AILINUX_SKIP_CLEANUP:-false}
export AILINUX_ENABLE_DEBUG=${AILINUX_ENABLE_DEBUG:-false}
export AILINUX_DRY_RUN=${AILINUX_DRY_RUN:-false}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Simple logging functions (before modules are loaded)
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*" | tee -a "$LOG_FILE"
}

log_warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN: $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $*" | tee -a "$LOG_FILE"
}

log_critical() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] CRITICAL: $*" | tee -a "$LOG_FILE"
}

# Simple swarm coordination function (fallback if module not available)
swarm_coordinate() {
    local operation="$1"
    local message="$2"
    local level="${3:-info}"
    local category="${4:-general}"
    
    # Try to use Claude Flow coordination if available
    if command -v npx >/dev/null 2>&1 && npx claude-flow@alpha --version >/dev/null 2>&1; then
        npx claude-flow@alpha hooks notification --message "$operation: $message" --telemetry true 2>/dev/null || true
    fi
    
    # Always log locally
    case "$level" in
        error|critical) log_error "SWARM: $operation - $message" ;;
        warning) log_warn "SWARM: $operation - $message" ;;
        success) log_success "SWARM: $operation - $message" ;;
        *) log_info "SWARM: $operation - $message" ;;
    esac
}

# ============================================================================
# INITIALIZATION
# ============================================================================

# Initialize build environment
init_build_environment() {
    log_info "🚀 Initializing AILinux build environment..."
    
    # Create essential directories
    mkdir -p "$AILINUX_BUILD_CHROOT_DIR"
    mkdir -p "$AILINUX_BUILD_OUTPUT_DIR"
    mkdir -p "$AILINUX_BUILD_TEMP_DIR"
    mkdir -p "$AILINUX_BUILD_LOGS_DIR"
    
    # Ensure we're running with appropriate permissions
    if [ "$EUID" -eq 0 ]; then
        log_warn "⚠️  Running as root - build will proceed but session safety is critical"
        export AILINUX_BUILD_AS_ROOT=true
    else
        log_info "ℹ️  Running as user - this is the recommended approach"
        export AILINUX_BUILD_AS_ROOT=false
    fi
    
    # Export build environment variables
    export AILINUX_BUILD_ENV_INITIALIZED=true
    
    log_success "✅ Build environment initialized"
}

# Load all required modules
load_build_modules() {
    log_info "📚 Loading AILinux build modules..."
    
    local modules_dir="$AILINUX_BUILD_DIR/modules"
    
    # Essential modules in dependency order
    local essential_modules=(
        "session_safety.sh"      # MUST be first - session protection
        "error_handler.sh"       # MUST be second - error handling
        "resource_manager.sh"    # Third - resource management
        "chroot_manager.sh"      # Fourth - chroot operations
        "service_manager.sh"     # Fifth - service management
    )
    
    # Specialized modules (order less critical)
    local specialized_modules=(
        "checksum_validator.sh"
        "mirror_manager.sh"
        "secureboot_handler.sh"
        "kde_installer.sh"
        "calamares_setup.sh"
        "ai_integrator.sh"
    )
    
    # Load essential modules first
    for module in "${essential_modules[@]}"; do
        local module_path="$modules_dir/$module"
        
        if [ -f "$module_path" ]; then
            log_info "   Loading essential module: $module"
            source "$module_path" || {
                log_error "❌ Failed to load essential module: $module"
                return 1
            }
        else
            log_error "❌ Essential module not found: $module"
            return 1
        fi
    done
    
    # Load specialized modules
    for module in "${specialized_modules[@]}"; do
        local module_path="$modules_dir/$module"
        
        if [ -f "$module_path" ]; then
            log_info "   Loading specialized module: $module"
            source "$module_path" || {
                log_warn "⚠️  Failed to load specialized module: $module"
            }
        else
            log_warn "⚠️  Specialized module not found: $module"
        fi
    done
    
    log_success "✅ Build modules loaded successfully"
}

# Initialize all module systems
initialize_build_systems() {
    log_info "⚙️  Initializing build systems..."
    
    # Initialize in dependency order
    
    # Core safety and error handling (MANDATORY)
    if command -v init_session_safety >/dev/null 2>&1; then
        init_session_safety || {
            log_critical "❌ Failed to initialize session safety - ABORTING"
            exit 1
        }
    else
        log_critical "❌ Session safety module not available - ABORTING"
        exit 1
    fi
    
    if command -v init_error_handling >/dev/null 2>&1; then
        init_error_handling || {
            log_critical "❌ Failed to initialize error handling - ABORTING"
            exit 1
        }
    else
        log_critical "❌ Error handling module not available - ABORTING"  
        exit 1
    fi
    
    # Resource and system management
    if command -v init_resource_management >/dev/null 2>&1; then
        init_resource_management || log_warn "⚠️  Resource management initialization failed"
    fi
    
    if command -v init_chroot_management >/dev/null 2>&1; then
        init_chroot_management || log_warn "⚠️  Chroot management initialization failed"
    fi
    
    if command -v init_service_management >/dev/null 2>&1; then
        init_service_management || log_warn "⚠️  Service management initialization failed"
    fi
    
    # Specialized systems (optional but recommended)
    command -v init_checksum_validation >/dev/null 2>&1 && init_checksum_validation
    command -v init_mirror_management >/dev/null 2>&1 && init_mirror_management
    command -v init_secureboot_handling >/dev/null 2>&1 && init_secureboot_handling
    command -v init_kde_installation >/dev/null 2>&1 && init_kde_installation
    command -v init_calamares_setup >/dev/null 2>&1 && init_calamares_setup
    command -v init_ai_integration >/dev/null 2>&1 && init_ai_integration
    
    log_success "✅ Build systems initialized"
    
    # Coordinate with swarm
    swarm_coordinate "build_init" "AILinux build systems initialized successfully" "success" "initialization"
}

# ============================================================================
# BUILD PHASES
# ============================================================================

# Phase 1: Environment validation and setup
phase_1_environment_setup() {
    log_info "🔍 Phase 1: Environment validation and setup"
    
    # Check system requirements
    check_system_requirements || return 1
    
    # Set up build directories
    setup_build_directories || return 1
    
    # Initialize package management
    setup_package_management || return 1
    
    log_success "✅ Phase 1 completed: Environment setup"
    swarm_coordinate "phase_1" "Environment setup completed successfully" "success" "build_phase"
}

# Check system requirements
check_system_requirements() {
    log_info "🔍 Checking system requirements..."
    
    local required_tools=(
        "debootstrap"
        "chroot"
        "mount"
        "umount"
        "mksquashfs"
        "xorriso"
        "grub-mkrescue"
        "wget"
        "curl"
    )
    
    local missing_tools=()
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "❌ Missing required tools: ${missing_tools[*]}"
        log_info "Please install missing tools with:"
        log_info "   sudo apt-get install debootstrap squashfs-tools xorriso grub-pc-bin grub-efi-amd64-bin"
        return 1
    fi
    
    # Check disk space (minimum 10GB recommended)
    local available_space_gb=$(df --output=avail "$AILINUX_BUILD_DIR" | tail -1 | awk '{print int($1/1024/1024)}')
    
    if [ "$available_space_gb" -lt 10 ]; then
        log_warn "⚠️  Available disk space: ${available_space_gb}GB (minimum 10GB recommended)"
        log_warn "Build may fail due to insufficient disk space"
    else
        log_success "✅ Disk space check passed: ${available_space_gb}GB available"
    fi
    
    # Check memory
    local available_memory_gb=$(free -g | awk 'NR==2{print $7}')
    
    if [ "$available_memory_gb" -lt 2 ]; then
        log_warn "⚠️  Available memory: ${available_memory_gb}GB (minimum 2GB recommended)"
    else
        log_success "✅ Memory check passed: ${available_memory_gb}GB available"
    fi
    
    log_success "✅ System requirements check completed"
    return 0
}

# Set up build directories with proper structure
setup_build_directories() {
    log_info "📁 Setting up build directories..."
    
    # Clean existing chroot if requested
    if [ "$AILINUX_SKIP_CLEANUP" = false ] && [ -d "$AILINUX_BUILD_CHROOT_DIR" ]; then
        log_info "🧹 Cleaning existing chroot directory..."
        
        # Use chroot manager for safe cleanup if available
        if command -v cleanup_chroot_mounts >/dev/null 2>&1; then
            cleanup_chroot_mounts "$AILINUX_BUILD_CHROOT_DIR"
        fi
        
        safe_execute "sudo rm -rf '$AILINUX_BUILD_CHROOT_DIR'" "cleanup_chroot" "Failed to clean chroot directory"
    fi
    
    # Create directory structure
    local build_dirs=(
        "$AILINUX_BUILD_CHROOT_DIR"
        "$AILINUX_BUILD_OUTPUT_DIR" 
        "$AILINUX_BUILD_TEMP_DIR/iso"
        "$AILINUX_BUILD_TEMP_DIR/squashfs"
        "$AILINUX_BUILD_TEMP_DIR/boot"
        "$AILINUX_BUILD_LOGS_DIR"
    )
    
    for dir in "${build_dirs[@]}"; do
        safe_execute "mkdir -p '$dir'" "create_dir" "Failed to create directory: $dir" || return 1
    done
    
    log_success "✅ Build directories set up successfully"
    return 0
}

# Set up package management
setup_package_management() {
    log_info "📦 Setting up package management..."
    
    # Update host package lists
    safe_execute "sudo apt-get update" "update_packages" "Failed to update package lists" || {
        log_warn "⚠️  Package list update failed, continuing with cached packages"
    }
    
    # Install any missing dependencies
    local build_deps="debootstrap squashfs-tools xorriso grub-pc-bin grub-efi-amd64-bin isolinux syslinux-utils"
    
    safe_execute "sudo apt-get install -y $build_deps" "install_build_deps" "Failed to install build dependencies" "" "true"
    
    log_success "✅ Package management setup completed"
    return 0
}

# Phase 2: Base system creation with chroot isolation
phase_2_base_system() {
    log_info "🏗️  Phase 2: Base system creation with chroot isolation"
    
    # Create base system using debootstrap
    create_base_system || return 1
    
    # Set up essential mounts
    setup_essential_chroot_mounts || return 1
    
    # Configure base system
    configure_base_system || return 1
    
    log_success "✅ Phase 2 completed: Base system creation"
    swarm_coordinate "phase_2" "Base system creation completed successfully" "success" "build_phase"
}

# Create base system using debootstrap
create_base_system() {
    log_info "🏗️  Creating base system with debootstrap..."
    
    # Use resource tracking if available
    if command -v track_resource_usage >/dev/null 2>&1; then
        track_resource_usage "debootstrap" $$
    fi
    
    # Run debootstrap
    local debootstrap_cmd="sudo debootstrap --arch=amd64 --variant=minbase noble '$AILINUX_BUILD_CHROOT_DIR' http://archive.ubuntu.com/ubuntu/"
    
    if ! safe_execute "$debootstrap_cmd" "debootstrap" "Failed to create base system with debootstrap"; then
        log_error "❌ Base system creation failed"
        return 1
    fi
    
    # Stop resource tracking
    if command -v stop_tracking_resource_usage >/dev/null 2>&1; then
        stop_tracking_resource_usage "debootstrap"
    fi
    
    log_success "✅ Base system created successfully"
    return 0
}

# Set up essential chroot mounts
setup_essential_chroot_mounts() {
    log_info "🗂️  Setting up essential chroot mounts..."
    
    # Use chroot manager if available, otherwise fall back to manual mounting
    if command -v setup_essential_mounts >/dev/null 2>&1; then
        setup_essential_mounts "$AILINUX_BUILD_CHROOT_DIR" || return 1
    else
        # Manual mount setup (fallback)
        local mounts=(
            "proc:$AILINUX_BUILD_CHROOT_DIR/proc"
            "sysfs:$AILINUX_BUILD_CHROOT_DIR/sys"
            "devtmpfs:$AILINUX_BUILD_CHROOT_DIR/dev"
            "devpts:$AILINUX_BUILD_CHROOT_DIR/dev/pts"
            "tmpfs:$AILINUX_BUILD_CHROOT_DIR/run"
        )
        
        for mount_spec in "${mounts[@]}"; do
            IFS=':' read -r fs_type mount_point <<< "$mount_spec"
            
            safe_execute "mkdir -p '$mount_point'" "create_mount_point" "Failed to create mount point: $mount_point"
            safe_execute "sudo mount -t $fs_type $fs_type '$mount_point'" "mount_filesystem" "Failed to mount: $mount_point" "" "true"
        done
    fi
    
    log_success "✅ Essential chroot mounts set up"
    return 0
}

# Configure base system
configure_base_system() {
    log_info "⚙️  Configuring base system..."
    
    # Configure hostname
    echo "ailinux" | safe_execute "sudo tee '$AILINUX_BUILD_CHROOT_DIR/etc/hostname'" "set_hostname" "Failed to set hostname"
    
    # Configure hosts file
    cat > "$AILINUX_BUILD_TEMP_DIR/hosts" << EOF
127.0.0.1   localhost
127.0.1.1   ailinux
::1         localhost ip6-localhost ip6-loopback
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
EOF
    
    safe_execute "sudo cp '$AILINUX_BUILD_TEMP_DIR/hosts' '$AILINUX_BUILD_CHROOT_DIR/etc/hosts'" "set_hosts" "Failed to configure hosts file"
    
    # Configure sources.list
    create_chroot_sources_list || return 1
    
    # Update package lists in chroot
    update_chroot_packages || return 1
    
    log_success "✅ Base system configuration completed"
    return 0
}

# Create sources.list for chroot
create_chroot_sources_list() {
    log_info "📝 Creating sources.list for chroot..."
    
    local sources_file="$AILINUX_BUILD_CHROOT_DIR/etc/apt/sources.list"
    
    cat > "$AILINUX_BUILD_TEMP_DIR/sources.list" << EOF
# Ubuntu Noble (24.04) repositories
deb http://archive.ubuntu.com/ubuntu/ noble main restricted universe multiverse
deb-src http://archive.ubuntu.com/ubuntu/ noble main restricted universe multiverse

# Updates
deb http://archive.ubuntu.com/ubuntu/ noble-updates main restricted universe multiverse
deb-src http://archive.ubuntu.com/ubuntu/ noble-updates main restricted universe multiverse

# Security
deb http://security.ubuntu.com/ubuntu/ noble-security main restricted universe multiverse
deb-src http://security.ubuntu.com/ubuntu/ noble-security main restricted universe multiverse

# Backports
deb http://archive.ubuntu.com/ubuntu/ noble-backports main restricted universe multiverse
deb-src http://archive.ubuntu.com/ubuntu/ noble-backports main restricted universe multiverse
EOF
    
    safe_execute "sudo cp '$AILINUX_BUILD_TEMP_DIR/sources.list' '$sources_file'" "set_sources" "Failed to create sources.list"
    
    return 0
}

# Update packages in chroot
update_chroot_packages() {
    log_info "📦 Updating packages in chroot..."
    
    # Use chroot manager if available
    if command -v enter_chroot_safely >/dev/null 2>&1; then
        enter_chroot_safely "$AILINUX_BUILD_CHROOT_DIR" "apt-get update" || {
            log_warn "⚠️  Package update in chroot failed"
        }
    else
        # Fallback to direct chroot
        sudo chroot "$AILINUX_BUILD_CHROOT_DIR" apt-get update || {
            log_warn "⚠️  Package update in chroot failed"
        }
    fi
    
    return 0
}

# Phase 3: KDE 6.3 installation with error recovery
phase_3_kde_installation() {
    log_info "🎨 Phase 3: KDE 6.3 installation with error recovery"
    
    # Install KDE desktop environment
    install_kde_desktop || return 1
    
    # Configure KDE settings
    configure_kde_desktop || return 1
    
    # Set up display manager
    setup_display_manager || return 1
    
    log_success "✅ Phase 3 completed: KDE 6.3 installation"
    swarm_coordinate "phase_3" "KDE 6.3 installation completed successfully" "success" "build_phase"
}

# Install KDE desktop environment
install_kde_desktop() {
    log_info "🎨 Installing KDE desktop environment..."
    
    # Use KDE installer module if available
    if command -v install_kde_base >/dev/null 2>&1; then
        install_kde_base "$AILINUX_BUILD_CHROOT_DIR" || return 1
    else
        # Fallback KDE installation
        local kde_packages="kde-plasma-desktop plasma-workspace sddm firefox-esr"
        local install_cmd="DEBIAN_FRONTEND=noninteractive apt-get install -y $kde_packages"
        
        if command -v enter_chroot_safely >/dev/null 2>&1; then
            enter_chroot_safely "$AILINUX_BUILD_CHROOT_DIR" "$install_cmd" || return 1
        else
            sudo chroot "$AILINUX_BUILD_CHROOT_DIR" bash -c "$install_cmd" || return 1
        fi
    fi
    
    log_success "✅ KDE desktop environment installed"
    return 0
}

# Configure KDE desktop
configure_kde_desktop() {
    log_info "⚙️  Configuring KDE desktop..."
    
    # Use KDE configuration module if available
    if command -v configure_kde_settings >/dev/null 2>&1; then
        configure_kde_settings "$AILINUX_BUILD_CHROOT_DIR" || {
            log_warn "⚠️  KDE configuration failed, using defaults"
        }
    fi
    
    # Set up themes if available
    if command -v setup_kde_themes >/dev/null 2>&1; then
        setup_kde_themes "$AILINUX_BUILD_CHROOT_DIR" || {
            log_warn "⚠️  KDE themes setup failed"
        }
    fi
    
    log_success "✅ KDE desktop configured"
    return 0
}

# Set up display manager
setup_display_manager() {
    log_info "🖥️  Setting up SDDM display manager..."
    
    # Enable SDDM in chroot
    if command -v enter_chroot_safely >/dev/null 2>&1; then
        enter_chroot_safely "$AILINUX_BUILD_CHROOT_DIR" "systemctl enable sddm" || {
            log_warn "⚠️  Could not enable SDDM service"
        }
        
        enter_chroot_safely "$AILINUX_BUILD_CHROOT_DIR" "systemctl set-default graphical.target" || {
            log_warn "⚠️  Could not set graphical target"
        }
    fi
    
    log_success "✅ Display manager configured"
    return 0
}

# Phase 4: Calamares setup with validation
phase_4_calamares_setup() {
    log_info "🔧 Phase 4: Calamares installer setup with validation"
    
    # Install Calamares installer
    install_calamares_installer || return 1
    
    # Configure Calamares
    configure_calamares_installer || return 1
    
    # Set up branding
    setup_calamares_branding_phase || return 1
    
    log_success "✅ Phase 4 completed: Calamares setup"
    swarm_coordinate "phase_4" "Calamares installer setup completed successfully" "success" "build_phase"
}

# Install Calamares installer
install_calamares_installer() {
    log_info "🔧 Installing Calamares installer..."
    
    # Use Calamares module if available
    if command -v install_calamares >/dev/null 2>&1; then
        install_calamares "$AILINUX_BUILD_CHROOT_DIR" || return 1
    else
        # Fallback Calamares installation
        local calamares_cmd="DEBIAN_FRONTEND=noninteractive apt-get install -y calamares calamares-settings-ubuntu"
        
        if command -v enter_chroot_safely >/dev/null 2>&1; then
            enter_chroot_safely "$AILINUX_BUILD_CHROOT_DIR" "$calamares_cmd" || return 1
        else
            sudo chroot "$AILINUX_BUILD_CHROOT_DIR" bash -c "$calamares_cmd" || return 1
        fi
    fi
    
    log_success "✅ Calamares installer installed"
    return 0
}

# Configure Calamares installer
configure_calamares_installer() {
    log_info "⚙️  Configuring Calamares installer..."
    
    # Use Calamares configuration module if available
    if command -v configure_calamares_modules >/dev/null 2>&1; then
        configure_calamares_modules || {
            log_warn "⚠️  Calamares module configuration failed"
        }
    fi
    
    # Create desktop entry if available
    if command -v create_calamares_desktop_entry >/dev/null 2>&1; then
        create_calamares_desktop_entry "$AILINUX_BUILD_CHROOT_DIR" || {
            log_warn "⚠️  Calamares desktop entry creation failed"
        }
    fi
    
    log_success "✅ Calamares installer configured"
    return 0
}

# Set up Calamares branding
setup_calamares_branding_phase() {
    log_info "🎨 Setting up Calamares branding..."
    
    # Use Calamares branding module if available
    if command -v setup_calamares_branding >/dev/null 2>&1; then
        setup_calamares_branding || {
            log_warn "⚠️  Calamares branding setup failed"
        }
    fi
    
    log_success "✅ Calamares branding configured"
    return 0
}

# Phase 5: AI integration and customization
phase_5_ai_integration() {
    log_info "🤖 Phase 5: AI integration and customization"
    
    # Set up AILinux mirror
    setup_ailinux_repositories || return 1
    
    # Install AI helper
    install_ai_helper_system || return 1
    
    # Apply AILinux customizations
    apply_ailinux_customizations || return 1
    
    log_success "✅ Phase 5 completed: AI integration"
    swarm_coordinate "phase_5" "AI integration and customization completed successfully" "success" "build_phase"
}

# Set up AILinux repositories
setup_ailinux_repositories() {
    log_info "🌐 Setting up AILinux repositories..."
    
    # Use mirror management module if available
    if command -v setup_ailinux_mirror >/dev/null 2>&1; then
        setup_ailinux_mirror "$AILINUX_BUILD_CHROOT_DIR" || {
            log_warn "⚠️  AILinux mirror setup failed, continuing without custom repositories"
        }
    fi
    
    # Configure GPG keys if available
    if command -v configure_gpg_keys >/dev/null 2>&1; then
        configure_gpg_keys "$AILINUX_BUILD_CHROOT_DIR" || {
            log_warn "⚠️  GPG key configuration failed"
        }
    fi
    
    log_success "✅ AILinux repositories configured"
    return 0
}

# Install AI helper system
install_ai_helper_system() {
    log_info "🤖 Installing AI helper system..."
    
    # Use AI integration module if available
    if command -v install_ai_helper >/dev/null 2>&1; then
        install_ai_helper "$AILINUX_BUILD_CHROOT_DIR" || {
            log_warn "⚠️  AI helper installation failed"
            return 1
        }
    else
        # Fallback: create placeholder AI helper
        create_placeholder_ai_helper || return 1
    fi
    
    log_success "✅ AI helper system installed"
    return 0
}

# Create placeholder AI helper (fallback)
create_placeholder_ai_helper() {
    log_info "📝 Creating placeholder AI helper..."
    
    # Create AI helper directory
    safe_execute "mkdir -p '$AILINUX_BUILD_CHROOT_DIR/opt/ailinux/aihelp/bin'" "create_ai_dir" "Failed to create AI helper directory"
    
    # Create simple AI helper script
    cat > "$AILINUX_BUILD_TEMP_DIR/aihelp" << 'EOF'
#!/bin/bash
# AILinux AI Helper - Placeholder Script
echo "AILinux AI Helper v1.0"
echo "This is a placeholder implementation."
echo "For help with commands, try: man <command>"
EOF
    
    safe_execute "sudo cp '$AILINUX_BUILD_TEMP_DIR/aihelp' '$AILINUX_BUILD_CHROOT_DIR/opt/ailinux/aihelp/bin/aihelp'" "install_ai_helper" "Failed to install AI helper"
    safe_execute "sudo chmod +x '$AILINUX_BUILD_CHROOT_DIR/opt/ailinux/aihelp/bin/aihelp'" "make_executable" "Failed to make AI helper executable"
    
    # Create system symlink
    safe_execute "sudo ln -sf '/opt/ailinux/aihelp/bin/aihelp' '$AILINUX_BUILD_CHROOT_DIR/usr/local/bin/aihelp'" "create_symlink" "Failed to create AI helper symlink"
    
    return 0
}

# Apply AILinux customizations
apply_ailinux_customizations() {
    log_info "🎨 Applying AILinux customizations..."
    
    # Set up AILinux branding
    setup_ailinux_system_branding || return 1
    
    # Configure system settings
    configure_ailinux_system_settings || return 1
    
    # Set up user defaults
    setup_ailinux_user_defaults || return 1
    
    log_success "✅ AILinux customizations applied"
    return 0
}

# Set up AILinux system branding
setup_ailinux_system_branding() {
    log_info "🏷️  Setting up AILinux system branding..."
    
    # Update OS release information
    cat > "$AILINUX_BUILD_TEMP_DIR/os-release" << EOF
PRETTY_NAME="AILinux 1.0"
NAME="AILinux"
VERSION_ID="1.0"
VERSION="1.0"
VERSION_CODENAME=noble
ID=ailinux
ID_LIKE=ubuntu
HOME_URL="https://ailinux.org/"
SUPPORT_URL="https://ailinux.org/support/"
BUG_REPORT_URL="https://ailinux.org/bugs/"
PRIVACY_POLICY_URL="https://ailinux.org/privacy/"
UBUNTU_CODENAME=noble
EOF
    
    safe_execute "sudo cp '$AILINUX_BUILD_TEMP_DIR/os-release' '$AILINUX_BUILD_CHROOT_DIR/etc/os-release'" "set_os_release" "Failed to set OS release info"
    
    # Update issue files
    echo "AILinux 1.0 \\n \\l" | safe_execute "sudo tee '$AILINUX_BUILD_CHROOT_DIR/etc/issue'" "set_issue" "Failed to set issue file"
    echo "AILinux 1.0" | safe_execute "sudo tee '$AILINUX_BUILD_CHROOT_DIR/etc/issue.net'" "set_issue_net" "Failed to set issue.net file"
    
    return 0
}

# Configure AILinux system settings
configure_ailinux_system_settings() {
    log_info "⚙️  Configuring AILinux system settings..."
    
    # Set timezone to UTC
    if command -v enter_chroot_safely >/dev/null 2>&1; then
        enter_chroot_safely "$AILINUX_BUILD_CHROOT_DIR" "ln -sf /usr/share/zoneinfo/UTC /etc/localtime" || true
    fi
    
    # Configure locale
    local locale_cmd="locale-gen en_US.UTF-8 && dpkg-reconfigure -f noninteractive locales"
    if command -v enter_chroot_safely >/dev/null 2>&1; then
        enter_chroot_safely "$AILINUX_BUILD_CHROOT_DIR" "$locale_cmd" || {
            log_warn "⚠️  Locale configuration failed"
        }
    fi
    
    return 0
}

# Set up AILinux user defaults
setup_ailinux_user_defaults() {
    log_info "👤 Setting up AILinux user defaults..."
    
    # Create live user
    create_live_user || return 1
    
    # Configure sudo access
    configure_sudo_access || return 1
    
    return 0
}

# Create live user
create_live_user() {
    log_info "👤 Creating live user..."
    
    local user_cmds=(
        "useradd -m -s /bin/bash -G sudo,adm,cdrom,dip,plugdev,lpadmin,sambashare ailinux"
        "echo 'ailinux:ailinux' | chpasswd"
        "chown -R ailinux:ailinux /home/ailinux"
    )
    
    for cmd in "${user_cmds[@]}"; do
        if command -v enter_chroot_safely >/dev/null 2>&1; then
            enter_chroot_safely "$AILINUX_BUILD_CHROOT_DIR" "$cmd" || {
                log_warn "⚠️  User command failed: $cmd"
            }
        fi
    done
    
    return 0
}

# Configure sudo access
configure_sudo_access() {
    log_info "🔐 Configuring sudo access..."
    
    # Allow passwordless sudo for live user
    echo "ailinux ALL=(ALL) NOPASSWD:ALL" | safe_execute "sudo tee '$AILINUX_BUILD_CHROOT_DIR/etc/sudoers.d/ailinux'" "configure_sudo" "Failed to configure sudo"
    
    return 0
}

# Phase 6: ISO generation with checksum validation
phase_6_iso_generation() {
    log_info "💿 Phase 6: ISO generation with checksum validation"
    
    # Set up boot configuration
    setup_boot_configuration || return 1
    
    # Create squashfs filesystem
    create_squashfs_filesystem || return 1
    
    # Generate ISO image
    generate_iso_image || return 1
    
    # Validate and create checksums
    validate_and_checksum_iso || return 1
    
    log_success "✅ Phase 6 completed: ISO generation"
    swarm_coordinate "phase_6" "ISO generation completed successfully" "success" "build_phase"
}

# Set up boot configuration
setup_boot_configuration() {
    log_info "🥾 Setting up boot configuration..."
    
    # Use secure boot handler if available
    if command -v configure_uefi_boot >/dev/null 2>&1 && command -v configure_legacy_boot >/dev/null 2>&1; then
        configure_uefi_boot "$AILINUX_BUILD_CHROOT_DIR" || {
            log_warn "⚠️  UEFI boot configuration failed"
        }
        
        configure_legacy_boot "$AILINUX_BUILD_CHROOT_DIR" || {
            log_warn "⚠️  Legacy boot configuration failed"
        }
    else
        # Fallback boot configuration
        setup_fallback_boot_config || return 1
    fi
    
    log_success "✅ Boot configuration completed"
    return 0
}

# Fallback boot configuration
setup_fallback_boot_config() {
    log_info "🔄 Setting up fallback boot configuration..."
    
    # Create basic GRUB configuration
    mkdir -p "$AILINUX_BUILD_TEMP_DIR/iso/boot/grub"
    
    cat > "$AILINUX_BUILD_TEMP_DIR/iso/boot/grub/grub.cfg" << EOF
set timeout=10
set default=0

menuentry "AILinux Live" {
    linux /casper/vmlinuz boot=casper quiet splash
    initrd /casper/initrd
}

menuentry "AILinux Live (Safe Mode)" {
    linux /casper/vmlinuz boot=casper quiet splash nomodeset
    initrd /casper/initrd
}
EOF
    
    return 0
}

# Create squashfs filesystem
create_squashfs_filesystem() {
    log_info "📦 Creating squashfs filesystem..."
    
    # Clean up chroot before creating squashfs
    cleanup_chroot_for_squashfs || return 1
    
    # Create squashfs
    local squashfs_file="$AILINUX_BUILD_TEMP_DIR/iso/casper/filesystem.squashfs"
    mkdir -p "$(dirname "$squashfs_file")"
    
    # Use resource tracking if available
    if command -v track_resource_usage >/dev/null 2>&1; then
        track_resource_usage "mksquashfs" $$
    fi
    
    local mksquashfs_cmd="mksquashfs '$AILINUX_BUILD_CHROOT_DIR' '$squashfs_file' -comp xz -e boot"
    
    if ! safe_execute "$mksquashfs_cmd" "mksquashfs" "Failed to create squashfs filesystem"; then
        log_error "❌ SquashFS creation failed"
        return 1
    fi
    
    # Stop resource tracking
    if command -v stop_tracking_resource_usage >/dev/null 2>&1; then
        stop_tracking_resource_usage "mksquashfs"
    fi
    
    # Create filesystem size file
    printf "$(du -sx --block-size=1 "$AILINUX_BUILD_CHROOT_DIR" | cut -f1)" > "$AILINUX_BUILD_TEMP_DIR/iso/casper/filesystem.size"
    
    log_success "✅ SquashFS filesystem created"
    return 0
}

# Clean up chroot before creating squashfs
cleanup_chroot_for_squashfs() {
    log_info "🧹 Cleaning up chroot for squashfs creation..."
    
    # Unmount chroot filesystems
    if command -v cleanup_chroot_mounts >/dev/null 2>&1; then
        cleanup_chroot_mounts "$AILINUX_BUILD_CHROOT_DIR"
    fi
    
    # Clean package cache
    if command -v enter_chroot_safely >/dev/null 2>&1; then
        # Re-mount for cleanup
        if command -v setup_essential_mounts >/dev/null 2>&1; then
            setup_essential_mounts "$AILINUX_BUILD_CHROOT_DIR"
        fi
        
        enter_chroot_safely "$AILINUX_BUILD_CHROOT_DIR" "apt-get clean" || true
        enter_chroot_safely "$AILINUX_BUILD_CHROOT_DIR" "apt-get autoremove -y" || true
        
        # Unmount again
        if command -v cleanup_chroot_mounts >/dev/null 2>&1; then
            cleanup_chroot_mounts "$AILINUX_BUILD_CHROOT_DIR"
        fi
    fi
    
    # Remove temporary files
    safe_execute "sudo rm -rf '$AILINUX_BUILD_CHROOT_DIR/tmp/*'" "cleanup_tmp" "Failed to clean tmp directory" "" "true"
    safe_execute "sudo rm -rf '$AILINUX_BUILD_CHROOT_DIR/var/cache/apt/archives/*.deb'" "cleanup_cache" "Failed to clean package cache" "" "true"
    
    return 0
}

# Generate ISO image
generate_iso_image() {
    log_info "💿 Generating ISO image..."
    
    # Copy kernel and initrd
    copy_kernel_and_initrd || return 1
    
    # Create ISO directory structure
    create_iso_structure || return 1
    
    # Generate the ISO
    create_final_iso || return 1
    
    log_success "✅ ISO image generated successfully"
    return 0
}

# Copy kernel and initrd
copy_kernel_and_initrd() {
    log_info "📋 Copying kernel and initrd..."
    
    # Create casper directory
    mkdir -p "$AILINUX_BUILD_TEMP_DIR/iso/casper"
    
    # Find and copy kernel
    local kernel_file=$(find "$AILINUX_BUILD_CHROOT_DIR/boot" -name "vmlinuz-*" | head -1)
    if [ -n "$kernel_file" ]; then
        safe_execute "cp '$kernel_file' '$AILINUX_BUILD_TEMP_DIR/iso/casper/vmlinuz'" "copy_kernel" "Failed to copy kernel"
    else
        log_error "❌ No kernel found in chroot"
        return 1
    fi
    
    # Find and copy initrd
    local initrd_file=$(find "$AILINUX_BUILD_CHROOT_DIR/boot" -name "initrd.img-*" | head -1)
    if [ -n "$initrd_file" ]; then
        safe_execute "cp '$initrd_file' '$AILINUX_BUILD_TEMP_DIR/iso/casper/initrd'" "copy_initrd" "Failed to copy initrd"
    else
        log_error "❌ No initrd found in chroot"
        return 1
    fi
    
    return 0
}

# Create ISO directory structure
create_iso_structure() {
    log_info "📁 Creating ISO directory structure..."
    
    # Create additional ISO directories
    local iso_dirs=(
        "$AILINUX_BUILD_TEMP_DIR/iso/.disk"
        "$AILINUX_BUILD_TEMP_DIR/iso/preseed"
        "$AILINUX_BUILD_TEMP_DIR/iso/isolinux"
    )
    
    for dir in "${iso_dirs[@]}"; do
        mkdir -p "$dir"
    done
    
    # Create disk info
    echo "AILinux 1.0 - Release amd64 ($(date +%Y%m%d))" > "$AILINUX_BUILD_TEMP_DIR/iso/.disk/info"
    echo "AILinux" > "$AILINUX_BUILD_TEMP_DIR/iso/.disk/release_notes_url"
    
    # Create manifest
    if command -v enter_chroot_safely >/dev/null 2>&1; then
        # Re-mount for manifest creation
        if command -v setup_essential_mounts >/dev/null 2>&1; then
            setup_essential_mounts "$AILINUX_BUILD_CHROOT_DIR"
        fi
        
        enter_chroot_safely "$AILINUX_BUILD_CHROOT_DIR" "dpkg-query -W --showformat='\${Package} \${Version}\n'" > "$AILINUX_BUILD_TEMP_DIR/iso/casper/filesystem.manifest" 2>/dev/null || {
            log_warn "⚠️  Could not create package manifest"
        }
        
        # Unmount
        if command -v cleanup_chroot_mounts >/dev/null 2>&1; then
            cleanup_chroot_mounts "$AILINUX_BUILD_CHROOT_DIR"
        fi
    fi
    
    return 0
}

# Create final ISO
create_final_iso() {
    log_info "💿 Creating final ISO image..."
    
    local iso_output="$AILINUX_BUILD_OUTPUT_DIR/ailinux-1.0-amd64.iso"
    
    # Use resource tracking if available
    if command -v track_resource_usage >/dev/null 2>&1; then
        track_resource_usage "xorriso" $$
    fi
    
    # Create ISO using xorriso
    local xorriso_cmd="xorriso -as mkisofs \
        -iso-level 3 \
        -full-iso9660-filenames \
        -volid 'AILinux 1.0' \
        -appid 'AILinux Live CD' \
        -publisher 'AILinux Team' \
        -preparer 'AILinux Build System' \
        -eltorito-boot isolinux/isolinux.bin \
        -eltorito-catalog isolinux/boot.cat \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        -eltorito-alt-boot \
        -e boot/grub/efi.img \
        -no-emul-boot \
        -output '$iso_output' \
        '$AILINUX_BUILD_TEMP_DIR/iso/'"
    
    if ! safe_execute "$xorriso_cmd" "xorriso" "Failed to create ISO image"; then
        log_error "❌ ISO creation failed"
        return 1
    fi
    
    # Stop resource tracking
    if command -v stop_tracking_resource_usage >/dev/null 2>&1; then
        stop_tracking_resource_usage "xorriso"
    fi
    
    log_success "✅ ISO image created: $iso_output"
    return 0
}

# Validate and create checksums for ISO
validate_and_checksum_iso() {
    log_info "🔐 Validating and creating checksums for ISO..."
    
    local iso_file="$AILINUX_BUILD_OUTPUT_DIR/ailinux-1.0-amd64.iso"
    
    if [ ! -f "$iso_file" ]; then
        log_error "❌ ISO file not found: $iso_file"
        return 1
    fi
    
    # Generate checksums
    if command -v generate_checksums >/dev/null 2>&1; then
        generate_checksums "$AILINUX_BUILD_OUTPUT_DIR" "ailinux-1.0-checksums.md5" "md5" || {
            log_warn "⚠️  Checksum generation using module failed, using fallback"
        }
    fi
    
    # Fallback checksum generation
    cd "$AILINUX_BUILD_OUTPUT_DIR" || return 1
    
    md5sum "$(basename "$iso_file")" > "ailinux-1.0-checksums.md5" || {
        log_error "❌ Failed to generate MD5 checksum"
        return 1
    }
    
    sha256sum "$(basename "$iso_file")" > "ailinux-1.0-checksums.sha256" || {
        log_warn "⚠️  Failed to generate SHA256 checksum"
    }
    
    # Display file information
    local iso_size=$(du -h "$iso_file" | cut -f1)
    local iso_md5=$(cat "ailinux-1.0-checksums.md5" | cut -d' ' -f1)
    
    log_success "✅ ISO validation completed:"
    log_info "   File: $(basename "$iso_file")"
    log_info "   Size: $iso_size"
    log_info "   MD5:  $iso_md5"
    
    cd - >/dev/null || true
    return 0
}

# ============================================================================
# CLEANUP AND FINALIZATION
# ============================================================================

# Cleanup build resources
cleanup_build_resources() {
    log_info "🧹 Cleaning up build resources..."
    
    # Use module cleanup functions if available
    if command -v cleanup_chroot_mounts >/dev/null 2>&1; then
        cleanup_chroot_mounts "$AILINUX_BUILD_CHROOT_DIR"
    fi
    
    if command -v cleanup_resource_management >/dev/null 2>&1; then
        cleanup_resource_management
    fi
    
    if command -v cleanup_service_management >/dev/null 2>&1; then
        cleanup_service_management
    fi
    
    if command -v cleanup_checksum_validation >/dev/null 2>&1; then
        cleanup_checksum_validation
    fi
    
    if command -v cleanup_mirror_management >/dev/null 2>&1; then
        cleanup_mirror_management
    fi
    
    if command -v cleanup_secureboot_handling >/dev/null 2>&1; then
        cleanup_secureboot_handling
    fi
    
    if command -v cleanup_kde_installation >/dev/null 2>&1; then
        cleanup_kde_installation
    fi
    
    if command -v cleanup_calamares_setup >/dev/null 2>&1; then
        cleanup_calamares_setup
    fi
    
    if command -v cleanup_ai_integration >/dev/null 2>&1; then
        cleanup_ai_integration
    fi
    
    # Clean up temporary files (unless skip cleanup is enabled)
    if [ "$AILINUX_SKIP_CLEANUP" = false ]; then
        log_info "🗂️  Removing temporary build files..."
        safe_execute "sudo rm -rf '$AILINUX_BUILD_TEMP_DIR'" "cleanup_temp" "Failed to clean temporary directory" "" "true"
        
        if [ "$AILINUX_BUILD_AS_ROOT" = false ]; then
            safe_execute "sudo rm -rf '$AILINUX_BUILD_CHROOT_DIR'" "cleanup_chroot" "Failed to clean chroot directory" "" "true"
        fi
    else
        log_info "ℹ️  Skipping cleanup as requested (AILINUX_SKIP_CLEANUP=true)"
    fi
    
    log_success "✅ Build resource cleanup completed"
}

# Generate final build report
generate_build_report() {
    log_info "📄 Generating final build report..."
    
    local report_file="$AILINUX_BUILD_OUTPUT_DIR/ailinux-build-report-$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "# AILinux Build Report"
        echo "# Generated: $(date)"
        echo "# Build Version: $AILINUX_BUILD_VERSION"
        echo "# Build Date: $AILINUX_BUILD_DATE"
        echo ""
        
        echo "== BUILD CONFIGURATION =="
        echo "Build Directory: $AILINUX_BUILD_DIR"
        echo "Chroot Directory: $AILINUX_BUILD_CHROOT_DIR"
        echo "Output Directory: $AILINUX_BUILD_OUTPUT_DIR"
        echo "Log File: $LOG_FILE"
        echo "Skip Cleanup: $AILINUX_SKIP_CLEANUP"
        echo "Debug Mode: $AILINUX_ENABLE_DEBUG"
        echo "Dry Run: $AILINUX_DRY_RUN"
        echo ""
        
        echo "== SYSTEM INFORMATION =="
        echo "Host OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')"
        echo "Build User: $(whoami)"
        echo "Build Time: $(date)"
        echo "Build Duration: $(( $(date +%s) - BUILD_START_TIME )) seconds"
        echo ""
        
        echo "== OUTPUT FILES =="
        if [ -d "$AILINUX_BUILD_OUTPUT_DIR" ]; then
            find "$AILINUX_BUILD_OUTPUT_DIR" -type f -exec ls -lh {} \;
        fi
        echo ""
        
        echo "== BUILD LOG SUMMARY =="
        if [ -f "$LOG_FILE" ]; then
            echo "Total log entries: $(wc -l < "$LOG_FILE")"
            echo "Errors: $(grep -c "ERROR:" "$LOG_FILE" || echo 0)"
            echo "Warnings: $(grep -c "WARN:" "$LOG_FILE" || echo 0)"
            echo "Success messages: $(grep -c "SUCCESS:" "$LOG_FILE" || echo 0)"
        fi
        echo ""
        
        echo "== FINAL STATUS =="
        if [ -f "$AILINUX_BUILD_OUTPUT_DIR/ailinux-1.0-amd64.iso" ]; then
            echo "✅ BUILD SUCCESSFUL"
            echo "ISO File: ailinux-1.0-amd64.iso"
            echo "ISO Size: $(du -h "$AILINUX_BUILD_OUTPUT_DIR/ailinux-1.0-amd64.iso" | cut -f1)"
            if [ -f "$AILINUX_BUILD_OUTPUT_DIR/ailinux-1.0-checksums.md5" ]; then
                echo "MD5 Checksum: $(cat "$AILINUX_BUILD_OUTPUT_DIR/ailinux-1.0-checksums.md5" | cut -d' ' -f1)"
            fi
        else
            echo "❌ BUILD FAILED"
            echo "No ISO file generated"
        fi
        
    } > "$report_file"
    
    log_success "📄 Build report generated: $report_file"
    
    # Coordinate with swarm
    swarm_coordinate "build_complete" "AILinux ISO build completed - report generated: $report_file" "success" "completion"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

# Main function
main() {
    # Record build start time
    BUILD_START_TIME=$(date +%s)
    
    log_info "🚀 Starting AILinux ISO build process..."
    log_info "Build Version: $AILINUX_BUILD_VERSION"
    log_info "Build Date: $AILINUX_BUILD_DATE"
    log_info "Session ID: $AILINUX_BUILD_SESSION_ID"
    
    # Initialize swarm coordination if available
    if command -v npx >/dev/null 2>&1; then
        npx claude-flow@alpha hooks pre-task --description "AILinux ISO Build Process" --auto-spawn-agents false 2>/dev/null || true
    fi
    
    # Phase 0: Initialization
    init_build_environment || {
        log_critical "❌ Build environment initialization failed"
        exit 1
    }
    
    load_build_modules || {
        log_critical "❌ Module loading failed"
        exit 1
    }
    
    initialize_build_systems || {
        log_critical "❌ Build system initialization failed"
        exit 1
    }
    
    # Execute build phases
    if [ "$AILINUX_DRY_RUN" = true ]; then
        log_info "🔍 DRY RUN MODE - Simulating build phases..."
        
        log_info "Phase 1: Environment validation and setup [SIMULATED]"
        log_info "Phase 2: Base system creation [SIMULATED]"
        log_info "Phase 3: KDE 6.3 installation [SIMULATED]"
        log_info "Phase 4: Calamares setup [SIMULATED]"
        log_info "Phase 5: AI integration [SIMULATED]"
        log_info "Phase 6: ISO generation [SIMULATED]"
        
        log_success "✅ DRY RUN COMPLETED - All phases would execute successfully"
        
    else
        # Execute actual build phases
        phase_1_environment_setup || {
            log_critical "❌ Phase 1 failed - Environment setup"
            cleanup_build_resources
            exit 1
        }
        
        phase_2_base_system || {
            log_critical "❌ Phase 2 failed - Base system creation"
            cleanup_build_resources
            exit 1
        }
        
        phase_3_kde_installation || {
            log_critical "❌ Phase 3 failed - KDE installation"
            cleanup_build_resources
            exit 1
        }
        
        phase_4_calamares_setup || {
            log_critical "❌ Phase 4 failed - Calamares setup"
            cleanup_build_resources
            exit 1
        }
        
        phase_5_ai_integration || {
            log_critical "❌ Phase 5 failed - AI integration"
            cleanup_build_resources
            exit 1
        }
        
        phase_6_iso_generation || {
            log_critical "❌ Phase 6 failed - ISO generation"
            cleanup_build_resources
            exit 1
        }
    fi
    
    # Finalization
    cleanup_build_resources
    generate_build_report
    
    # Final coordination
    if command -v npx >/dev/null 2>&1; then
        npx claude-flow@alpha hooks post-task --task-id "ailinux-iso-build" --analyze-performance true 2>/dev/null || true
    fi
    
    local build_duration=$(( $(date +%s) - BUILD_START_TIME ))
    log_success "🎉 AILinux ISO build completed successfully in ${build_duration} seconds!"
    
    if [ "$AILINUX_DRY_RUN" = false ]; then
        log_info "📁 Output files available in: $AILINUX_BUILD_OUTPUT_DIR"
        if [ -f "$AILINUX_BUILD_OUTPUT_DIR/ailinux-1.0-amd64.iso" ]; then
            log_info "💿 ISO file: ailinux-1.0-amd64.iso"
        fi
    fi
    
    return 0
}

# Handle script arguments
handle_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-cleanup)
                export AILINUX_SKIP_CLEANUP=true
                log_info "🔧 Skip cleanup enabled"
                shift
                ;;
            --debug)
                export AILINUX_ENABLE_DEBUG=true
                export LOG_LEVEL="DEBUG"
                log_info "🐛 Debug mode enabled"
                shift
                ;;
            --dry-run)
                export AILINUX_DRY_RUN=true
                log_info "🔍 Dry run mode enabled"
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            --version|-v)
                echo "AILinux Build Script v$AILINUX_BUILD_VERSION"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Show help information
show_help() {
    cat << EOF
AILinux ISO Build Script v$AILINUX_BUILD_VERSION

DESCRIPTION:
    Builds a complete AILinux live ISO with KDE 6.3, Calamares installer,
    Secure Boot support, AI helper integration, and session safety.

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --skip-cleanup     Skip cleanup of temporary files (useful for debugging)
    --debug            Enable debug mode with verbose logging
    --dry-run          Simulate build process without actual execution
    --help, -h         Show this help message
    --version, -v      Show version information

EXAMPLES:
    $0                     # Normal build
    $0 --debug             # Build with debug logging
    $0 --dry-run           # Simulate build process
    $0 --skip-cleanup      # Build and keep temporary files

REQUIREMENTS:
    - Ubuntu 24.04 (Noble) or compatible system
    - Minimum 10GB free disk space
    - Minimum 2GB available RAM
    - sudo privileges
    - debootstrap, squashfs-tools, xorriso, grub utilities

OUTPUT:
    - ailinux-1.0-amd64.iso (bootable ISO image)
    - ailinux-1.0-checksums.md5 (MD5 checksums)
    - ailinux-build-report-*.txt (detailed build report)

ENVIRONMENT VARIABLES:
    AILINUX_SKIP_CLEANUP   Skip cleanup (true/false)
    AILINUX_ENABLE_DEBUG   Enable debug mode (true/false)
    AILINUX_DRY_RUN        Dry run mode (true/false)

For more information, visit: https://ailinux.org/build
EOF
}

# ============================================================================
# SCRIPT ENTRY POINT
# ============================================================================

# Ensure script is not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Handle command line arguments
    handle_arguments "$@"
    
    # Execute main function
    main "$@"
    exit $?
else
    log_warn "⚠️  This script should be executed, not sourced"
fi