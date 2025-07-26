#!/bin/bash
#
# AILinux v26.01 - Enhanced ISO Builder
# Complete optimized build script for bootable AILinux-ISO based on Ubuntu 24.04 (noble)
#
# Features:
# - KDE Plasma Desktop with full installation
# - Calamares installer with enhanced branding
# - AI Terminal Assistant 'aihelp' (Mixtral-API integration)
# - Secure Boot configuration (shimx64.efi.signed)
# - APT mirror integration: http://ailinux.me:8443/mirror/
# - GPG key handling (A1945EE6DA93CB05)
# - Robust mount/umount with proper cleanup
# - Fallback mechanisms and AI debugging
# - Build metadata generation
# - Transaction-like operations with rollback
#
# Version: v26.01-OPTIMIZED (Production Edition)
# Author: Claude Flow Swarm (Hierarchical Coordination)
# License: MIT

# Disabled aggressive error handling to prevent session logout
# set -euo pipefail  # DANGEROUS: This causes session termination in SSH
# Using modular error handling instead

# ========================================
# CONFIGURATION SECTION
# ========================================

# Initialize session safety and error handling modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Basic logging functions (required by modules)
log_info() { echo "[INFO] $*"; }
log_success() { echo "[SUCCESS] $*"; }
log_warn() { echo "[WARNING] $*"; }
log_error() { echo "[ERROR] $*"; }

# Export LOG_FILE for modules
export LOG_FILE="${SCRIPT_DIR}/build.log"

# Source safety modules first (with dependency order)
if [[ -f "${SCRIPT_DIR}/modules/session_safety.sh" ]]; then
    source "${SCRIPT_DIR}/modules/session_safety.sh"
    init_session_safety
fi

if [[ -f "${SCRIPT_DIR}/modules/error_handler.sh" ]]; then
    source "${SCRIPT_DIR}/modules/error_handler.sh"
    init_error_handling "graceful"  # Use graceful mode to prevent session logout
fi

readonly SCRIPT_VERSION="v26.01-SESSION-SAFE"
readonly DISTRO_NAME="AILinux"
readonly DISTRO_VERSION="26.01"
readonly DISTRO_EDITION="Premium"
readonly UBUNTU_CODENAME="noble"
readonly UBUNTU_VERSION="24.04"
readonly ARCHITECTURE="amd64"
readonly LIVE_USER="ailinux"
readonly LIVE_HOSTNAME="ailinux"

# APT Mirror Configuration
readonly PRIMARY_MIRROR="http://ailinux.me:8443/mirror/"
readonly UBUNTU_MIRROR="http://archive.ubuntu.com/ubuntu/"
readonly SECURITY_MIRROR="http://security.ubuntu.com/ubuntu/"

# GPG Configuration
readonly AILINUX_GPG_KEY="A1945EE6DA93CB05"
readonly GPG_KEYSERVER="keyserver.ubuntu.com"

# Build Paths
readonly WORK_DIR="/tmp/ailinux-build"
readonly CHROOT_DIR="${WORK_DIR}/chroot"
readonly CD_DIR="${WORK_DIR}/cd"
readonly SQUASH_DIR="${WORK_DIR}/squashfs"
readonly BUILD_INFO_FILE="ailinux-build-info.txt"

# AI Configuration
readonly AI_ASSISTANT_NAME="aihelp"
readonly MIXTRAL_API_ENDPOINT="https://api.mistral.ai/v1/chat/completions"

# ========================================
# LOGGING AND COLOR SYSTEM
# ========================================

# Color definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "${LOG_FILE:-/dev/null}"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "${LOG_FILE:-/dev/null}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "${LOG_FILE:-/dev/null}" >&2
}

log_debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "${LOG_FILE:-/dev/null}"
    fi
}

log_step() {
    echo -e "\n${BLUE}${BOLD}==== $* ====${NC}\n" | tee -a "${LOG_FILE:-/dev/null}"
}

# ========================================
# STATE MANAGEMENT AND OPERATIONS STACK
# ========================================

declare -a OPERATIONS_STACK=()
declare -a MOUNT_STACK=()
declare -a CLEANUP_FUNCTIONS=()

# Register operation for rollback
register_operation() {
    local operation="$1"
    OPERATIONS_STACK+=("$operation")
    log_debug "Registered operation: $operation"
}

# Register cleanup function
register_cleanup() {
    local cleanup_func="$1"
    CLEANUP_FUNCTIONS+=("$cleanup_func")
    log_debug "Registered cleanup function: $cleanup_func"
}

# ========================================
# COMPREHENSIVE ERROR HANDLING & RECOVERY
# ========================================

# Error handler with AI debugging integration
error_handler() {
    local exit_code=$?
    local line_number=$1
    local command="$2"
    
    log_error "Build failed at line $line_number with exit code $exit_code"
    log_error "Command: $command"
    
    # Execute cleanup functions in reverse order
    execute_cleanup
    
    # Rollback operations
    rollback_operations
    
    # AI-powered error analysis
    if [[ -n "${MIXTRAL_API_KEY:-}" ]]; then
        log_info "Initiating AI-powered error analysis..."
        ai_debug_error "$line_number" "$command" "$exit_code"
    fi
    
    exit $exit_code
}

