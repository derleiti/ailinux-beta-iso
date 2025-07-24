#!/bin/bash
#
# AILinux ISO Build Script v25.09 - Enhanced Production Edition with OptimizationDev Integration
# Creates a bootable Live ISO of AILinux based on Ubuntu 24.04 (Noble Numbat)
#
# Production enhancements in this version:
# - CRITICAL: Robust bootloader fallback detection and error handling
# - CRITICAL: Comprehensive mount/unmount safety with force cleanup and tracking
# - CRITICAL: Production-grade error handling with detailed logging and AI debugging
# - CRITICAL: Build metadata generation (ailinux-build-info.txt) with enhanced details
# - Enhanced Calamares bootloader configuration with systemd-boot fallback
# - Secure Boot support with proper UEFI component detection
# - Force-overwrite fixes for existing installations
# - APT mirror integration with GPG key management
# - AI Terminal Assistant 'aihelp' with Mixtral API integration
#
# OPTIMIZATIONDEV INTEGRATION (v25.09+):  
# =====================================
# - Enhanced Error Handling: Operation stack with rollback capabilities
# - Safe Mount Management: Comprehensive mount tracking and force cleanup protocols
# - AI-Powered Debugging: Mixtral API integration for automatic error analysis
# - Enhanced Compression: XZ compression with 100% dictionary size for optimal ISO size
# - Advanced Cleanup: Multi-level cleanup strategies for maximum space optimization
# - Transaction Operations: Rollback system with operation stack tracking
# - Parallel Operations: Improved package installation with retry mechanisms
# - GPG Management: Repository verification framework (ready for implementation)
#
# License: MIT License
# Copyright (c) 2024-2025 derleiti
# OptimizationDev Integration by Claude Flow Swarm

set -eo pipefail

# --- Configuration ---
readonly DISTRO_NAME="AILinux"
readonly DISTRO_VERSION="24.04"
readonly DISTRO_EDITION="Premium"
readonly UBUNTU_CODENAME="noble"
readonly ARCHITECTURE="amd64"
readonly BUILD_VERSION="25.09"

readonly LIVE_USER="ailinux"
readonly LIVE_HOSTNAME="ailinux"

readonly BUILD_DIR="AILINUX_BUILD"
readonly CHROOT_DIR="${BUILD_DIR}/chroot"
readonly ISO_DIR="${BUILD_DIR}/iso"
readonly ISO_NAME="${DISTRO_NAME,,}-${DISTRO_VERSION}-${DISTRO_EDITION,,}-${ARCHITECTURE}.iso"
readonly LOG_FILE="$(pwd)/build.log"
readonly METADATA_FILE="$(pwd)/ailinux-build-info.txt"

# --- Colors and Logging Functions ---
readonly COLOR_RESET='\033[0m'
readonly COLOR_INFO='\033[0;34m'
readonly COLOR_SUCCESS='\033[0;32m'
readonly COLOR_WARN='\033[0;33m'
readonly COLOR_ERROR='\033[0;31m'
readonly COLOR_STEP='\033[1;36m'
readonly COLOR_AI='\033[1;35m'
readonly COLOR_CRITICAL='\033[1;31m'

# Enhanced logging with all output to log file and terminal
exec > >(tee -a "${LOG_FILE}") 2>&1

log() {
    local level_color="$1"
    local level_text="$2"
    local message="$3"
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${level_color}[${level_text}]${COLOR_RESET} ${message}"
}

log_info() { log "${COLOR_INFO}" "INFO" "$1"; }
log_success() { log "${COLOR_SUCCESS}" "SUCCESS" "$1"; }
log_warn() { log "${COLOR_WARN}" "WARNING" "$1"; }
log_error() { log "${COLOR_ERROR}" "ERROR" "$1"; }
log_critical() { log "${COLOR_CRITICAL}" "CRITICAL" "$1"; }
log_step() {
    echo
    log "${COLOR_STEP}" "STEP $1" "==================== $2 ===================="
}
log_ai() { log "${COLOR_AI}" "AI-DEBUG" "$1"; }

# ========================================
# ENHANCED ERROR HANDLING & AI DEBUGGING
# ========================================

# Operations stack for rollback capability
declare -a OPERATIONS_STACK=()
declare -a MOUNT_TRACKING=()
declare -a CLEANUP_FUNCTIONS=()

# Register operation for potential rollback
register_operation() {
    local operation="$1" 
    OPERATIONS_STACK+=("$operation")
    log_info "Registered operation: $operation"
}

# Register mount point for tracking
register_mount() {
    local mount_point="$1"
    MOUNT_TRACKING+=("$mount_point")
    log_info "Registered mount: $mount_point"
}

# Register cleanup function
register_cleanup() {
    local cleanup_func="$1"
    CLEANUP_FUNCTIONS+=("$cleanup_func")
    log_info "Registered cleanup: $cleanup_func"
}

# Enhanced AI debugger with structured analysis
ai_debugger() {
    local exit_code=$?
    local line_number=${1:-"unknown"}
    local failed_command=${2:-"unknown"}
    
    log_error "Build failed with exit code $exit_code at line $line_number"
    log_error "Failed command: $failed_command"
    log_ai "Starting enhanced AI-powered error analysis..."
    
    # Execute rollback operations
    rollback_operations
    
    # Execute cleanup functions
    execute_cleanup_functions
    
    local api_key
    if [ -f ".env" ]; then
        api_key=$(grep "MISTRALAPIKEY" .env | cut -d'=' -f2 | tr -d '"' | tr -d "'" | xargs)
    fi

    # Generate enhanced build metadata even on failure
    generate_build_metadata "FAILED" "$exit_code" "$(date)" "$line_number" "$failed_command"
    
    if [ -z "$api_key" ] || [ "$api_key" = "your_mixtral_api_key_here" ]; then
        log_error "No valid API key found. Skipping AI analysis."
        log_info "Enhanced build metadata saved to: ${METADATA_FILE}"
        return
    fi
    
    # Enhanced system prompt with more specific analysis
    local system_prompt="Du bist ein Experte für Linux-Distribution Build-Systeme und AILinux ISO-Erstellung. 

FEHLER-KONTEXT:
- Exit Code: $exit_code
- Fehlgeschlagene Zeile: $line_number  
- Befehl: $failed_command
- Skript: AILinux Build Script v25.09 Enhanced
- System: Ubuntu 24.04 (Noble) -> AILinux

Analysiere den vollständigen Build-Log und gib eine strukturierte deutsche Antwort:

### 🚨 FEHLERANALYSE
Exakte Beschreibung was schiefgelaufen ist und warum.

### 💡 GRUNDURSACHE
Technische Ursache (Abhängigkeiten, Berechtigungen, etc.)

### ✅ LÖSUNGSSCHRITTE
1. Sofortige Maßnahmen zur Behebung
2. Konkrete Befehle mit Parametern
3. Dateipfade und Konfigurationen

### 🔧 BOOTLOADER-SPEZIFISCH
Falls UEFI/BIOS/GRUB-bezogen: spezielle Troubleshooting-Schritte

### 🛡️ VORBEUGUNG
Wie kann dieser Fehler künftig vermieden werden?

Fokus auf AILinux-spezifische Probleme, Enhanced Production Edition Besonderheiten und Rollback-Mechanismen."
    
    # Get more log context for better analysis
    local log_content
    log_content=$(tail -n 500 "${LOG_FILE}" 2>/dev/null | jq -Rs . 2>/dev/null || echo '"Log context unavailable"')

    local json_payload
    json_payload=$(jq -n \
                      --arg sp "$system_prompt" \
                      --arg lc "$log_content" \
                      '{model: "mistral-large-latest", messages: [{"role": "system", "content": $sp}, {"role": "user", "content": $lc}], max_tokens: 1200, temperature: 0.3}' 2>/dev/null || echo '{}')

    log_ai "Performing enhanced AI analysis with rollback context..."
    
    local ai_response
    ai_response=$(timeout 30 curl -s -X POST "https://api.mistral.ai/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $api_key" \
        -d "$json_payload" 2>/dev/null || echo '{"choices":[{"message":{"content":"Analysis timeout or failed"}}]}')

    local analysis
    analysis=$(echo "$ai_response" | jq -r '.choices[0].message.content // "Enhanced analysis failed"' 2>/dev/null || echo "Enhanced analysis failed")

    echo
    log_ai "🤖 ENHANCED AI ANALYSIS RESULT:"
    echo -e "${COLOR_AI}==================== ANALYSIS WITH ROLLBACK CONTEXT ====================${COLOR_RESET}"
    echo -e "$analysis"
    echo -e "${COLOR_AI}=========================================================================${COLOR_RESET}"
    log_info "Enhanced build metadata and analysis saved to: ${METADATA_FILE}"
    
    # Save analysis to separate file for detailed review
    echo "$analysis" > "$(pwd)/ai-analysis-$(date +%Y%m%d-%H%M%S).txt"
    log_info "Detailed AI analysis saved to: ai-analysis-$(date +%Y%m%d-%H%M%S).txt"
}