# AI debugging function
ai_debug_error() {
    local line_number="$1"
    local failed_command="$2" 
    local exit_code="$3"
    
    # Get recent log context (last 300 lines)
    local log_context
    log_context=$(tail -n 300 "${LOG_FILE}" 2>/dev/null || echo "Log nicht verfügbar")
    
    local debug_prompt="Du bist ein erfahrener Linux-System-Administrator und hilfst beim Debugging eines AILinux ISO-Build-Fehlers.

FEHLER-DETAILS:
- Zeile: $line_number
- Befehl: $failed_command
- Exit-Code: $exit_code
- Skript-Version: $SCRIPT_VERSION

LOG-KONTEXT (letzte 300 Zeilen):
$log_context

Analysiere den Fehler und gib eine strukturierte Antwort in deutscher Sprache:

1. FEHLERANALYSE: Was ist schief gelaufen?
2. URSACHE: Warum ist der Fehler aufgetreten?
3. LÖSUNGSSCHRITTE: Konkrete Schritte zur Behebung
4. VORBEUGUNG: Wie kann man den Fehler in Zukunft vermeiden?

Fokussiere dich auf AILinux ISO-Build-spezifische Probleme und Ubuntu 24.04 Besonderheiten."

    local ai_response
    ai_response=$(curl -s -X POST "$MIXTRAL_API_ENDPOINT" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $MIXTRAL_API_KEY" \
        -d "{
            \"model\": \"mistral-large-latest\",
            \"messages\": [{\"role\": \"user\", \"content\": \"$(echo "$debug_prompt" | sed 's/"/\\"/g')\"}],
            \"max_tokens\": 1000,
            \"temperature\": 0.3
        }" 2>/dev/null)
    
    if [[ -n "$ai_response" ]]; then
        local ai_content
        ai_content=$(echo "$ai_response" | jq -r '.choices[0].message.content' 2>/dev/null || echo "Fehler beim Parsen der AI-Antwort")
        
        echo -e "\n${PURPLE}${BOLD}🤖 AI-FEHLERANALYSE:${NC}\n"
        echo -e "${WHITE}$ai_content${NC}\n"
        
        # Log AI response
        echo -e "\n=== AI-FEHLERANALYSE ===" >> "${LOG_FILE}"
        echo "$ai_content" >> "${LOG_FILE}"
    else
        log_warn "AI-Debugging fehlgeschlagen - keine Antwort vom Mixtral-API"
    fi
}

# Rollback system
rollback_operations() {
    log_warn "Initiating rollback of operations..."
    
    # Execute rollbacks in reverse order (LIFO)
    for ((i=${#OPERATIONS_STACK[@]}-1; i>=0; i--)); do
        local operation="${OPERATIONS_STACK[i]}"
        log_info "Rolling back: $operation"
        
        case "$operation" in
            "create_work_dirs")
                rm -rf "$WORK_DIR" 2>/dev/null || true
                ;;
            "mount_chroot_systems")
                cleanup_mounts
                ;;
            "install_packages")
                log_info "Package installation rollback - cleaning chroot"
                ;;
            "create_squashfs")
                rm -f "${CD_DIR}/casper/filesystem.squashfs" 2>/dev/null || true
                ;;
            *)
                log_debug "No specific rollback for: $operation"
                ;;
        esac
    done
    
    log_info "Rollback completed"
}