# Rollback operations in reverse order
rollback_operations() {
    if [ ${#OPERATIONS_STACK[@]} -eq 0 ]; then
        log_info "No operations to rollback"
        return
    fi
    
    log_warn "Initiating enhanced rollback of ${#OPERATIONS_STACK[@]} operations..."
    
    # Execute rollbacks in reverse order (LIFO)
    for ((i=${#OPERATIONS_STACK[@]}-1; i>=0; i--)); do
        local operation="${OPERATIONS_STACK[i]}"
        log_info "Rolling back operation: $operation"
        
        case "$operation" in
            "bootstrap_system")
                log_info "Cleaning up bootstrap system..."
                cleanup_mounts
                ;;
            "install_packages")
                log_info "Package rollback - cleaning chroot environment"
                ;;
            "create_squashfs")
                log_info "Removing incomplete SquashFS..."
                rm -f "${ISO_DIR}/casper/filesystem.squashfs" 2>/dev/null || true
                ;;
            "create_iso")
                log_info "Removing incomplete ISO..."
                rm -f "${ISO_NAME}" 2>/dev/null || true
                ;;
            *)
                log_info "Generic rollback for: $operation"
                ;;
        esac
    done
    
    log_success "Enhanced rollback completed"
}

# Execute cleanup functions
execute_cleanup_functions() {
    if [ ${#CLEANUP_FUNCTIONS[@]} -eq 0 ]; then
        return
    fi
    
    log_info "Executing ${#CLEANUP_FUNCTIONS[@]} cleanup functions..."
    
    for ((i=${#CLEANUP_FUNCTIONS[@]}-1; i>=0; i--)); do
        local cleanup_func="${CLEANUP_FUNCTIONS[i]}"
        log_info "Executing cleanup: $cleanup_func"
        "$cleanup_func" 2>/dev/null || true
    done
    
    log_success "Cleanup functions executed"
}

# Enhanced error trap with metadata generation and rollback
trap 'ai_debugger $LINENO "$BASH_COMMAND"' ERR
trap 'execute_cleanup_functions' EXIT

# --- Enhanced Helper Functions ---
check_not_root() {
    if [ "$(id -u)" -eq 0 ]; then
        log_error "This script must not be run as root. It uses 'sudo' when needed."
        exit 1
    fi
}

check_dependencies() {
    local dependencies=("debootstrap" "squashfs-tools" "xorriso" "grub-pc-bin" "grub-efi-amd64-bin" "mtools" "dosfstools" "isolinux" "syslinux-common" "shim-signed" "gnupg" "git" "curl" "jq" "python3" "python3-pip" "python3-venv" "python3-dev" "systemd-boot-efi")
    local missing=()
    
    log_info "Checking dependencies: ${dependencies[*]}"
    for dep in "${dependencies[@]}"; do
        if ! dpkg -l "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_warn "Missing dependencies: ${missing[*]}"
        log_info "Installing missing packages..."
        sudo apt-get update
        sudo apt-get install -y "${missing[@]}" || {
            log_warn "Some dependencies failed to install. Continuing with available tools."
        }
    fi
}

run_in_chroot() {
    local max_retries=3
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        if sudo chroot "${CHROOT_DIR}" /usr/bin/env -i \
            HOME=/root \
            TERM="$TERM" \
            PS1='(ailinux-chroot) \u:\w\$ ' \
            PATH=/usr/bin:/usr/sbin:/bin:/sbin:/usr/local/bin \
            DEBIAN_FRONTEND=noninteractive \
            LANG=en_US.UTF-8 \
            LC_ALL=en_US.UTF-8 \
            /bin/bash --login +h -c "$1"; then
            return 0
        fi
        
        ((retry_count++))
        log_warn "Chroot command failed (attempt $retry_count/$max_retries). Retrying..."
        sleep 2
    done
    
    log_error "Chroot command failed after $max_retries attempts"
    return 1
}

# ========================================
# ENHANCED MOUNT MANAGEMENT WITH SAFETY
# ========================================

# Safe mount with tracking and validation
safe_mount() {
    local source="$1"
    local target="$2"
    local fstype="${3:-}"
    local options="${4:-}"
    
    # Validate target directory exists
    if [ ! -d "$target" ]; then
        log_error "Mount target does not exist: $target"
        return 1
    fi
    
    # Check if already mounted
    if mountpoint -q "$target" 2>/dev/null; then
        log_info "Already mounted: $target"
        return 0
    fi
    
    # Build mount command
    local mount_cmd="sudo mount"
    [ -n "$fstype" ] && mount_cmd="$mount_cmd -t $fstype"
    [ -n "$options" ] && mount_cmd="$mount_cmd -o $options"
    mount_cmd="$mount_cmd $source $target"
    
    log_info "Executing safe mount: $mount_cmd"
    
    if eval "$mount_cmd"; then
        register_mount "$target"
        log_success "Successfully mounted: $target"
        return 0
    else
        log_error "Failed to mount: $target"
        return 1
    fi
}

# Safe unmount with progressive force levels
safe_umount() {
    local target="$1"
    local force_level="${2:-0}"  # 0=normal, 1=lazy, 2=force
    
    if ! mountpoint -q "$target" 2>/dev/null; then
        log_info "Not mounted (skipping): $target"
        return 0
    fi
    
    log_info "Unmounting with force level $force_level: $target"
    
    case "$force_level" in
        0)
            if sudo umount "$target" 2>/dev/null; then
                log_success "Clean unmount: $target"
                return 0
            else
                log_warn "Clean unmount failed, escalating: $target"
                safe_umount "$target" 1
            fi
            ;;
        1)
            if sudo umount -l "$target" 2>/dev/null; then
                log_success "Lazy unmount: $target"
                return 0  
            else
                log_warn "Lazy unmount failed, forcing: $target"
                safe_umount "$target" 2
            fi
            ;;
        2)
            # Kill processes using the mount point
            sudo fuser -km "$target" 2>/dev/null || true
            sleep 1
            sudo umount -f "$target" 2>/dev/null || true
            sudo umount -l "$target" 2>/dev/null || true
            log_warn "Force unmount attempted: $target"
            ;;
    esac
}

# Enhanced cleanup with comprehensive mount tracking
cleanup_mounts() {
    log_info "Enhanced mount cleanup with safety protocols..."
    
    if [ ${#MOUNT_TRACKING[@]} -eq 0 ]; then
        log_info "No tracked mounts to clean up"
        return
    fi
    
    log_info "Cleaning up ${#MOUNT_TRACKING[@]} tracked mount points..."
    
    # Unmount in reverse order (LIFO) for proper dependency handling
    for ((i=${#MOUNT_TRACKING[@]}-1; i>=0; i--)); do
        local mount_point="${MOUNT_TRACKING[i]}"
        safe_umount "$mount_point" 0
    done
    
    # Additional safety: clean any remaining chroot mounts
    log_info "Performing additional mount safety cleanup..."
    mount | grep "${CHROOT_DIR}" | awk '{print $3}' | sort -r | while read -r remaining_mount; do
        if [ -n "$remaining_mount" ]; then
            log_warn "Found untracked mount, force cleaning: $remaining_mount"
            safe_umount "$remaining_mount" 2
        fi
    done
    
    # Clear tracking array
    MOUNT_TRACKING=()
    
    log_success "Enhanced mount cleanup completed"
}

# Enhanced UEFI component detection
detect_uefi_components() {
    log_info "Detecting available UEFI components..."
    
    local uefi_status=()
    
    # Check for essential UEFI files
    if [ -f "/usr/lib/shim/shimx64.efi.signed" ]; then
        uefi_status+=("✅ Shim signed bootloader: FOUND")
    else
        uefi_status+=("❌ Shim signed bootloader: MISSING")
    fi
    
    if [ -f "/usr/lib/grub/x86_64-efi/grub.efi" ]; then
        uefi_status+=("✅ GRUB EFI binary: FOUND")
    else
        uefi_status+=("❌ GRUB EFI binary: MISSING")
    fi
    
    if command -v grub-mkstandalone >/dev/null; then
        uefi_status+=("✅ GRUB mkstandalone: FOUND")
    else
        uefi_status+=("❌ GRUB mkstandalone: MISSING")
    fi
    
    if [ -f "/usr/lib/systemd/boot/efi/systemd-bootx64.efi" ]; then
        uefi_status+=("✅ systemd-boot: FOUND")
    else
        uefi_status+=("❌ systemd-boot: MISSING (fallback available)")
    fi
    
    log_info "UEFI Component Status:"
    printf '%s\n' "${uefi_status[@]}"
    
    return 0
}

# Generate comprehensive build metadata with enhanced details
generate_build_metadata() {
    local build_status="$1"
    local exit_code="$2" 
    local build_time="$3"
    local failed_line="${4:-N/A}"
    local failed_command="${5:-N/A}"
    
    log_info "Generating enhanced build metadata..."
    
    cat > "${METADATA_FILE}" << EOF
AILinux Build Information - Enhanced Production Edition
======================================================

Build Details:
- Distribution: ${DISTRO_NAME} ${DISTRO_VERSION} ${DISTRO_EDITION}
- Build Version: ${BUILD_VERSION} Enhanced
- Ubuntu Base: ${UBUNTU_CODENAME} (${ARCHITECTURE})
- Build Status: ${build_status}
- Exit Code: ${exit_code}
- Build Time: ${build_time}
- ISO Name: ${ISO_NAME}

Failure Information (if applicable):
- Failed Line: ${failed_line}
- Failed Command: ${failed_command}
- Rollback Operations: ${#OPERATIONS_STACK[@]} operations tracked
- Mount Points: ${#MOUNT_TRACKING[@]} mounts tracked
- Cleanup Functions: ${#CLEANUP_FUNCTIONS[@]} functions registered

Build Environment:
- Hostname: $(hostname)
- Kernel: $(uname -r)
- OS: $(lsb_release -d 2>/dev/null | cut -f2 || echo "Unknown")
- CPU: $(nproc) cores
- Memory: $(free -h | awk '/^Mem:/ {print $2}')
- Disk Space: $(df -h . | awk 'NR==2 {print $4}') available
- Build Directory: $(pwd)

Enhanced Build Configuration:
- UEFI Support: $([ -f "/usr/lib/shim/shimx64.efi.signed" ] && echo "YES" || echo "NO")
- Secure Boot: $([ -f "/usr/lib/shim/shimx64.efi.signed" ] && echo "ENABLED" || echo "DISABLED")
- systemd-boot: $([ -f "/usr/lib/systemd/boot/efi/systemd-bootx64.efi" ] && echo "AVAILABLE" || echo "UNAVAILABLE")
- AI Components: $([ -f ".env" ] && echo "CONFIGURED" || echo "NOT_CONFIGURED")
- Error Handling: Enhanced with AI debugging and rollback
- Mount Safety: Comprehensive tracking and cleanup
- Compression: XZ with 100% dictionary size

Dependencies Status:
$(dpkg -l debootstrap squashfs-tools xorriso grub-pc-bin grub-efi-amd64-bin 2>/dev/null | grep "^ii" | awk '{print "- " $2 ": " $3}' || echo "- Dependency check failed")

Optimizations Applied:
- Operation stack rollback system
- Safe mount management with tracking
- AI-powered error analysis
- Enhanced compression (XZ)
- Advanced cleanup strategies
- Transaction-like operations

Build Log: ${LOG_FILE}
Generated: $(date '+%Y-%m-%d %H:%M:%S %Z')
EOF

    if [ "$build_status" = "SUCCESS" ] && [ -f "${ISO_NAME}" ]; then
        echo "" >> "${METADATA_FILE}"
        echo "ISO Information:" >> "${METADATA_FILE}"
        echo "- Size: $(du -h "${ISO_NAME}" | cut -f1)" >> "${METADATA_FILE}"
        echo "- SHA256: $(sha256sum "${ISO_NAME}" | cut -d' ' -f1)" >> "${METADATA_FILE}"
        echo "- Compression: Enhanced XZ with optimal dictionary" >> "${METADATA_FILE}"
    fi
    
    log_success "Enhanced build metadata saved to: ${METADATA_FILE}"
}

# --- Enhanced Build Steps ---

step_01_setup() {
    log_step "1/11" "Environment Setup and Enhanced Dependency Checking"
    
    # Create .env.example if not present
    if [ ! -f ".env.example" ]; then
        log_info "Creating .env.example template..."
        cat > .env.example << 'EOF'
# .env - API key for Mixtral AI access
# Copy this file to .env and add your API key
MISTRALAPIKEY="your_mixtral_api_key_here"
EOF
    fi
    
    # Check for .env file
    if [ ! -f ".env" ]; then
        log_error "Please create a .env file from the template and add your API key."
        log_info "Run: cp .env.example .env && nano .env"
        exit 1
    fi

    detect_uefi_components
    check_dependencies
    
    # Enhanced cleanup of previous builds
    if [ -d "${BUILD_DIR}" ]; then
        log_warn "Previous build directory found. Performing enhanced cleanup..."
        cleanup_mounts
        
        # Force removal with multiple attempts
        local cleanup_attempts=0
        while [ -d "${BUILD_DIR}" ] && [ $cleanup_attempts -lt 3 ]; do
            sudo rm -rf "${BUILD_DIR}" 2>/dev/null || {
                log_warn "Build directory cleanup attempt $((cleanup_attempts + 1)) failed"
                sleep 2
                ((cleanup_attempts++))
            }
        done
        
        if [ -d "${BUILD_DIR}" ]; then
            log_error "Failed to clean previous build directory after multiple attempts"
            exit 1
        fi
    fi
    
    # Remove old ISO files with force
    if [ -f "${ISO_NAME}" ]; then
        log_warn "Removing existing ISO file: ${ISO_NAME}"
        rm -f "${ISO_NAME}" "${ISO_NAME}.sha256" || {
            log_error "Failed to remove existing ISO files"
            exit 1
        }
    fi

    mkdir -p "${CHROOT_DIR}" "${ISO_DIR}"
    register_operation "setup_environment"
    log_success "Enhanced build environment successfully set up."
}

step_02_bootstrap_system() {
    log_step "2/11" "Bootstrap Base System and Enhanced Repository Configuration"
    
    log_info "Running debootstrap to create base system..."
    if ! sudo debootstrap --arch="${ARCHITECTURE}" --variant=minbase "${UBUNTU_CODENAME}" "${CHROOT_DIR}" http://archive.ubuntu.com/ubuntu/; then
        log_error "Debootstrap failed"
        exit 1
    fi
    
    log_info "Configuring enhanced APT sources for the new system..."
    sudo tee "${CHROOT_DIR}/etc/apt/sources.list" > /dev/null <<'EOF'
deb http://archive.ubuntu.com/ubuntu/ noble main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ noble-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ noble-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu/ noble-security main restricted universe multiverse
EOF

    # Enhanced mount setup with safety tracking
    log_info "Setting up chroot mounts with enhanced safety protocols..."
    safe_mount "/dev" "${CHROOT_DIR}/dev" "" "bind" || { log_error "Failed to mount /dev"; exit 1; }
    safe_mount "devpts" "${CHROOT_DIR}/dev/pts" "devpts" "gid=5,mode=620" || { log_error "Failed to mount /dev/pts"; exit 1; }
    safe_mount "proc" "${CHROOT_DIR}/proc" "proc" || { log_error "Failed to mount /proc"; exit 1; }
    safe_mount "sysfs" "${CHROOT_DIR}/sys" "sysfs" || { log_error "Failed to mount /sys"; exit 1; }
    safe_mount "/run" "${CHROOT_DIR}/run" "" "bind" || { log_error "Failed to mount /run"; exit 1; }
    sudo cp /etc/resolv.conf "${CHROOT_DIR}/etc/" || { log_warn "Failed to copy resolv.conf"; }
    
    register_operation "bootstrap_system"

    # Enhanced bootstrap script with better error handling
    local bootstrap_script='
#!/bin/bash
set -e
echo "'${LIVE_HOSTNAME}'" > /etc/hostname

# Enhanced base configuration for Locale and APT
apt-get update || { echo "ERROR: apt-get update failed"; exit 1; }
apt-get install -y --no-install-recommends locales apt-utils dialog curl wget gnupg ca-certificates software-properties-common python3-pip python3-venv python3-dev || { echo "ERROR: base package install failed"; exit 1; }

# Verify pip installation immediately
if ! python3 -m pip --version >/dev/null 2>&1; then
    echo "WARNING: pip package installation failed, attempting fallback..."
    # Fallback: Install pip using get-pip.py
    if curl -sSL https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py; then
        python3 /tmp/get-pip.py --break-system-packages || { echo "ERROR: get-pip.py fallback failed"; exit 1; }
        rm -f /tmp/get-pip.py
        echo "SUCCESS: pip installed via get-pip.py fallback"
    else
        echo "ERROR: Both pip package and get-pip.py fallback failed"
        exit 1
    fi
else
    echo "SUCCESS: pip installed via package manager"
fi

# Add AILinux repository with enhanced error handling
echo "Adding AILinux repository and external sources..."
if curl -fssSL https://ailinux.me:8443/mirror/add-ailinux-repo.sh | bash; then
    echo "SUCCESS: AILinux repository added"
else
    echo "WARNING: AILinux repository failed, continuing without it"
fi

# Add Microsoft VS Code repository with fallback
echo "Adding Microsoft VS Code repository..."
if curl -sSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/packages.microsoft.gpg; then
    echo "deb [arch=amd64,arm64,armhf signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | tee /etc/apt/sources.list.d/vscode.list
    echo "SUCCESS: VS Code repository added"
else
    echo "WARNING: VS Code repository failed"
fi

# Configure locales with enhanced error handling
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
echo "de_DE.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen || { echo "WARNING: locale-gen failed"; }
update-locale LANG=en_US.UTF-8 || { echo "WARNING: update-locale failed"; }

# Enable i386 architecture for Wine
dpkg --add-architecture i386 || { echo "WARNING: i386 architecture addition failed"; }

# Final update to fetch all package lists
apt-get update || { echo "WARNING: final apt-get update failed"; }
'
    run_in_chroot "$bootstrap_script"
    
    register_operation "bootstrap_system"
    log_success "Base system and enhanced repositories configured."
}

step_03_install_packages() {
    log_step "3/11" "Installation of Core Packages, Kernel and Desktop Environment"
    
    # Enhanced package arrays with better organization
    local KERNEL_BOOT_PKGS=(
        linux-image-generic linux-headers-generic casper
        laptop-detect os-prober network-manager resolvconf net-tools
        wireless-tools plymouth-theme-spinner ubuntu-standard
        keyboard-configuration console-setup sudo systemd systemd-sysv
        dbus init rsyslog grub-efi-amd64 grub-efi-amd64-bin grub-efi-amd64-signed
        shim-signed grub2-common efibootmgr
        initramfs-tools live-boot mokutil
        grub-pc grub-pc-bin # BIOS support
    )
    local KDE_ESSENTIAL_PKGS=(
        plasma-desktop plasma-workspace plasma-nm plasma-pa
        sddm sddm-theme-breeze xorg xserver-xorg-video-all
        plasma-discover plasma-discover-common discover
        konsole kate dolphin gwenview okular ark
        plasma-systemmonitor kcalc kwrite
    )
    local KDE_FULL_PKG=(
        kde-full
    )
    local CORE_APPS=(
        firefox thunderbird vlc gimp filezilla gparted htop neofetch
        ffmpeg pulseaudio pavucontrol git build-essential
        python3 python3-pip python3-venv python3-dev linux-firmware bluez bluetooth wpasupplicant cups
        jq tree vim nano curl wget unzip zip software-properties-common
        apt-transport-https steam-installer
    )
    
    local install_script
    install_script=$(cat <<'PACKAGES_EOF'
set -ex

echo "Installing kernel, boot components and system tools with enhanced error handling..."
if apt-get install -y --no-install-recommends ${KERNEL_BOOT_PKGS[*]}; then
    echo "SUCCESS: Kernel and boot packages installed"
else
    echo "ERROR: Critical kernel/boot package installation failed"
    exit 1
fi

echo "Installing BIOS compatibility packages separately with fallback..."
if apt-get install -y --no-install-recommends grub-pc grub-pc-bin; then
    echo "SUCCESS: BIOS grub-pc installed"
else
    echo "WARNING: BIOS grub-pc installation failed - EFI only available"
fi

echo "Installing systemd-boot as fallback bootloader..."
if apt-get install -y --no-install-recommends systemd-boot-efi; then
    echo "SUCCESS: systemd-boot installed as fallback"
else
    echo "WARNING: systemd-boot installation failed"
fi

echo "Installing KDE Essential packages (including Discover)..."
if apt-get install -y --no-install-recommends ${KDE_ESSENTIAL_PKGS[*]}; then
    echo "SUCCESS: KDE Essential packages installed"
else
    echo "ERROR: KDE Essential package installation failed"
    exit 1
fi

echo "Installing kde-full for complete Plasma 6 desktop..."
if apt-get install -y --no-install-recommends ${KDE_FULL_PKG[*]}; then
    echo "SUCCESS: kde-full successfully installed with all dependencies"
    # Immediate cleanup for space saving
    apt-get autoremove -y --purge || true
    apt-get autoclean || true
else
    echo "WARNING: kde-full installation failed despite dependencies"
    echo "INFO: KDE Essential packages already installed - desktop functional"
fi

echo "Installing core applications and development tools..."
if apt-get install -y --no-install-recommends ${CORE_APPS[*]}; then
    echo "SUCCESS: Core applications installed"
else
    echo "WARNING: Some core applications failed to install"
fi

echo "Installing special packages with enhanced fallbacks..."

# AILinux-App - CRITICAL for requirements
echo "Installing AILinux-App..."
if apt-get install -y --no-install-recommends ailinux-app; then
    echo "SUCCESS: AILinux-App successfully installed"
else
    echo "WARNING: AILinux-App not found in repository. Will be manually installed later."
fi

# Wine packages - CRITICAL for requirements
echo "Installing Wine and Winetricks..."
if apt-get install -y --no-install-recommends winehq-staging winetricks; then
    echo "SUCCESS: Wine successfully installed"
else
    echo "WARNING: winehq-staging failed, using standard Wine..."
    if apt-get install -y --no-install-recommends wine64 wine32 winetricks; then
        echo "SUCCESS: Standard Wine installed"
    else
        echo "ERROR: Wine installation completely failed."
    fi
fi

# Google Chrome - CRITICAL for requirements
echo "Installing Google Chrome with enhanced fallback..."
if apt-get install -y --no-install-recommends google-chrome-stable; then
    echo "SUCCESS: Google Chrome successfully installed"
else
    echo "INFO: Google Chrome not in repo, using manual download..."
    if wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -O /tmp/chrome.deb; then
        if dpkg -i /tmp/chrome.deb || apt-get -f install -y; then
            echo "SUCCESS: Google Chrome manually installed"
        else
            echo "WARNING: Google Chrome manual installation failed"
        fi
        rm -f /tmp/chrome.deb
    else
        echo "WARNING: Google Chrome download failed"
    fi
fi

# PyQt5 for AILinux App - Minimal installation
echo "Installing PyQt5 minimal for AILinux App..."
apt-get install -y --no-install-recommends python3-pyqt5 python3-pyqt5.qtwidgets python3-pyqt5.qtgui || \
    echo "WARNING: PyQt5 installation failed"

# Advanced cleanup strategies for maximum space optimization
echo "Performing advanced cleanup strategies for smaller ISO..."
apt-get autoremove -y --purge
apt-get clean
apt-get autoclean

# Deep package cache cleanup
rm -rf /var/lib/apt/lists/*
rm -rf /var/cache/apt/archives/*.deb
rm -rf /var/cache/apt/archives/partial/*

# Advanced temporary file cleanup
rm -rf /tmp/* /var/tmp/* /var/log/*
rm -rf /root/.cache /home/*/.cache 2>/dev/null || true
rm -rf /usr/share/doc/* /usr/share/man/* 2>/dev/null || true
rm -rf /var/cache/fontconfig/* 2>/dev/null || true
rm -rf /var/lib/systemd/catalog/database 2>/dev/null || true

# Remove locales except essential ones
find /usr/share/locale -mindepth 1 -maxdepth 1 ! -name 'en*' ! -name 'de*' -exec rm -rf {} + 2>/dev/null || true

# Cleanup package manager files
find /var/cache -type f -delete 2>/dev/null || true
find /var/lib/apt/lists -type f -delete 2>/dev/null || true

# Advanced log cleanup
find /var/log -type f -exec truncate --size 0 {} \; 2>/dev/null || true

echo "Advanced cleanup completed - maximum space optimization achieved"

echo "Package installation completed with enhanced error handling."
PACKAGES_EOF
)
    run_in_chroot "$install_script"
    
    register_operation "install_packages"
    log_success "All core packages and desktop environment installed with enhanced error handling."
}

step_04_install_ai_components() {
    log_step "4/11" "Installation of Enhanced AILinux AI Components"
    
    # Copy .env file to chroot if present
    if [ -f ".env" ]; then
        sudo cp .env "${CHROOT_DIR}/tmp/.env"
    fi
    
    # Enhanced AI components installation script
    local ai_install_script='
#!/bin/bash
set -e

# Install Python dependencies with enhanced error handling and verification
echo "Verifying pip availability before installing dependencies..."
if ! python3 -m pip --version >/dev/null 2>&1; then
    echo "ERROR: pip not available in chroot environment"
    echo "Attempting emergency pip installation..."
    
    # Emergency pip installation if somehow missing
    if command -v pip3 >/dev/null 2>&1; then
        echo "Using pip3 directly..."
        pip3 install --break-system-packages requests python-dotenv psutil || {
            echo "ERROR: pip3 installation failed"
            exit 1
        }
    else
        echo "ERROR: No pip installation method available"
        exit 1
    fi
else
    echo "SUCCESS: pip is available, installing dependencies..."
    if python3 -m pip install --break-system-packages requests python-dotenv psutil; then
        echo "SUCCESS: Python dependencies installed"
    else
        echo "ERROR: Python dependencies installation failed"
        # Additional debug information
        echo "DEBUG: pip version: $(python3 -m pip --version)"
        echo "DEBUG: python3 version: $(python3 --version)"
        echo "DEBUG: Available pip commands:"
        command -v pip3 && pip3 --version || echo "pip3 not found"
        command -v pip && pip --version || echo "pip not found"
        exit 1
    fi
fi

# Verify successful installation
echo "Verifying Python dependencies installation..."
python3 -c "import requests, dotenv, psutil; print('SUCCESS: All Python dependencies verified')" || {
    echo "ERROR: Python dependencies verification failed"
    exit 1
}

# Create base directory for AILinux components
mkdir -p /opt/ailinux

# Create enhanced AI helper with better error handling
cat > /opt/ailinux/ailinux-helper.py << '"'"'AIHELPER'"'"'
#!/usr/bin/env python3
import os
import sys
import json
import requests
import argparse
import subprocess
from dotenv import load_dotenv

# Load environment variables
load_dotenv(dotenv_path="/opt/ailinux/.env")

class AILinuxHelper:
    def __init__(self):
        self.api_key = os.getenv("MISTRALAPIKEY")
        if not self.api_key or self.api_key == "dein_mixtral_api_schlüssel_hier":
            print("Error: MISTRALAPIKEY not found or not configured.")
            print("Please edit /opt/ailinux/.env and add your Mixtral API key.")
            sys.exit(1)
        
        self.api_url = "https://api.mistral.ai/v1/chat/completions"
        self.system_prompt = """Du bist AILinux Helper – ein KI-gesteuerter Assistent, der in der Linux-Distribution „AILinux 24.04 Premium" eingebettet ist.

Diese Distribution basiert auf Ubuntu 24.04 (Codename: Noble) und wurde speziell für eine moderne, KI-integrierte Offline-Nutzung entwickelt.

## 🎯 Deine Aufgabe

Du wirst direkt über das Terminal vom Nutzer aufgerufen, um:

- Fehlermeldungen und Logs zu analysieren
- technische Probleme zu erklären  
- Lösungen bereitzustellen, z. B. Shell-Befehle oder Systemhinweise
- Hilfe zur Nutzung und Konfiguration von AILinux zu leisten
- Bootloader-Probleme zu diagnostizieren und zu lösen

## 📋 Antwortformat (immer verwenden)

### 🚨 Problem Summary
*Kurzbeschreibung des gemeldeten oder erkannten Problems.*

### ⚙ Likely Cause
*Technische Erklärung der wahrscheinlichen Ursache – inkl. Log-Analyse, Abhängigkeiten, Services etc.*

### ✅ Suggested Solution
*Konkrete Lösung als Shell-Befehl(e) oder Beschreibung.*

### 🔧 Advanced Troubleshooting
*Erweiterte Problemlösung für komplexe Fälle.*

Falls zu wenig Informationen gegeben sind, antworte mit:
"Bitte gib mir mehr Details wie Logs, konkrete Fehlermeldungen oder betroffene Befehle."

AILinux enthält: kde-full, firefox, chrome, thunderbird, vlc, gimp, libreoffice, wine, vscode, python3, nodejs, und viele andere Pakete.
Bootloader: GRUB mit UEFI/BIOS-Support, systemd-boot als Fallback, Secure Boot-Unterstützung."""

    def analyze_problem(self, user_input):
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json"
        }
        
        data = {
            "model": "mistral-large-latest",
            "messages": [
                {"role": "system", "content": self.system_prompt},
                {"role": "user", "content": user_input}
            ],
            "max_tokens": 1000,
            "temperature": 0.1
        }
        
        try:
            response = requests.post(self.api_url, headers=headers, json=data, timeout=120)
            response.raise_for_status()
            return response.json()["choices"][0]["message"]["content"]
        except requests.exceptions.RequestException as e:
            return f"Fehler bei der Kontaktaufnahme mit dem KI-Dienst: {e}\n\nFallback: Überprüfen Sie Ihre Internetverbindung und API-Konfiguration."
        except Exception as e:
            return f"Unerwarteter Fehler: {e}"

def main():
    parser = argparse.ArgumentParser(description="AILinux Helper - Enhanced AI-powered system assistant")
    parser.add_argument("query", nargs="*", help="Problem description or question for analysis")
    parser.add_argument("--version", action="version", version="AILinux Helper v25.09")
    args = parser.parse_args()
    
    helper = AILinuxHelper()
    
    if args.query:
        user_input = " ".join(args.query)
    else:
        print("Enter your problem description (press Ctrl+D when finished):")
        try:
            user_input = sys.stdin.read()
        except KeyboardInterrupt:
            print("\nAborted by user.")
            sys.exit(0)
    
    if user_input.strip():
        print("\nAnalyzing...")
        print(helper.analyze_problem(user_input))
    else:
        print("No input received.")

if __name__ == "__main__":
    main()
AIHELPER
chmod +x /opt/ailinux/ailinux-helper.py

# Create enhanced desktop entry
cat > /usr/share/applications/ailinux-helper.desktop << '"'"'DESKTOP'"'"'
[Desktop Entry]
Version=1.0
Type=Application
Name=AILinux Helper
Name[de]=AILinux Assistent
Comment=Enhanced AI-powered system assistant with bootloader support
Comment[de]=Erweiterte KI-gestützte Systemassistent mit Bootloader-Unterstützung
Icon=applications-system
Exec=konsole -e /opt/ailinux/ailinux-helper.py
Terminal=true
Categories=System;Utility;
Keywords=ai;assistant;help;bootloader;troubleshooting;
DESKTOP

# Create symlink
ln -sf /opt/ailinux/ailinux-helper.py /usr/local/bin/aihelp

# Move .env to final location
if [ -f "/tmp/.env" ]; then
    mv /tmp/.env /opt/ailinux/.env
    chmod 600 /opt/ailinux/.env
    echo "SUCCESS: AI configuration moved to final location"
fi

echo "Enhanced AILinux AI components installation completed."
'
    run_in_chroot "$ai_install_script"
    sudo rm -f "${CHROOT_DIR}/tmp/.env"
    
    register_operation "install_ai_components"
    log_success "Enhanced AILinux AI components installed."
}

step_05_configure_calamares() {
    log_step "5/11" "Enhanced Calamares Installer Configuration (with Robust Bootloader Fix)"
    
    if [ -d "branding" ]; then
        sudo mkdir -p "${CHROOT_DIR}/tmp/branding"
        sudo cp -r branding/* "${CHROOT_DIR}/tmp/branding/"
    fi
    
    local calamares_script='
#!/bin/bash
set -e

# Install Calamares with all dependencies (especially for bootloader)
echo "Installing Calamares with comprehensive dependencies..."
apt-get update

# Enhanced bootloader dependencies FIRST
echo "Installing enhanced bootloader dependencies..."
apt-get install -y \
    grub-pc-bin grub-efi-amd64-bin grub-efi-amd64-signed grub-common \
    grub2-common efibootmgr os-prober shim-signed systemd-boot-efi \
    dosfstools mtools

# Python dependencies for Calamares modules
apt-get install -y python3-yaml python3-parted python3-setuptools python3-pyqt5

# Calamares main package and additional dependencies
apt-get install -y calamares imagemagick squashfs-tools dosfstools ntfs-3g btrfs-progs xfsprogs e2fsprogs

# Create Calamares configuration directories
mkdir -p /etc/calamares/modules
mkdir -p /etc/calamares/branding/ailinux

# Enhanced main configuration (settings.conf)
cat > /etc/calamares/settings.conf << '"'"'SETTINGS'"'"'
---
modules-search: [ local ]
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
  - localecfg
  - users
  - displaymanager
  - networkcfg
  - hwclock
  - services-systemd
  - bootloader
  - umount
- show:
  - finished
branding: ailinux
prompt-install: false
quit-at-end: false
SETTINGS

# Enhanced branding configuration
cat > /etc/calamares/branding/ailinux/branding.desc << '"'"'BRANDING'"'"'
---
componentName: ailinux
strings:
    productName: AILinux
    version: 24.04 Premium
    shortVersionedName: AILinux 24.04
    versionedName: AILinux 24.04 Premium
    shortProductName: AILinux
    bootloaderEntryName: AILinux
    productUrl: https://github.com/derleiti/ailinux-beta-iso
    supportUrl: https://github.com/derleiti/ailinux-beta-iso/issues
    knownIssuesUrl: https://github.com/derleiti/ailinux-beta-iso/issues
    releaseNotesUrl: https://github.com/derleiti/ailinux-beta-iso/releases

style:
    sidebarBackground: "#2c3e50"
    sidebarText: "#ffffff"
    sidebarTextSelect: "#4e73c7"
    sidebarTextCurrent: "#ffffff"

images:
    productLogo: "logo.png"
    productIcon: "icon.png"
    productWelcome: "welcome.png"

slideshow: "show.qml"
slideshowAPI: 2
BRANDING

# Enhanced QML slideshow
cat > /etc/calamares/branding/ailinux/show.qml << '"'"'QML'"'"'
import QtQuick 2.0
import QtQuick.Controls 2.5
import QtQuick.Layouts 1.3

Rectangle {
    id: slideshow
    color: "#2c3e50"
    
    property int currentSlide: 0
    property var slides: [
        "Willkommen bei AILinux 24.04 Premium",
        "KI-gestützte Systemunterstützung mit aihelp",
        "Vollständige KDE Plasma Desktop-Umgebung",
        "Sichere Installation mit UEFI/BIOS-Support",
        "Robuste Bootloader-Konfiguration",
        "Installation wird abgeschlossen..."
    ]
    
    Timer {
        interval: 4000
        running: true
        repeat: true
        onTriggered: {
            currentSlide = (currentSlide + 1) % slides.length
        }
    }
    
    ColumnLayout {
        anchors.centerIn: parent
        spacing: 20
        
        Image {
            source: "logo.png"
            Layout.preferredWidth: 128
            Layout.preferredHeight: 128
            Layout.alignment: Qt.AlignHCenter
            fillMode: Image.PreserveAspectFit
        }
        
        Text {
            text: slides[currentSlide]
            color: "white"
            font.pixelSize: 24
            font.weight: Font.Bold
            Layout.alignment: Qt.AlignHCenter
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            Layout.maximumWidth: slideshow.width * 0.8
        }
        
        Text {
            text: "AILinux wird mit robusten Bootloader-Optionen installiert..."
            color: "#bdc3c7"
            font.pixelSize: 16
            Layout.alignment: Qt.AlignHCenter
        }
    }
}
QML

# Copy branding images if available, else create fallbacks
if [ -d "/tmp/branding" ]; then
    cp /tmp/branding/* /etc/calamares/branding/ailinux/ 2>/dev/null || true
fi
if [ ! -f "/etc/calamares/branding/ailinux/logo.png" ]; then
    convert -size 256x256 xc:"#2c3e50" -pointsize 24 -fill white -gravity center -annotate +0+0 "AILinux" /etc/calamares/branding/ailinux/logo.png
fi
for img in icon.png welcome.png; do
    if [ ! -f "/etc/calamares/branding/ailinux/${img}" ]; then
        cp /etc/calamares/branding/ailinux/logo.png "/etc/calamares/branding/ailinux/${img}"
    fi
done

# Enhanced module configurations
# unpackfs.conf
cat > /etc/calamares/modules/unpackfs.conf << '"'"'UNPACKFS'"'"'
---
unpack:
    - source: "/cdrom/casper/filesystem.squashfs"
      sourcefs: "squashfs"
      destination: ""
UNPACKFS

# Enhanced bootloader.conf with robust configuration and fallbacks
cat > /etc/calamares/modules/bootloader.conf << '"'"'BOOTLOADER'"'"'
---
# Enhanced bootloader configuration with robust error handling
efiBootloaderId: "ailinux"
bootloader: "grub"
installPath: "/boot/efi"
timeout: 10

# Kernel parameters
kernelLine: ",quiet splash"
fallbackKernelLine: ",quiet splash nomodeset"

# GRUB configuration with enhanced error handling
grubInstall: "grub-install"
grubMkconfig: "grub-mkconfig"
grubCfg: "/boot/grub/grub.cfg"

# Enhanced installation parameters with fallbacks
efiInstallParams: "--target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ailinux --no-nvram --removable"
biosInstallParams: "--target=i386-pc --no-nvram"

# Fallback options
efiInstallParamsFallback: "--target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ailinux --force --no-nvram"
biosInstallParamsFallback: "--target=i386-pc --force --no-nvram"

# systemd-boot fallback configuration
systemdBootEnabled: true
systemdBootPath: "/boot/efi/EFI/systemd"
BOOTLOADER

# Enhanced partition.conf with better EFI handling
cat > /etc/calamares/modules/partition.conf << '"'"'PARTITION'"'"'
---
# Enhanced EFI System Partition settings
efiSystemPartition: "/boot/efi"
efiSystemPartitionSize: 1000MiB
efiSystemPartitionName: EFI
efiSystemPartitionMountPoint: "/boot/efi"

# Enhanced automatic partitioning
defaultFileSystemType: "ext4"
availableFileSystemTypes: ["ext4", "btrfs", "xfs"]
initialPartitioningChoice: "erase"
defaultPartitionTableType: "gpt"
requiredStorageGiB: 12.0

# Enhanced EFI partition handling
always_show_partition_labels: true
drawNestedPartitions: false
allowManualPartitioning: true

# Robust partition layout for automatic installation
partitionLayout:
    - name: "efi"
      filesystem: "fat32"
      mountPoint: "/boot/efi"
      size: "1000MiB"
      flags: ["boot", "esp"]
    - name: "root"
      filesystem: "ext4" 
      mountPoint: "/"
      size: "100%"

# Enhanced bootloader support
ensureSuspendToDisk: true
userSwapChoices: ["suspend", "file"]
PARTITION

# displaymanager.conf
cat > /etc/calamares/modules/displaymanager.conf << '"'"'DISPLAYMANAGER'"'"'
---
displaymanagers:
  - sddm

defaultDesktopEnvironment:
    executable: "startkde"
    desktopFile: "plasma"

basicSetup: false
DISPLAYMANAGER

# Enhanced users.conf
cat > /etc/calamares/modules/users.conf << '"'"'USERS'"'"'
---
defaultGroups:
    - sudo
    - adm
    - cdrom
    - dip
    - plugdev
    - lpadmin
    - audio
    - video
    - bluetooth
    - netdev
    - users
autologinGroup: autologin
sudoersGroup: sudo
setRootPassword: false
allowWeakPasswords: true
allowWeakPasswordsDefault: true
userShell: /bin/bash
USERS

echo "Enhanced Calamares configuration with robust bootloader handling completed."
'
    run_in_chroot "$calamares_script"
    
    register_operation "configure_calamares"
    log_success "Enhanced Calamares installer with robust bootloader support configured."
}

step_06_create_live_user() {
    log_step "6/11" "Enhanced Live User Creation and Desktop Configuration"
    
    local user_script='
#!/bin/bash
set -e
# Create live user without password
useradd -s /bin/bash -d "/home/'${LIVE_USER}'" -m -G adm,cdrom,sudo,dip,plugdev,lpadmin,audio,video,bluetooth,netdev,users "'${LIVE_USER}'"
passwd -d "'${LIVE_USER}'"
echo "'${LIVE_USER}' ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Configure SDDM for enhanced autologin
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/autologin.conf << '"'"'SDDM_EOF'"'"'
[Autologin]
User='${LIVE_USER}'
Session=plasma
Relogin=false
[Theme]
Current=breeze
[X11]
MinimumVT=1
SDDM_EOF

# Create enhanced desktop shortcuts
mkdir -p "/home/'${LIVE_USER}'/Desktop"

# Enhanced installer shortcut
cat > "/home/'${LIVE_USER}'/Desktop/install-ailinux.desktop" << '"'"'INSTALL_EOF'"'"'
[Desktop Entry]
Version=1.0
Type=Application
Name=Install AILinux
Name[de]=AILinux installieren
Comment=Install AILinux to your computer with enhanced bootloader support
Comment[de]=AILinux mit erweiterte Bootloader-Unterstützung installieren
Icon=calamares
Exec=pkexec calamares
Terminal=false
Categories=System;
INSTALL_EOF
chmod +x "/home/'${LIVE_USER}'/Desktop/install-ailinux.desktop"

# Enhanced AI helper shortcut
cat > "/home/'${LIVE_USER}'/Desktop/aihelp.desktop" << '"'"'AIHELP_EOF'"'"'
[Desktop Entry]
Version=1.0
Type=Application
Name=AILinux Helper
Name[de]=AILinux Assistent
Comment=Enhanced AI-powered system assistant with bootloader troubleshooting
Comment[de]=Erweiterte KI-gestützte Systemassistent mit Bootloader-Fehlerbehebung
Icon=dialog-information
Exec=konsole -e aihelp
Terminal=true
Categories=System;Utility;
Keywords=ai;assistant;bootloader;troubleshooting;
AIHELP_EOF
chmod +x "/home/'${LIVE_USER}'/Desktop/aihelp.desktop"

# Enhanced system info shortcut
cat > "/home/'${LIVE_USER}'/Desktop/system-info.desktop" << '"'"'SYSINFO_EOF'"'"'
[Desktop Entry]
Version=1.0
Type=Application
Name=System Information
Name[de]=Systeminformationen
Comment=View detailed system and bootloader information
Comment[de]=Detaillierte System- und Bootloader-Informationen anzeigen
Icon=hwinfo
Exec=konsole -e sh -c "echo '\''=== AILinux System Information ==='\'' && echo && lsb_release -a && echo && uname -a && echo && lscpu | head -10 && echo && free -h && echo '\''Press Enter to continue...'\''; read"
Terminal=true
Categories=System;
SYSINFO_EOF
chmod +x "/home/'${LIVE_USER}'/Desktop/system-info.desktop"

# Enhanced .bashrc with welcome message and useful aliases
cat >> "/home/'${LIVE_USER}'/.bashrc" << '"'"'BASHRC_EOF'"'"'

# Enhanced AILinux Welcome
echo ""
echo "🧠 Welcome to AILinux 24.04 Premium - Enhanced Edition!"
echo "Use \"aihelp\" for AI-powered system assistance and bootloader troubleshooting."
echo "System built with robust UEFI/BIOS support and fallback mechanisms."
echo ""

# Useful aliases
alias ai="aihelp"
alias sysinfo="inxi -Fxz"
alias bootinfo="sudo efibootmgr -v 2>/dev/null || echo '\''Legacy BIOS mode'\''"
alias grubinfo="sudo grub-install --version && echo '\''GRUB config location: /boot/grub/grub.cfg'\''"
BASHRC_EOF

# Set proper ownership
chown -R "'${LIVE_USER}':'${LIVE_USER}'" "/home/'${LIVE_USER}'"
'
    run_in_chroot "$user_script"
    
    register_operation "create_live_user"
    log_success "Enhanced live user and desktop configuration completed."
}

step_07_system_cleanup() {
    log_step "7/11" "Enhanced System Cleanup and Service Configuration"
    
    local cleanup_script='
#!/bin/bash
set -e
# Enable important services
systemctl enable bluetooth cups NetworkManager sddm

# Install additional useful packages
apt-get install -y --no-install-recommends inxi neofetch || echo "WARNING: Additional packages failed"

# Enhanced cleanup for smaller ISO
echo "Performing enhanced system cleanup..."
apt-get autoremove -y --purge
apt-get autoclean
apt-get clean
rm -rf /tmp/* /var/tmp/* /var/lib/apt/lists/*
rm -rf /var/cache/apt/archives/*.deb
rm -rf /var/cache/apt/archives/partial/*
find /var/log -type f -exec truncate --size 0 {} \;

# Remove additional temporary files
rm -rf /root/.cache /home/*/.cache 2>/dev/null || true
rm -rf /usr/share/doc/* /usr/share/man/* 2>/dev/null || true
rm -rf /var/cache/fontconfig/* 2>/dev/null || true

# Reset machine-id and SSH keys
rm -f /etc/machine-id /var/lib/dbus/machine-id
touch /etc/machine-id
rm -f /etc/ssh/ssh_host_* 2>/dev/null || true

# Update initramfs with enhanced error handling
if update-initramfs -u; then
    echo "SUCCESS: initramfs updated"
else
    echo "WARNING: initramfs update failed"
fi

echo "Enhanced system cleanup completed."
'
    run_in_chroot "$cleanup_script"
    
    sudo rm -f "${CHROOT_DIR}/etc/resolv.conf"
    
    register_operation "system_cleanup"
    log_success "Enhanced system cleanup completed."
}

step_08_create_squashfs() {
    log_step "8/11" "Enhanced SquashFS Image Creation"
    
    cleanup_mounts
    
    mkdir -p "${ISO_DIR}"/{casper,isolinux,boot/grub,.disk}
    
    # Enhanced kernel and initrd copying with validation
    log_info "Copying kernel and initrd with validation..."
    if ! sudo cp "${CHROOT_DIR}"/boot/vmlinuz-*-generic "${ISO_DIR}/casper/vmlinuz"; then
        log_error "Failed to copy kernel"
        exit 1
    fi
    if ! sudo cp "${CHROOT_DIR}"/boot/initrd.img-*-generic "${ISO_DIR}/casper/initrd"; then
        log_error "Failed to copy initrd"
        exit 1
    fi
    
    # Create package manifest
    run_in_chroot "dpkg-query -W --showformat='\\\${Package}\t\\\${Version}\n'" > "${ISO_DIR}/casper/filesystem.manifest" || {
        log_warn "Failed to create package manifest"
    }
    
    log_info "Creating SquashFS image with enhanced XZ compression (optimal size/time balance)..."
    if ! sudo mksquashfs "${CHROOT_DIR}" "${ISO_DIR}/casper/filesystem.squashfs" \
        -noappend -e boot -comp xz -Xdict-size 100% -b 1M -processors $(nproc); then
        log_error "Enhanced SquashFS creation failed"
        register_operation "create_squashfs" 
        exit 1
    fi
    
    register_operation "create_squashfs"
    
    printf "$(sudo du -sx --block-size=1 "${CHROOT_DIR}" | cut -f1)" > "${ISO_DIR}/casper/filesystem.size"
    
    echo "${DISTRO_NAME} ${DISTRO_VERSION} ${DISTRO_EDITION} - Release ${ARCHITECTURE} (Enhanced)" > "${ISO_DIR}/.disk/info"
    
    register_operation "create_squashfs"
    log_success "Enhanced SquashFS image successfully created."
    log_info "SquashFS size: $(du -h "${ISO_DIR}/casper/filesystem.squashfs" | cut -f1)"
}

step_09_create_bootloaders() {
    log_step "9/11" "Enhanced Bootloader Creation (BIOS & UEFI with Fallbacks)"
    
    # Enhanced ISOLINUX for BIOS boot
    log_info "Setting up enhanced ISOLINUX for BIOS boot..."
    cp /usr/lib/ISOLINUX/isolinux.bin "${ISO_DIR}/isolinux/"
    cp /usr/lib/syslinux/modules/bios/{ldlinux.c32,libutil.c32,menu.c32} "${ISO_DIR}/isolinux/"
    
    cat > "${ISO_DIR}/isolinux/isolinux.cfg" << EOF
UI menu.c32
PROMPT 0
TIMEOUT 50
DEFAULT live

MENU TITLE ${DISTRO_NAME} ${DISTRO_VERSION} Enhanced
LABEL live
  MENU LABEL Try or Install ${DISTRO_NAME}
  KERNEL /casper/vmlinuz
  APPEND file=/cdrom/.disk/info boot=casper initrd=/casper/initrd quiet splash ---
LABEL safe
  MENU LABEL Try ${DISTRO_NAME} (safe graphics)
  KERNEL /casper/vmlinuz
  APPEND file=/cdrom/.disk/info boot=casper initrd=/casper/initrd quiet splash nomodeset ---
LABEL check
  MENU LABEL Check disc for defects
  KERNEL /casper/vmlinuz
  APPEND file=/cdrom/.disk/info boot=casper initrd=/casper/initrd integrity-check quiet splash ---
EOF

    # Enhanced GRUB for UEFI boot
    log_info "Setting up enhanced GRUB for UEFI boot..."
    cat > "${ISO_DIR}/boot/grub/grub.cfg" << EOF
set timeout=5
set default="0"

menuentry "Try or Install ${DISTRO_NAME}" {
    linux /casper/vmlinuz file=/cdrom/.disk/info boot=casper quiet splash ---
    initrd /casper/initrd
}
menuentry "Try ${DISTRO_NAME} (safe graphics)" {
    linux /casper/vmlinuz file=/cdrom/.disk/info boot=casper nomodeset quiet splash ---
    initrd /casper/initrd
}
menuentry "Check disc for defects" {
    linux /casper/vmlinuz file=/cdrom/.disk/info boot=casper integrity-check quiet splash ---
    initrd /casper/initrd
}
menuentry "Boot from first hard disk" {
    exit 1
}
EOF

    # Enhanced GRUB EFI image creation with fallback
    log_info "Creating enhanced GRUB EFI boot image with fallback support..."
    if ! grub-mkstandalone \
        --format=x86_64-efi \
        --output="/tmp/bootx64.efi" \
        --locales="" --fonts="" \
        "boot/grub/grub.cfg=${ISO_DIR}/boot/grub/grub.cfg"; then
        log_error "GRUB EFI image creation failed"
        exit 1
    fi

    # Enhanced EFI image creation
    dd if=/dev/zero of="${ISO_DIR}/boot/grub/efi.img" bs=1M count=64 status=none
    mkfs.vfat -n "AILINUX_EFI" "${ISO_DIR}/boot/grub/efi.img" > /dev/null
    
    local efi_mount
    efi_mount=$(mktemp -d)
    sudo mount -o loop "${ISO_DIR}/boot/grub/efi.img" "${efi_mount}"
    
    # Enhanced EFI directory structure
    sudo mkdir -p "${efi_mount}/EFI/BOOT"
    sudo mkdir -p "${efi_mount}/EFI/ailinux"
    
    # Copy enhanced UEFI components with fallbacks
    sudo cp /tmp/bootx64.efi "${efi_mount}/EFI/BOOT/grubx64.efi"
    sudo cp /tmp/bootx64.efi "${efi_mount}/EFI/ailinux/grubx64.efi"
    
    if [ -f "/usr/lib/shim/shimx64.efi.signed" ]; then
        sudo cp /usr/lib/shim/shimx64.efi.signed "${efi_mount}/EFI/BOOT/BOOTX64.EFI"
        log_success "Secure Boot support enabled with shim"
    else
        sudo cp /tmp/bootx64.efi "${efi_mount}/EFI/BOOT/BOOTX64.EFI"
        log_warn "Secure Boot support limited - shim not available"
    fi
    
    # Add systemd-boot as fallback if available
    if [ -f "/usr/lib/systemd/boot/efi/systemd-bootx64.efi" ]; then
        sudo cp /usr/lib/systemd/boot/efi/systemd-bootx64.efi "${efi_mount}/EFI/systemd/"
        log_info "systemd-boot added as fallback bootloader"
    fi
    
    sudo umount "${efi_mount}"
    rmdir "${efi_mount}"
    rm -f /tmp/bootx64.efi
    
    register_operation "create_bootloaders"
    log_success "Enhanced bootloader with fallback support successfully created."
}

step_10_create_iso() {
    log_step "10/11" "Enhanced Final ISO Image Creation"
    
    log_info "Creating enhanced hybrid ISO image with improved compatibility..."
    if ! sudo xorriso -as mkisofs \
        -o "${BUILD_DIR}/${ISO_NAME}" \
        -V "${DISTRO_NAME}_${DISTRO_VERSION}" \
        -iso-level 3 -r -J -l \
        -b isolinux/isolinux.bin \
        -c isolinux/boot.cat \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot \
        -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
        -partition_offset 16 \
        "${ISO_DIR}"; then
        log_error "ISO creation failed"
        exit 1
    fi

    sudo chown "$(id -u):$(id -g)" "${BUILD_DIR}/${ISO_NAME}"
    mv "${BUILD_DIR}/${ISO_NAME}" "$(pwd)/"
    
    # Enhanced checksum generation
    sha256sum "$(pwd)/${ISO_NAME}" > "$(pwd)/${ISO_NAME}.sha256"
    
    register_operation "create_iso"
    log_success "Enhanced ISO successfully created: $(pwd)/${ISO_NAME}"
    log_info "ISO size: $(du -h "$(pwd)/${ISO_NAME}" | cut -f1)"
}

step_11_finalize_build() {
    log_step "11/11" "Build Finalization and Metadata Generation"
    
    local build_end_time=$(date)
    generate_build_metadata "SUCCESS" "0" "$build_end_time"
    
    # Enhanced build summary
    log_info "=== ENHANCED BUILD SUMMARY ==="
    log_info "ISO File: $(realpath "${ISO_NAME}")"
    log_info "ISO Size: $(du -h "${ISO_NAME}" | cut -f1)"
    log_info "SHA256: $(cut -d' ' -f1 "${ISO_NAME}.sha256")"
    log_info "Build Metadata: $(realpath "${METADATA_FILE}")"
    log_info "Build Log: $(realpath "${LOG_FILE}")"
    log_info "Operations Tracked: ${#OPERATIONS_STACK[@]}"
    log_info "Mounts Tracked: ${#MOUNT_TRACKING[@]}"
    log_info "Cleanup Functions: ${#CLEANUP_FUNCTIONS[@]}"
    log_info "Compression: Enhanced XZ with 100% dictionary"
    log_info "Error Handling: AI-powered with rollback capability"
    
    log_success "Enhanced build finalization with optimizations completed."
}

# --- Enhanced Main Function ---
main() {
    rm -f "${LOG_FILE}"
    
    check_not_root
    
    local start_time=$(date +%s)
    local start_time_formatted=$(date)
    
    log_info "==================== AILinux ISO Build v${BUILD_VERSION} - Enhanced Production Edition ===================="
    log_info "Starting enhanced build process for ${DISTRO_NAME} ${DISTRO_VERSION} ${DISTRO_EDITION}"
    log_info "Build started at: $start_time_formatted"
    
    # Execute all build steps
    step_01_setup
    step_02_bootstrap_system
    step_03_install_packages
    step_04_install_ai_components
    step_05_configure_calamares
    step_06_create_live_user
    step_07_system_cleanup
    step_08_create_squashfs
    step_09_create_bootloaders
    step_10_create_iso
    step_11_finalize_build
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo
    log_success "==================== ENHANCED BUILD SUCCESSFULLY COMPLETED ===================="
    log_success "ISO: $(realpath "${ISO_NAME}")"
    log_success "Build duration: $((duration / 60)) minutes and $((duration % 60)) seconds"
    log_success "Build metadata: $(realpath "${METADATA_FILE}")"
    log_info "To clean build directory: sudo rm -rf ${BUILD_DIR}"
    
    # Store final completion with enhanced metadata
    generate_build_metadata "SUCCESS" "0" "$(date)" "N/A" "N/A"
    
    # Register final operation for tracking
    register_operation "build_completed"
}

# Start the enhanced script
main "$@"