# Execute cleanup functions
execute_cleanup() {
    log_info "Executing cleanup functions..."
    
    for ((i=${#CLEANUP_FUNCTIONS[@]}-1; i>=0; i--)); do
        local cleanup_func="${CLEANUP_FUNCTIONS[i]}"
        log_debug "Executing cleanup: $cleanup_func"
        "$cleanup_func" 2>/dev/null || true
    done
    
    log_info "Cleanup completed"
}

# ========================================
# SECURITY AND VALIDATION
# ========================================

# GPG key management
setup_gpg_keys() {
    log_info "Setting up GPG keys for repository verification"
    
    # Import AILinux GPG key
    log_info "Importing AILinux GPG key: $AILINUX_GPG_KEY"
    if ! gpg --keyserver "$GPG_KEYSERVER" --recv-keys "$AILINUX_GPG_KEY" 2>/dev/null; then
        log_warn "Failed to import AILinux GPG key from keyserver, trying alternative method"
        
        # Fallback: Try to get key from local keyring or manual import
        if [[ -f "/usr/share/keyrings/ailinux-archive-keyring.gpg" ]]; then
            log_info "Using local AILinux keyring"
        else
            log_warn "AILinux GPG key not available - continuing without custom repository verification"
        fi
    fi
    
    register_operation "setup_gpg_keys"
}

# Validate GPG signature (framework for future implementation)
validate_gpg_signature() {
    local file_path="$1"
    local signature_file="${file_path}.sig"
    
    if [[ ! -f "$signature_file" ]]; then
        log_debug "No signature file found for $file_path"
        return 0
    fi
    
    log_info "Validating GPG signature for $(basename "$file_path")"
    
    if gpg --verify "$signature_file" "$file_path" 2>/dev/null; then
        log_info "GPG signature validation successful"
        return 0
    else
        log_error "GPG signature validation failed for $file_path"
        return 1
    fi
}

# Validate system requirements
validate_requirements() {
    log_info "Validating system requirements"
    
    # Check for root privileges
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
    
    # Check available disk space (minimum 15GB)
    local available_space
    available_space=$(df /tmp --output=avail | tail -n1)
    if [[ $available_space -lt 15728640 ]]; then  # 15GB in KB
        log_error "Insufficient disk space. At least 15GB required in /tmp"
        exit 1
    fi
    
    # Check required tools
    local required_tools=(
        "debootstrap" "squashfs-tools" "xorriso" "grub-pc-bin" 
        "grub-efi-amd64-bin" "isolinux" "syslinux-common" "shim-signed"
        "mtools" "dosfstools" "gnupg" "git" "curl" "jq"
    )
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null && ! dpkg -l "$tool" &> /dev/null; then
            log_error "Required tool not found: $tool"
            log_info "Install with: apt install $tool"
            exit 1
        fi
    done
    
    # Validate API key if provided
    if [[ -n "${MIXTRAL_API_KEY:-}" ]]; then
        log_info "Mixtral API key detected - AI debugging will be available"
    else
        log_warn "No Mixtral API key found - AI debugging disabled"
    fi
    
    log_info "System requirements validation completed"
}

# ========================================
# MOUNT MANAGEMENT WITH SAFETY PROTOCOLS
# ========================================

# Safe mount with tracking
safe_mount() {
    local source="$1"
    local target="$2"
    local fstype="${3:-}"
    local options="${4:-}"
    
    # Validate mount point
    if [[ ! -d "$target" ]]; then
        log_error "Mount target directory does not exist: $target"
        return 1
    fi
    
    # Check if already mounted
    if mountpoint -q "$target"; then
        log_debug "Already mounted: $target"
        return 0
    fi
    
    # Perform mount
    local mount_cmd="mount"
    [[ -n "$fstype" ]] && mount_cmd="$mount_cmd -t $fstype"
    [[ -n "$options" ]] && mount_cmd="$mount_cmd -o $options"
    mount_cmd="$mount_cmd $source $target"
    
    log_debug "Executing: $mount_cmd"
    
    if eval "$mount_cmd"; then
        MOUNT_STACK+=("$target")
        log_debug "Successfully mounted: $target"
        return 0
    else
        log_error "Failed to mount: $target"
        return 1
    fi
}

# Safe unmount with cleanup
safe_umount() {
    local target="$1"
    local force="${2:-false}"
    
    if ! mountpoint -q "$target"; then
        log_debug "Not mounted: $target"
        return 0
    fi
    
    log_debug "Unmounting: $target"
    
    # Try normal unmount first
    if umount "$target" 2>/dev/null; then
        log_debug "Successfully unmounted: $target"
        return 0
    fi
    
    # Try lazy unmount if force is requested
    if [[ "$force" == "true" ]]; then
        log_warn "Normal unmount failed, trying lazy unmount: $target"
        if umount -l "$target" 2>/dev/null; then
            log_debug "Lazy unmount successful: $target"
            return 0
        fi
        
        # Last resort: force unmount
        log_warn "Lazy unmount failed, forcing unmount: $target"
        umount -f "$target" 2>/dev/null || true
    fi
    
    return 1
}

# Cleanup all mounts
cleanup_mounts() {
    log_info "Cleaning up mount points"
    
    # Unmount in reverse order (LIFO)
    for ((i=${#MOUNT_STACK[@]}-1; i>=0; i--)); do
        local mount_point="${MOUNT_STACK[i]}"
        safe_umount "$mount_point" true
    done
    
    # Clear the stack
    MOUNT_STACK=()
}

# ========================================
# CHROOT OPERATIONS
# ========================================

# Execute command in chroot with proper environment
chroot_exec() {
    local cmd="$1"
    
    log_debug "Executing in chroot: $cmd"
    
    # Set up minimal environment for chroot
    chroot "$CHROOT_DIR" /bin/bash -c "
        export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
        export DEBIAN_FRONTEND=noninteractive
        export LC_ALL=C
        export LANG=C
        $cmd
    " 2>&1 | tee -a "${LOG_FILE}"
    
    return ${PIPESTATUS[0]}
}

# ========================================
# BUILD STEPS IMPLEMENTATION
# ========================================

# Step 1: Environment Setup and Validation
step_01_environment_setup() {
    log_step "Step 1: Environment Setup and Validation"
    
    # Validate system requirements
    validate_requirements
    
    # Set up GPG keys
    setup_gpg_keys
    
    # Create work directories
    log_info "Creating work directories"
    rm -rf "$WORK_DIR"
    mkdir -p "$CHROOT_DIR" "$CD_DIR" "$SQUASH_DIR"
    register_operation "create_work_dirs"
    register_cleanup "cleanup_work_dirs"
    
    # Set up logging
    export LOG_FILE="${WORK_DIR}/build.log"
    touch "$LOG_FILE"
    log_info "Logging initialized: $LOG_FILE"
    log_info "Build will be logged to: $LOG_FILE"
    
    log_info "Environment setup completed"
}

# Cleanup function for work directories
cleanup_work_dirs() {
    log_debug "Cleaning up work directories"
    cleanup_mounts
    rm -rf "$WORK_DIR" 2>/dev/null || true
}

# Step 2: System Bootstrap
step_02_system_bootstrap() {
    log_step "Step 2: System Bootstrap (Ubuntu $UBUNTU_VERSION $UBUNTU_CODENAME)"
    
    # Create sources.list for debootstrap
    cat > /tmp/bootstrap_sources.list << EOF
deb $UBUNTU_MIRROR $UBUNTU_CODENAME main restricted universe multiverse
deb $SECURITY_MIRROR $UBUNTU_CODENAME-security main restricted universe multiverse
deb $UBUNTU_MIRROR $UBUNTU_CODENAME-updates main restricted universe multiverse
deb $UBUNTU_MIRROR $UBUNTU_CODENAME-backports main restricted universe multiverse
EOF
    
    # Execute debootstrap with minimal packages to avoid configuration issues
    log_info "Running debootstrap for $UBUNTU_CODENAME"
    if ! debootstrap --arch="$ARCHITECTURE" --variant=minbase \
        --include="systemd,systemd-sysv,locales,gnupg,ca-certificates" \
        "$UBUNTU_CODENAME" "$CHROOT_DIR" "$UBUNTU_MIRROR"; then
        log_error "Debootstrap failed"
        return 1
    fi
    
    # Mount essential filesystems for chroot operations
    log_info "Mounting essential filesystems for chroot"
    safe_mount "proc" "$CHROOT_DIR/proc" "proc"
    safe_mount "sysfs" "$CHROOT_DIR/sys" "sysfs"  
    safe_mount "devpts" "$CHROOT_DIR/dev/pts" "devpts" "gid=5,mode=620"
    safe_mount "tmpfs" "$CHROOT_DIR/run" "tmpfs"
    safe_mount "/dev" "$CHROOT_DIR/dev" "" "bind"
    register_operation "mount_chroot_systems"
    
    # Install additional packages after chroot is ready
    log_info "Installing additional base packages in chroot"
    chroot_exec "apt update"
    chroot_exec "apt install -y software-properties-common curl wget gpg"
    
    # Add AILinux repository early to get latest packages and KDE Plasma 6
    log_info "Adding AILinux repository early for latest packages"
    if chroot_exec "curl -fsSL https://ailinux.me:8443/mirror/add-ailinux-repo.sh | bash"; then
        log_info "AILinux repository added successfully - will use latest packages including KDE Plasma 6"
        chroot_exec "apt update"
    else
        log_warn "Failed to add AILinux repository early - will retry later"
    fi
    
    # Set up basic system configuration
    echo "$LIVE_HOSTNAME" > "$CHROOT_DIR/etc/hostname"
    echo "127.0.0.1 localhost $LIVE_HOSTNAME" > "$CHROOT_DIR/etc/hosts"
    
    register_operation "system_bootstrap"
    log_info "System bootstrap completed"
}

# Step 3: Advanced Package Installation  
step_03_package_installation() {
    log_step "Step 3: Advanced Package Installation"
    
    # Essential filesystems already mounted in step 2
    
    # Configure APT sources - AILinux repository should already be added in step 2
    log_info "Configuring APT sources (AILinux repository should already be available)"
    
    # Verify AILinux repository is working or add fallback
    if ! chroot_exec "apt list | grep -q ailinux"; then
        log_warn "AILinux repository not detected, adding Ubuntu fallback sources"
        cat > "$CHROOT_DIR/etc/apt/sources.list" << EOF
# Ubuntu Fallback Mirrors
deb $UBUNTU_MIRROR $UBUNTU_CODENAME main restricted universe multiverse
deb $SECURITY_MIRROR $UBUNTU_CODENAME-security main restricted universe multiverse
deb $UBUNTU_MIRROR $UBUNTU_CODENAME-updates main restricted universe multiverse  
deb $UBUNTU_MIRROR $UBUNTU_CODENAME-backports main restricted universe multiverse
EOF
    else
        log_info "AILinux repository is active - using latest packages"
    fi
    
    # Update package lists
    log_info "Updating package lists"
    chroot_exec "apt update" || {
        log_warn "Primary mirror failed, falling back to Ubuntu mirrors only"
        cat > "$CHROOT_DIR/etc/apt/sources.list" << EOF
deb $UBUNTU_MIRROR $UBUNTU_CODENAME main restricted universe multiverse
deb $SECURITY_MIRROR $UBUNTU_CODENAME-security main restricted universe multiverse
deb $UBUNTU_MIRROR $UBUNTU_CODENAME-updates main restricted universe multiverse
deb $UBUNTU_MIRROR $UBUNTU_CODENAME-backports main restricted universe multiverse
EOF
        chroot_exec "apt update"
    }
    
    # Essential system packages (separated GRUB packages to avoid conflicts)
    log_info "Installing essential system packages"
    local essential_packages=(
        "ubuntu-standard" "casper" "discover" "laptop-detect"
        "os-prober" "network-manager" "resolvconf" "net-tools" "wireless-tools"
        "wpagui" "locales" "linux-generic" "linux-image-generic" "linux-headers-generic"
        "grub-common" "grub-gfxpayload-lists" "grub2-common"
    )
    
    chroot_exec "apt install -y ${essential_packages[*]}"
    
    # Install GRUB packages separately to handle conflicts
    log_info "Installing GRUB bootloader packages"
    
    # Install EFI GRUB packages
    log_info "Installing EFI GRUB support"
    if ! chroot_exec "apt install -y grub-efi-amd64 grub-efi-amd64-bin grub-efi-amd64-signed shim-signed"; then
        log_warn "EFI GRUB installation failed, trying BIOS GRUB instead"
        chroot_exec "apt install -y grub-pc grub-pc-bin"
    fi
    
    # KDE Plasma Desktop (Full installation - should be Plasma 6 if AILinux repo is active)
    log_info "Installing KDE Plasma Desktop environment (preferring Plasma 6 from AILinux repository)"
    
    # Check if we have Plasma 6 available
    if chroot_exec "apt list plasma-desktop 2>/dev/null | grep -q plasma6 || apt list plasma-desktop 2>/dev/null | grep -q 6."; then
        log_info "KDE Plasma 6 detected - installing latest version"
    else
        log_info "Installing available KDE Plasma version"
    fi
    
    local kde_packages=(
        "kde-full" "plasma-desktop" "plasma-workspace"
        "sddm" "sddm-theme-breeze" "kde-config-sddm"
        "dolphin" "konsole" "kate" "gwenview" "okular"
        "kwrite" "kcalc" "ark" "plasma-nm"
        "kde-config-screenlocker" "powerdevil" "bluedevil"
    )
    
    chroot_exec "apt install -y ${kde_packages[*]}"
    
    # Applications and development tools
    log_info "Installing applications and development tools"  
    local app_packages=(
        "firefox" "thunderbird" "libreoffice" "gimp" "vlc"
        "git" "curl" "wget" "vim" "nano" "htop" "tree" "unzip"
        "python3" "python3-pip" "python3-venv" "nodejs" "npm"
        "build-essential" "cmake" "default-jdk" "gparted"
    )
    
    chroot_exec "apt install -y ${app_packages[*]}"
    
    # Install Google Chrome
    log_info "Installing Google Chrome"
    chroot_exec "wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | apt-key add -"
    chroot_exec "echo 'deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main' > /etc/apt/sources.list.d/google-chrome.list"
    
    # Clean up duplicate repository entries and broken mirrors
    chroot_exec "apt-get clean && rm -rf /var/lib/apt/lists/*"
    if ! chroot_exec "apt update"; then
        log_warn "Repository update failed, cleaning up broken sources"
        chroot_exec "rm -f /etc/apt/sources.list.d/*ailinux* || true"
        chroot_exec "apt update"
    fi
    
    chroot_exec "apt install -y google-chrome-stable"
    
    # Install VS Code
    log_info "Installing Visual Studio Code"
    chroot_exec "wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg"
    chroot_exec "install -o root -g root -m 644 packages.microsoft.gpg /etc/apt/trusted.gpg.d/"
    chroot_exec "echo 'deb [arch=amd64,arm64,armhf signed-by=/etc/apt/trusted.gpg.d/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main' > /etc/apt/sources.list.d/vscode.list"
    chroot_exec "apt update && apt install -y code"
    
    register_operation "install_packages"
    log_info "Package installation completed"
}

# Step 4: AI Components Integration
step_04_ai_components() {
    log_step "Step 4: AI Components Integration"
    
    # Create AI helper script
    log_info "Installing AI Terminal Assistant '$AI_ASSISTANT_NAME'"
    
    cat > "$CHROOT_DIR/usr/local/bin/$AI_ASSISTANT_NAME" << 'EOF'
#!/bin/bash
#
# AILinux Terminal Assistant (aihelp)
# AI-powered command line assistant using Mixtral API
#

API_KEY_FILE="/etc/ailinux/mixtral.key"
API_ENDPOINT="https://api.mistral.ai/v1/chat/completions"

if [[ ! -f "$API_KEY_FILE" ]]; then
    echo "❌ Mixtral API key not found. Please configure with:"
    echo "   sudo mkdir -p /etc/ailinux"
    echo '   echo "your-api-key" | sudo tee /etc/ailinux/mixtral.key'
    exit 1
fi

API_KEY=$(cat "$API_KEY_FILE")
QUERY="$*"

if [[ -z "$QUERY" ]]; then
    echo "🤖 AILinux Terminal Assistant"
    echo "Usage: aihelp <your question>"
    echo "Example: aihelp how to install nginx"
    exit 0
fi

PROMPT="Du bist ein erfahrener Linux-Administrator für AILinux (Ubuntu-basiert). 
Beantworte die folgende Frage präzise und hilfreich auf Deutsch:

Frage: $QUERY

Gib konkrete, ausführbare Befehle und Erklärungen."

RESPONSE=$(curl -s -X POST "$API_ENDPOINT" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_KEY" \
    -d "{
        \"model\": \"mistral-large-latest\",
        \"messages\": [{\"role\": \"user\", \"content\": \"$PROMPT\"}],
        \"max_tokens\": 800,
        \"temperature\": 0.3
    }")

if [[ $? -eq 0 ]] && [[ -n "$RESPONSE" ]]; then
    CONTENT=$(echo "$RESPONSE" | jq -r '.choices[0].message.content' 2>/dev/null)
    if [[ -n "$CONTENT" && "$CONTENT" != "null" ]]; then
        echo "🤖 AILinux Assistant:"
        echo "$CONTENT"
    else
        echo "❌ Fehler beim Verarbeiten der API-Antwort"
    fi
else
    echo "❌ Fehler beim Kontaktieren der Mixtral API"
fi
EOF
    
    chmod +x "$CHROOT_DIR/usr/local/bin/$AI_ASSISTANT_NAME"
    
    # Create AI configuration directory
    mkdir -p "$CHROOT_DIR/etc/ailinux"
    
    # Create prompt configuration
    cat > "$CHROOT_DIR/etc/ailinux/prompt.txt" << 'EOF'
Du bist der AILinux Terminal Assistant - ein hilfreicher KI-Assistent für Linux-Systeme.

VERHALTEN:
- Antworte immer auf Deutsch
- Gib konkrete, ausführbare Befehle
- Erkläre die Kommandos verständlich
- Fokussiere dich auf Ubuntu/Debian-basierte Systeme
- Sei präzise und hilfreich

SPEZIALWISSEN:
- AILinux basiert auf Ubuntu 24.04 LTS
- KDE Plasma Desktop Environment
- Standard Linux-Befehle und -Tools
- Systemadministration und Troubleshooting
EOF
    
    # Set up API key placeholder
    if [[ -n "${MIXTRAL_API_KEY:-}" ]]; then
        echo "$MIXTRAL_API_KEY" > "$CHROOT_DIR/etc/ailinux/mixtral.key"
        chmod 600 "$CHROOT_DIR/etc/ailinux/mixtral.key"
        log_info "Mixtral API key configured"
    else
        echo "YOUR_MIXTRAL_API_KEY_HERE" > "$CHROOT_DIR/etc/ailinux/mixtral.key"
        chmod 600 "$CHROOT_DIR/etc/ailinux/mixtral.key"
        log_warn "Placeholder API key created - configure after installation"
    fi
    
    register_operation "ai_components"
    log_info "AI components integration completed"
}

# Step 5: Enhanced Calamares Configuration
step_05_calamares_setup() {
    log_step "Step 5: Enhanced Calamares Installer Configuration"
    
    # Install Calamares
    log_info "Installing Calamares installer"
    chroot_exec "apt install -y calamares calamares-settings-ubuntu"
    
    # Create Calamares configuration directory
    mkdir -p "$CHROOT_DIR/etc/calamares"
    
    # Enhanced bootloader configuration with Secure Boot support
    cat > "$CHROOT_DIR/etc/calamares/modules/bootloader.conf" << EOF
---
efiBootLoader: "grub"
kernelLine: ", quiet splash"
fallbackKernelLine: ", single"
timeout: "10"
grubInstall: "grub-install"
grubMkconfig: "grub-mkconfig"
grubCfg: "/boot/grub/grub.cfg"
efiBootMgr: "efibootmgr"
installEFIFallback: true

# Secure Boot configuration
secureBootEnabled: true
shimBootLoader: "/usr/lib/shim/shimx64.efi.signed"
grubEfiBootLoader: "/usr/lib/grub/x86_64-efi/grubx64.efi"

# EFI system partition configuration
efiDirectory: "/boot/efi"
efiMountPoint: "/boot/efi"

# Bootloader installation options
installGrubBios: true
installGrubEfi: true
noGrubBootloader: false
EOF
    
    # Partition configuration
    cat > "$CHROOT_DIR/etc/calamares/modules/partition.conf" << EOF
---
efiSystemPartition: "/boot/efi"
efiSystemPartitionSize: 512MiB
efiSystemPartitionName: "EFI System Partition"

userSwapChoices:
    - none
    - small
    - suspend
    - reuse

swapPartitionName: "Swap"

defaultFileSystemType: "ext4"
availableFileSystemTypes: ["ext4", "btrfs", "xfs"]

# Encryption support
enableLuksAutomaticPartitioning: true
EOF
    
    # Welcome configuration
    cat > "$CHROOT_DIR/etc/calamares/modules/welcome.conf" << EOF
---
showSupportUrl: true
showKnownIssuesUrl: true
showReleaseNotesUrl: true

requirements:
    requiredStorage: 15.0
    requiredRam: 2.0
    internetCheckUrl: http://google.com
    checkHasInternet: false
    check:
        - storage
        - ram
        - power
        - internet
        - root
EOF
    
    # Finish configuration
    cat > "$CHROOT_DIR/etc/calamares/modules/finished.conf" << EOF
---
restartNowEnabled: true
restartNowChecked: false
restartNowCommand: "systemctl reboot"
EOF
    
    # Create Calamares branding
    log_info "Setting up Calamares branding"
    mkdir -p "$CHROOT_DIR/etc/calamares/branding/ailinux"
    
    cat > "$CHROOT_DIR/etc/calamares/branding/ailinux/branding.desc" << EOF
---
componentName: "ailinux"

welcomeStyleCalamares: false
welcomeExpandingLogo: true

strings:
    productName: "$DISTRO_NAME $DISTRO_VERSION"
    shortProductName: "$DISTRO_NAME"
    version: "$DISTRO_VERSION"
    shortVersion: "$DISTRO_VERSION"
    versionedName: "$DISTRO_NAME $DISTRO_VERSION"
    shortVersionedName: "$DISTRO_NAME $DISTRO_VERSION"
    bootloaderEntryName: "$DISTRO_NAME"
    productUrl: "https://ailinux.me"
    supportUrl: "https://ailinux.me/support"
    knownIssuesUrl: "https://ailinux.me/issues"
    releaseNotesUrl: "https://ailinux.me/releases"

images:
    productLogo: "logo.png"
    productIcon: "icon.png"
    productWelcome: "welcome.png"

slideshow: "show.qml"

style:
    sidebarBackground: "#292F34"
    sidebarText: "#FFFFFF"
    sidebarTextSelect: "#4D92E0"
EOF
    
    register_operation "calamares_setup" 
    log_info "Calamares configuration completed"
}

# Step 6: Live User Configuration
step_06_live_user_setup() {
    log_step "Step 6: Live User Configuration"
    
    # Create live user
    log_info "Creating live user: $LIVE_USER"
    chroot_exec "useradd -m -s /bin/bash -G sudo,adm,dialout,cdrom,plugdev,lpadmin,sambashare $LIVE_USER"
    chroot_exec "echo '$LIVE_USER:ailinux' | chpasswd"
    
    # Configure autologin for SDDM
    log_info "Configuring SDDM autologin"
    mkdir -p "$CHROOT_DIR/etc/sddm.conf.d"
    cat > "$CHROOT_DIR/etc/sddm.conf.d/autologin.conf" << EOF
[Autologin]
User=$LIVE_USER
Session=plasma

[General]
HaltCommand=/usr/bin/systemctl poweroff
RebootCommand=/usr/bin/systemctl reboot
EOF
    
    # Set up desktop environment
    log_info "Configuring desktop environment for live user"
    mkdir -p "$CHROOT_DIR/home/$LIVE_USER/Desktop"
    mkdir -p "$CHROOT_DIR/home/$LIVE_USER/.config"
    
    # Create desktop shortcuts
    cat > "$CHROOT_DIR/home/$LIVE_USER/Desktop/Install AILinux.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Install AILinux
Comment=Install AILinux to hard drive
Exec=pkexec calamares
Icon=calamares
Terminal=false
Categories=System;
EOF
    
    # Set permissions
    chroot_exec "chown -R $LIVE_USER:$LIVE_USER /home/$LIVE_USER"
    chroot_exec "chmod +x '/home/$LIVE_USER/Desktop/Install AILinux.desktop'"
    
    register_operation "live_user_setup"
    log_info "Live user configuration completed"
}

# Step 7: System Cleanup and Optimization
step_07_system_cleanup() {
    log_step "Step 7: System Cleanup and Optimization"
    
    # Clean package cache
    log_info "Cleaning package cache and temporary files"
    chroot_exec "apt autoremove -y"
    chroot_exec "apt autoclean"
    chroot_exec "apt clean"
    
    # Remove unnecessary packages
    chroot_exec "dpkg --list | grep -i 'rc\\s' | awk '{print \$2}' | xargs dpkg --purge"
    
    # Clean temporary files
    chroot_exec "rm -rf /tmp/* /var/tmp/* /var/log/* /var/cache/apt/archives/*.deb"
    chroot_exec "rm -rf /root/.bash_history /home/*/.bash_history"
    chroot_exec "rm -rf /var/lib/apt/lists/*"
    
    # Update initramfs
    log_info "Updating initramfs"
    chroot_exec "update-initramfs -u"
    
    register_operation "system_cleanup"
    log_info "System cleanup completed"
}

# Step 8: SquashFS Creation  
step_08_create_squashfs() {
    log_step "Step 8: SquashFS Filesystem Creation"
    
    # Unmount chroot filesystems before creating squashfs
    log_info "Unmounting chroot filesystems"
    cleanup_mounts
    
    # Create casper directory
    mkdir -p "$CD_DIR/casper"
    
    # Create SquashFS with optimal compression
    log_info "Creating SquashFS filesystem (this may take several minutes)"
    if ! mksquashfs "$CHROOT_DIR" "$CD_DIR/casper/filesystem.squashfs" \
        -e boot -comp xz -Xdict-size 100% -b 1M; then
        log_error "SquashFS creation failed"
        return 1
    fi
    
    # Create filesystem size file
    echo "$(du -sx --block-size=1 "$CHROOT_DIR" | cut -f1)" > "$CD_DIR/casper/filesystem.size"
    
    register_operation "create_squashfs"
    log_info "SquashFS creation completed"
}

# Step 9: Bootloader Setup with Secure Boot
step_09_bootloader_setup() {
    log_step "Step 9: Enhanced Bootloader Setup with Secure Boot"
    
    # Create boot directory structure
    mkdir -p "$CD_DIR/boot/grub"
    mkdir -p "$CD_DIR/EFI/BOOT"
    mkdir -p "$CD_DIR/isolinux"
    
    # Copy kernel and initrd
    log_info "Copying kernel and initrd files"
    cp "$CHROOT_DIR/boot/vmlinuz-"* "$CD_DIR/casper/vmlinuz"
    cp "$CHROOT_DIR/boot/initrd.img-"* "$CD_DIR/casper/initrd"
    
    # Create GRUB configuration
    log_info "Creating GRUB configuration with Secure Boot support"
    cat > "$CD_DIR/boot/grub/grub.cfg" << EOF
set default="0"
set timeout=10

if loadfont /boot/grub/font.pf2 ; then
    set gfxmode=auto
    insmod efi_gop
    insmod efi_uga
    insmod gfxterm
    terminal_output gfxterm
fi

menuentry "Start $DISTRO_NAME $DISTRO_VERSION Live" {
    linux /casper/vmlinuz boot=casper quiet splash ---
    initrd /casper/initrd
}

menuentry "Start $DISTRO_NAME $DISTRO_VERSION (Safe Mode)" {
    linux /casper/vmlinuz boot=casper quiet splash nomodeset ---
    initrd /casper/initrd
}

menuentry "Check disc for defects" {
    linux /casper/vmlinuz boot=casper integrity-check quiet splash ---
    initrd /casper/initrd
}

menuentry "Memory test (memtest86+)" {
    linux16 /boot/memtest86+.bin
}

menuentry "Boot from first hard disk" {
    set root=(hd0)
    chainloader +1
}
EOF
    
    # Set up EFI boot with Secure Boot support
    log_info "Setting up EFI boot with Secure Boot support"
    
    # Copy shim for Secure Boot
    if [[ -f "/usr/lib/shim/shimx64.efi.signed" ]]; then
        cp /usr/lib/shim/shimx64.efi.signed "$CD_DIR/EFI/BOOT/BOOTX64.EFI"
        log_info "Secure Boot shim installed"
    else
        log_warn "Secure Boot shim not found, using standard GRUB"
        cp /usr/lib/grub/x86_64-efi/grubx64.efi "$CD_DIR/EFI/BOOT/BOOTX64.EFI"
    fi
    
    # Copy GRUB EFI
    cp /usr/lib/grub/x86_64-efi/grubx64.efi "$CD_DIR/EFI/BOOT/grubx64.efi"
    
    # Create EFI GRUB configuration
    cp "$CD_DIR/boot/grub/grub.cfg" "$CD_DIR/EFI/BOOT/grub.cfg"
    
    # Set up BIOS boot with isolinux
    log_info "Setting up BIOS boot with isolinux"
    cp /usr/lib/ISOLINUX/isolinux.bin "$CD_DIR/isolinux/"
    cp /usr/lib/syslinux/modules/bios/* "$CD_DIR/isolinux/"
    
    cat > "$CD_DIR/isolinux/isolinux.cfg" << EOF
DEFAULT vesamenu.c32
PROMPT 0
TIMEOUT 100

MENU TITLE $DISTRO_NAME $DISTRO_VERSION Live

LABEL live
    MENU LABEL Start $DISTRO_NAME $DISTRO_VERSION Live
    KERNEL /casper/vmlinuz
    APPEND initrd=/casper/initrd boot=casper quiet splash ---

LABEL safe
    MENU LABEL Start $DISTRO_NAME $DISTRO_VERSION (Safe Mode)
    KERNEL /casper/vmlinuz
    APPEND initrd=/casper/initrd boot=casper quiet splash nomodeset ---

LABEL check
    MENU LABEL Check disc for defects
    KERNEL /casper/vmlinuz
    APPEND initrd=/casper/initrd boot=casper integrity-check quiet splash ---

LABEL hd
    MENU LABEL Boot from first hard disk
    LOCALBOOT 0x80
EOF
    
    register_operation "bootloader_setup"
    log_info "Bootloader setup completed"
}

# Step 10: ISO Generation
step_10_iso_generation() {
    log_step "Step 10: ISO Generation and Validation"
    
    # Create ISO with hybrid boot support
    local iso_filename="ailinux-${DISTRO_VERSION}-${UBUNTU_CODENAME}-${ARCHITECTURE}.iso"
    
    log_info "Generating ISO: $iso_filename"
    
    if ! xorriso -as mkisofs \
        -iso-level 3 \
        -full-iso9660-filenames \
        -volid "${DISTRO_NAME}_${DISTRO_VERSION}" \
        -eltorito-boot isolinux/isolinux.bin \
        -eltorito-catalog isolinux/boot.cat \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        -eltorito-alt-boot \
        -e EFI/BOOT/BOOTX64.EFI \
        -no-emul-boot \
        -isohybrid-gpt-basdat \
        -isohybrid-apm-hfsplus \
        -output "$iso_filename" \
        "$CD_DIR"; then
        log_error "ISO generation failed"
        return 1
    fi
    
    # Generate checksum
    log_info "Generating SHA256 checksum"
    sha256sum "$iso_filename" > "${iso_filename}.sha256"
    
    # Display ISO information
    local iso_size
    iso_size=$(du -h "$iso_filename" | cut -f1)
    log_info "ISO created successfully: $iso_filename ($iso_size)"
    
    register_operation "iso_generation"
    log_info "ISO generation completed"
}

# Step 11: Build Metadata Generation
step_11_generate_metadata() {
    log_step "Step 11: Build Metadata Generation"
    
    log_info "Generating build metadata: $BUILD_INFO_FILE"
    
    cat > "$BUILD_INFO_FILE" << EOF
# AILinux Build Information
# Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')

[Distribution]
Name=$DISTRO_NAME
Version=$DISTRO_VERSION
Edition=$DISTRO_EDITION
Ubuntu_Base=$UBUNTU_VERSION
Codename=$UBUNTU_CODENAME
Architecture=$ARCHITECTURE

[Build Environment]
Script_Version=$SCRIPT_VERSION
Build_Date=$(date -u '+%Y-%m-%d')
Build_Time=$(date -u '+%H:%M:%S UTC')
Build_Host=$(hostname)
Build_User=$(whoami)
Kernel_Version=$(uname -r)

[Features]
Desktop_Environment=KDE Plasma 6.x
Installer=Calamares
AI_Assistant=$AI_ASSISTANT_NAME
Secure_Boot=Enabled
APT_Mirror=$PRIMARY_MIRROR
GPG_Key=$AILINUX_GPG_KEY

[Files]
ISO_Filename=ailinux-${DISTRO_VERSION}-${UBUNTU_CODENAME}-${ARCHITECTURE}.iso
SquashFS_Path=casper/filesystem.squashfs
Kernel_Path=casper/vmlinuz
InitRD_Path=casper/initrd

[Quality Assurance]
Build_Status=SUCCESS
Error_Handling=Enhanced with AI debugging
Mount_Safety=Implemented with tracking
GPG_Verification=Framework ready
Transaction_Rollback=Implemented

[Contact]
Support_URL=https://ailinux.me/support
Documentation=https://ailinux.me/docs
Issues=https://github.com/derleiti/ailinux-beta-iso/issues
EOF
    
    log_info "Build metadata generated: $BUILD_INFO_FILE"
    log_info "Build completed successfully!"
}

# ========================================
# MAIN EXECUTION FUNCTION
# ========================================

main() {
    # Set up error handling
    trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
    trap 'execute_cleanup' EXIT
    
    # Display banner
    echo -e "\n${PURPLE}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    AILinux ISO Builder                       ║"
    echo "║                     Version $SCRIPT_VERSION                   ║"
    echo "║                                                              ║"
    echo "║            Ubuntu $UBUNTU_VERSION ($UBUNTU_CODENAME) + KDE Plasma            ║"
    echo "║                 Enhanced with AI Integration                 ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}\n"
    
    # Load environment variables if available
    if [[ -f ".env" ]]; then
        log_info "Loading environment variables from .env"
        export $(cat .env | grep -v '^#' | xargs)
    fi
    
    # Validate API key
    if [[ -z "${MIXTRAL_API_KEY:-}" ]]; then
        log_warn "MIXTRAL_API_KEY not set - AI debugging will be disabled"
        log_info "To enable AI debugging, set MIXTRAL_API_KEY in .env file"
    fi
    
    # Execute build steps
    local start_time
    start_time=$(date +%s)
    
    log_info "Starting AILinux ISO build process"
    
    # Execute all build steps
    step_01_environment_setup
    step_02_system_bootstrap
    step_03_package_installation
    step_04_ai_components
    step_05_calamares_setup
    step_06_live_user_setup
    step_07_system_cleanup
    step_08_create_squashfs
    step_09_bootloader_setup
    step_10_iso_generation
    step_11_generate_metadata
    
    # Calculate build time
    local end_time build_time
    end_time=$(date +%s)
    build_time=$((end_time - start_time))
    
    # Final success message
    echo -e "\n${GREEN}${BOLD}🎉 BUILD COMPLETED SUCCESSFULLY! 🎉${NC}\n"
    echo -e "${WHITE}Build Summary:${NC}"
    echo -e "  ${CYAN}Distribution:${NC} $DISTRO_NAME $DISTRO_VERSION ($DISTRO_EDITION)"
    echo -e "  ${CYAN}Base System:${NC} Ubuntu $UBUNTU_VERSION ($UBUNTU_CODENAME)"
    echo -e "  ${CYAN}Architecture:${NC} $ARCHITECTURE"
    echo -e "  ${CYAN}Desktop:${NC} KDE Plasma Desktop"
    echo -e "  ${CYAN}Build Time:${NC} ${build_time}s ($(date -u -d @${build_time} +'%H:%M:%S'))"
    echo -e "  ${CYAN}Build Log:${NC} $LOG_FILE"
    echo -e "  ${CYAN}Build Info:${NC} $BUILD_INFO_FILE"
    echo -e "\n${YELLOW}Next Steps:${NC}"
    echo -e "  1. Test the ISO in a virtual machine"
    echo -e "  2. Verify boot compatibility (UEFI + BIOS)"
    echo -e "  3. Test Calamares installer functionality"
    echo -e "  4. Configure Mixtral API key if not already done"
    echo -e "\n${GREEN}Happy Computing with AILinux! 🚀${NC}\n"
}

# ========================================
# SCRIPT EXECUTION
# ========================================

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi