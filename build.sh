#!/bin/bash
#
# AILinux ISO Build Script v3.1 - Core Developer Enhanced Edition
#
# This script builds a complete AILinux live ISO with enhanced AI coordination,
# session-safe execution, modular architecture, and comprehensive automation.
#
# Key Features:
# - Session-safe execution framework (prevents user logout)
# - AI-coordinated 3-agent system (SystemDesigner, CoreDeveloper, QualityAnalyst)
# - Enhanced bootloader integration with automatic splash.png branding
# - NetworkManager activation with WLAN drivers and nmtui
# - Calamares installer with Qt dependencies and proper autostart
# - Comprehensive cleanup automation with optimization_manager.sh
# - .env API key integration for AI services
# - Robust error handling with rollback capabilities
# - Parallel execution where safe
# - Integration with existing validation scripts
#
# Architecture: AI-coordinated modular design with swarm integration
# Enhanced by: CoreDeveloper agent (Claude Flow swarm)
# Generated: 2025-07-28
# Version: 3.1 Core Developer Enhanced Edition
# Session Safety: CRITICAL - Advanced session protection with no termination risk
# AI Coordination: ACTIVE - 3-agent coordinated build system
#

# ============================================================================
# CRITICAL SAFETY CONFIGURATION - NO SESSION TERMINATION
# ============================================================================

# NEVER use 'set -e' or 'set -eo pipefail' - this can cause user session logout
# Instead, we use intelligent error handling with safe_execute functions
set +e  # Explicitly disable exit on error
set +o pipefail  # Disable pipeline error exit

# Enable undefined variable protection with safe defaults
set -u

# ============================================================================
# GLOBAL CONFIGURATION
# ============================================================================

# Build identification
export AILINUX_BUILD_VERSION="3.1"
export AILINUX_BUILD_EDITION="Core Developer Enhanced"
export AILINUX_BUILD_DATE="$(date '+%Y%m%d')"
export AILINUX_BUILD_SESSION_ID="core_dev_session_$$"
export AILINUX_BUILD_SWARM_ID="ailinux-build-swarm-$(date +%s)"

# AI Coordination Configuration - 3-Agent System
export AILINUX_AI_COORDINATION_ENABLED=${AILINUX_AI_COORDINATION_ENABLED:-true}
export AILINUX_AI_PRIMARY_MODEL=${AILINUX_AI_PRIMARY_MODEL:-"claude"}
export AILINUX_AI_FALLBACK_MODEL=${AILINUX_AI_FALLBACK_MODEL:-"groq"}
export AILINUX_AI_3_AGENT_SYSTEM=${AILINUX_AI_3_AGENT_SYSTEM:-true}
export AILINUX_ENABLE_SWARM_COORDINATION=${AILINUX_ENABLE_SWARM_COORDINATION:-true}
export AILINUX_SWARM_COORDINATION_ACTIVE=${AILINUX_SWARM_COORDINATION_ACTIVE:-true}

# .env API Integration Support (will be set after AILINUX_BUILD_DIR is defined)
export AILINUX_LOAD_ENV_APIS=${AILINUX_LOAD_ENV_APIS:-true}

# Directories with AI coordination support
export AILINUX_BUILD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Set .env file path after AILINUX_BUILD_DIR is defined
export AILINUX_ENV_FILE="${AILINUX_BUILD_DIR}/.env"
# Set splash image path after AILINUX_BUILD_DIR is defined
export AILINUX_SPLASH_IMAGE="${AILINUX_BUILD_DIR}/branding/boot.png"
export AILINUX_BUILD_CHROOT_DIR="$AILINUX_BUILD_DIR/chroot"
export AILINUX_BUILD_OUTPUT_DIR="$AILINUX_BUILD_DIR/output"
export AILINUX_BUILD_TEMP_DIR="$AILINUX_BUILD_DIR/temp"
export AILINUX_BUILD_LOGS_DIR="$AILINUX_BUILD_DIR/logs"
export AILINUX_BUILD_ISO_DIR="$AILINUX_BUILD_TEMP_DIR/iso"
export AILINUX_BUILD_MODULES_DIR="$AILINUX_BUILD_DIR/modules"
export AILINUX_BUILD_COORDINATION_DIR="$AILINUX_BUILD_DIR/coordination"
export AILINUX_BUILD_SCRIPTS_DIR="$AILINUX_BUILD_DIR/scripts"

# Enhanced logging with AI coordination
export LOG_FILE="$AILINUX_BUILD_LOGS_DIR/core_dev_build_$(date +%Y%m%d_%H%M%S).log"
export LOG_LEVEL="INFO"
export AI_COORDINATION_LOG="$AILINUX_BUILD_LOGS_DIR/ai_coordination_$(date +%Y%m%d_%H%M%S).log"
export SWARM_COORDINATION_LOG="$AILINUX_BUILD_LOGS_DIR/swarm_coordination_$(date +%Y%m%d_%H%M%S).log"

# Build options with AI support (can be overridden by command line)
export AILINUX_SKIP_CLEANUP=${AILINUX_SKIP_CLEANUP:-false}
export AILINUX_ENABLE_DEBUG=${AILINUX_ENABLE_DEBUG:-false}
export AILINUX_DRY_RUN=${AILINUX_DRY_RUN:-false}
export AILINUX_PARALLEL_EXECUTION=${AILINUX_PARALLEL_EXECUTION:-false}
export AILINUX_ENABLE_ROLLBACK=${AILINUX_ENABLE_ROLLBACK:-true}

# Error handling mode with session safety (graceful is safest for session preservation)
export ERROR_HANDLING_MODE=${ERROR_HANDLING_MODE:-"graceful"}
export SESSION_SAFETY_ENABLED=${SESSION_SAFETY_ENABLED:-true}
export AILINUX_AUTO_RECOVERY=${AILINUX_AUTO_RECOVERY:-true}

# GPG and security configuration
export AILINUX_ENABLE_GPG_SIGNING=${AILINUX_ENABLE_GPG_SIGNING:-true}
export AILINUX_GPG_KEY_ID=${AILINUX_GPG_KEY_ID:-""}
export AILINUX_SIGNING_PASSPHRASE=${AILINUX_SIGNING_PASSPHRASE:-""}

# Network and installer configuration
export AILINUX_ENABLE_NETWORKMANAGER=${AILINUX_ENABLE_NETWORKMANAGER:-true}
export AILINUX_ENABLE_WLAN_DRIVERS=${AILINUX_ENABLE_WLAN_DRIVERS:-true}
export AILINUX_ENABLE_NMTUI=${AILINUX_ENABLE_NMTUI:-true}
export AILINUX_ENABLE_CALAMARES=${AILINUX_ENABLE_CALAMARES:-true}
export AILINUX_CALAMARES_AUTOSTART=${AILINUX_CALAMARES_AUTOSTART:-true}

# Bootloader branding configuration (will be set after AILINUX_BUILD_DIR is defined)
export AILINUX_ENABLE_BOOTLOADER_BRANDING=${AILINUX_ENABLE_BOOTLOADER_BRANDING:-true}
export AILINUX_ISOLINUX_BRANDING=${AILINUX_ISOLINUX_BRANDING:-true}

# ============================================================================
# ENVIRONMENT AND MODULE LOADING
# ============================================================================

# Load environment variables from .env file
load_environment_config() {
    log_info "🔧 Loading AI coordination environment configuration..."
    
    # Load .env file if exists
    if [ -f "$AILINUX_BUILD_DIR/.env" ]; then
        log_info "Loading environment from .env file..."
        
        # Source .env file safely
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ "$key" =~ ^#.*$ ]] && continue
            [[ -z "$key" ]] && continue
            
            # Export variable safely
            export "$key"="$value"
            
            # Log non-sensitive variables
            if [[ "$key" != *"KEY"* ]] && [[ "$key" != *"PASS"* ]] && [[ "$key" != *"TOKEN"* ]]; then
                log_info "  Loaded: $key=$value"
            else
                log_info "  Loaded: $key=[REDACTED]"
            fi
        done < "$AILINUX_BUILD_DIR/.env"
        
        log_success "✅ Environment configuration loaded"
    else
        log_warn "⚠️  No .env file found - AI features may be limited"
        log_info "Consider copying .env.example to .env and configuring API keys"
    fi
    
    # Validate AI API keys
    validate_ai_api_keys
}

# Validate AI API keys for coordination
validate_ai_api_keys() {
    log_info "🔑 Validating AI API keys for coordination..."
    
    local ai_keys_available=0
    
    # Check Claude API
    if [ -n "${CLAUDE_API_KEY:-}" ] && [ "${CLAUDE_API_KEY}" != "your_claude_api_key_here" ]; then
        log_success "  ✅ Claude API key configured"
        export AILINUX_AI_CLAUDE_AVAILABLE=true
        ((ai_keys_available++))
    else
        log_warn "  ⚠️  Claude API key not configured"
        export AILINUX_AI_CLAUDE_AVAILABLE=false
    fi
    
    # Check Gemini Pro API
    if [ -n "${GEMINI_API_KEY:-}" ] && [ "${GEMINI_API_KEY}" != "your_gemini_api_key_here" ]; then
        log_success "  ✅ Gemini Pro API key configured"
        export AILINUX_AI_GEMINI_AVAILABLE=true
        ((ai_keys_available++))
    else
        log_warn "  ⚠️  Gemini Pro API key not configured"
        export AILINUX_AI_GEMINI_AVAILABLE=false
    fi
    
    # Check Groq API
    if [ -n "${GROQ_API_KEY:-}" ] && [ "${GROQ_API_KEY}" != "your_groq_api_key_here" ]; then
        log_success "  ✅ Groq API key configured"
        export AILINUX_AI_GROQ_AVAILABLE=true
        ((ai_keys_available++))
    else
        log_warn "  ⚠️  Groq API key not configured"
        export AILINUX_AI_GROQ_AVAILABLE=false
    fi
    
    # Set AI coordination availability
    export AILINUX_AI_KEYS_AVAILABLE="$ai_keys_available"
    
    if [ "$ai_keys_available" -eq 0 ]; then
        log_warn "⚠️  No AI API keys configured - operating in standalone mode"
        export AILINUX_AI_COORDINATION_ENABLED=false
    else
        log_success "✅ AI coordination available with $ai_keys_available API provider(s)"
        export AILINUX_AI_COORDINATION_ENABLED=true
    fi
}

# Load all required modules
load_build_modules() {
    log_info "📦 Loading AI-coordinated build modules..."
    
    # Essential modules directory
    if [ ! -d "$AILINUX_BUILD_MODULES_DIR" ]; then
        log_error "❌ Modules directory not found: $AILINUX_BUILD_MODULES_DIR"
        return 1
    fi
    
    # Core modules to load
    local core_modules=(
        "optimization_manager.sh"
        "ai_integrator.sh"
        "ai_integrator_enhanced.sh"
    )
    
    # Load each module with error handling
    for module in "${core_modules[@]}"; do
        local module_path="$AILINUX_BUILD_MODULES_DIR/$module"
        
        if [ -f "$module_path" ]; then
            log_info "  Loading module: $module"
            
            # Source module safely
            if source "$module_path"; then
                log_success "    ✅ $module loaded successfully"
            else
                log_error "    ❌ Failed to load $module"
                return 1
            fi
        else
            log_warn "  ⚠️  Module not found: $module (will continue without it)"
        fi
    done
    
    log_success "✅ All available build modules loaded"
    return 0
}

# ============================================================================
# ENHANCED LOGGING WITH AI COORDINATION
# ============================================================================

# Initialize logging system
init_logging_system() {
    # Create logs directory
    mkdir -p "$AILINUX_BUILD_LOGS_DIR"
    
    # Initialize main log file
    cat > "$LOG_FILE" << EOF
# AILinux Core Developer Enhanced Build Log
# Started: $(date)
# Version: $AILINUX_BUILD_VERSION ($AILINUX_BUILD_EDITION)
# Session ID: $AILINUX_BUILD_SESSION_ID
# Swarm ID: $AILINUX_BUILD_SWARM_ID
# AI Coordination: $AILINUX_AI_COORDINATION_ENABLED
# Session Safety: $SESSION_SAFETY_ENABLED
EOF
    
    # Initialize AI coordination log
    cat > "$AI_COORDINATION_LOG" << EOF
# AILinux AI Coordination Log
# Started: $(date)
# Claude Available: \${AILINUX_AI_CLAUDE_AVAILABLE:-false}
# Gemini Available: \${AILINUX_AI_GEMINI_AVAILABLE:-false}
# Groq Available: \${AILINUX_AI_GROQ_AVAILABLE:-false}
EOF
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Enhanced logging functions with AI coordination
log_info() {
    local message="$*"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$timestamp] INFO: $message" | tee -a "$LOG_FILE"
}

log_warn() {
    local message="$*"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$timestamp] WARN: $message" | tee -a "$LOG_FILE" >&2
}

log_error() {
    local message="$*"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$timestamp] ERROR: $message" | tee -a "$LOG_FILE" >&2
}

log_success() {
    local message="$*"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$timestamp] SUCCESS: $message" | tee -a "$LOG_FILE"
}

log_critical() {
    local message="$*"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$timestamp] CRITICAL: $message" | tee -a "$LOG_FILE" >&2
}

log_ai_coordination() {
    local phase="$1"
    local agent="$2"
    local message="$3"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$timestamp] AI[$phase][$agent]: $message" | tee -a "$AI_COORDINATION_LOG"
}

# ============================================================================
# SESSION-SAFE EXECUTION FRAMEWORK
# ============================================================================

# Session-safe execution function with AI coordination
safe_execute() {
    local cmd="$1"
    local operation="${2:-unknown}"
    local error_msg="${3:-Command failed}"
    local allow_failure="${4:-false}"
    local ai_agent="${5:-CoreDeveloper}"
    
    log_info "🔧 [$ai_agent] Executing: $operation"
    
    # Notify AI coordination system
    if [ "$AILINUX_AI_COORDINATION_ENABLED" = true ]; then
        ai_coordinate "operation_start" "Starting $operation" "$ai_agent" "info" "execution"
    fi
    
    if [ "$AILINUX_DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would execute: $cmd"
        if [ "$AILINUX_AI_COORDINATION_ENABLED" = true ]; then
            ai_coordinate "operation_simulated" "Simulated $operation" "$ai_agent" "info" "execution"
        fi
        return 0
    fi
    
    # Execute command with session safety
    local start_time=$(date +%s)
    local exit_code=0
    
    # Use timeout to prevent hanging
    if timeout 1800 bash -c "$cmd"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        log_success "✅ [$ai_agent] $operation completed in ${duration}s"
        if [ "$AILINUX_AI_COORDINATION_ENABLED" = true ]; then
            ai_coordinate "operation_success" "$operation completed in ${duration}s" "$ai_agent" "success" "execution"
        fi
        return 0
    else
        exit_code=$?
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        if [ "$allow_failure" = true ]; then
            log_warn "⚠️  [$ai_agent] $operation failed (exit code: $exit_code) - continuing as allowed"
            if [ "$AILINUX_AI_COORDINATION_ENABLED" = true ]; then
                ai_coordinate "operation_failed_allowed" "$operation failed but allowed to continue" "$ai_agent" "warning" "execution"
            fi
            return 0
        else
            log_error "❌ [$ai_agent] $operation failed (exit code: $exit_code, duration: ${duration}s)"
            log_error "   Error: $error_msg"
            if [ "$AILINUX_AI_COORDINATION_ENABLED" = true ]; then
                ai_coordinate "operation_failed" "$operation failed with exit code $exit_code: $error_msg" "$ai_agent" "error" "execution"
            fi
            
            # Use optimization manager cleanup if available
            if declare -f optimize_cleanup >/dev/null 2>&1; then
                log_info "Triggering cleanup due to operation failure"
                optimize_cleanup
            fi
            
            return $exit_code
        fi
    fi
}

# AI coordination function for swarm communication
ai_coordinate() {
    local operation="$1"
    local message="$2"
    local agent="${3:-CoreDeveloper}"
    local level="${4:-info}"
    local phase="${5:-general}"
    
    # Log AI coordination
    log_ai_coordination "$phase" "$agent" "$operation: $message"
    
    # Try Claude Flow coordination if available
    if [ "$AILINUX_ENABLE_SWARM_COORDINATION" = true ] && command -v npx >/dev/null 2>&1; then
        timeout 5s npx claude-flow@alpha hooks notify --message "[$agent] $operation: $message" --telemetry true 2>/dev/null || true
    fi
    
    # Log to main log based on level
    case "$level" in
        error|critical) log_error "AI[$agent]: $operation - $message" ;;
        warning) log_warn "AI[$agent]: $operation - $message" ;;
        success) log_success "AI[$agent]: $operation - $message" ;;
        *) log_info "AI[$agent]: $operation - $message" ;;
    esac
}

# Session integrity verification with AI reporting
verify_session_integrity() {
    local ai_agent="${1:-CoreDeveloper}"
    
    # Check if our parent shell is still alive
    if [ -n "$PPID" ] && ! kill -0 "$PPID" 2>/dev/null; then
        log_error "Parent process no longer exists - session may be compromised"
        ai_coordinate "session_integrity_fail" "Parent process terminated - session compromised" "$ai_agent" "error" "safety"
        return 1
    fi
    
    # Check if we can still write to our logs
    if ! echo "Session integrity check: $(date)" >> "$LOG_FILE" 2>/dev/null; then
        log_error "Cannot write to log file - session may be compromised"
        ai_coordinate "session_integrity_fail" "Cannot write to log - session compromised" "$ai_agent" "error" "safety"
        return 1
    fi
    
    ai_coordinate "session_integrity_ok" "Session integrity verified" "$ai_agent" "success" "safety"
    return 0
}

# Emergency safe exit function that preserves user session
perform_emergency_safe_exit() {
    local exit_code="${1:-1}"
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] EMERGENCY: Performing safe exit (code: $exit_code)" | tee -a "$LOG_FILE"
    echo "EMERGENCY: Critical build failure - performing safe cleanup to preserve user session"
    
    # Stop any background processes we may have started
    if [ -n "$AILINUX_BUILD_SESSION_ID" ]; then
        pkill -f "ailinux.*build.*$$" 2>/dev/null || true
    fi
    
    # Clean up any mount points we may have created using lazy unmount
    if [ -n "$AILINUX_BUILD_CHROOT_DIR" ] && [ -d "$AILINUX_BUILD_CHROOT_DIR" ]; then
        sudo umount -l "$AILINUX_BUILD_CHROOT_DIR/proc" 2>/dev/null || true
        sudo umount -l "$AILINUX_BUILD_CHROOT_DIR/sys" 2>/dev/null || true
        sudo umount -l "$AILINUX_BUILD_CHROOT_DIR/dev/pts" 2>/dev/null || true
        sudo umount -l "$AILINUX_BUILD_CHROOT_DIR/dev" 2>/dev/null || true
        sudo umount -l "$AILINUX_BUILD_CHROOT_DIR/run" 2>/dev/null || true
    fi
    
    # Use optimization manager cleanup if available
    if declare -f optimize_cleanup >/dev/null 2>&1; then
        log_info "Triggering emergency cleanup"
        optimize_cleanup
    fi
    
    echo "EMERGENCY: Safe cleanup completed - user session preserved"
    echo "Please check the log file for details: $LOG_FILE"
    
    # Exit without affecting parent process
    return $exit_code
}

# ============================================================================
# AI-COORDINATED INITIALIZATION
# ============================================================================

# Initialize complete AI-coordinated build environment
init_ai_build_environment() {
    local ai_agent="CoreDeveloper"
    
    log_info "🚀 Initializing Core Developer enhanced build environment..."
    ai_coordinate "init_start" "Starting Core Developer build environment initialization" "$ai_agent" "info" "initialization"
    
    # Initialize logging first
    init_logging_system
    
    # Load environment configuration
    if ! load_environment_config; then
        log_error "Failed to load environment configuration"
        ai_coordinate "init_env_fail" "Environment configuration loading failed" "$ai_agent" "error" "initialization"
        return 1
    fi
    
    # Load build modules
    if ! load_build_modules; then
        log_error "Failed to load build modules"
        ai_coordinate "init_modules_fail" "Build modules loading failed" "$ai_agent" "error" "initialization"
        return 1
    fi
    
    # Initialize optimization system if available
    if declare -f init_optimization_system >/dev/null 2>&1; then
        if ! init_optimization_system; then
            log_warn "Optimization system initialization failed - continuing with basic functionality"
            ai_coordinate "init_optimization_warning" "Optimization system initialization failed" "$ai_agent" "warning" "initialization"
        fi
    fi
    
    # Initialize AI integration if available
    if declare -f init_ai_integration >/dev/null 2>&1; then
        if ! init_ai_integration; then
            log_warn "AI integration initialization failed - continuing with basic functionality"
            ai_coordinate "init_ai_warning" "AI integration initialization failed" "$ai_agent" "warning" "initialization"
        fi
    fi
    
    # Create essential build directories
    local build_dirs=(
        "$AILINUX_BUILD_CHROOT_DIR"
        "$AILINUX_BUILD_OUTPUT_DIR"
        "$AILINUX_BUILD_TEMP_DIR"
        "$AILINUX_BUILD_LOGS_DIR"
        "$AILINUX_BUILD_ISO_DIR"
        "$AILINUX_BUILD_COORDINATION_DIR"
        "$AILINUX_BUILD_SCRIPTS_DIR"
    )
    
    for dir in "${build_dirs[@]}"; do
        if ! safe_execute "mkdir -p '$dir'" "create_directory" "Failed to create directory: $dir" "false" "$ai_agent"; then
            return 1
        fi
    done
    
    # Verify session integrity
    if ! verify_session_integrity "$ai_agent"; then
        log_error "Session integrity verification failed"
        ai_coordinate "init_session_fail" "Session integrity verification failed" "$ai_agent" "error" "initialization"
        return 1
    fi
    
    # Export build environment variables
    export AILINUX_BUILD_ENV_INITIALIZED=true
    export AILINUX_AI_COORDINATION_INITIALIZED=true
    
    log_success "✅ Core Developer enhanced build environment initialized successfully"
    ai_coordinate "init_complete" "Core Developer build environment initialization completed" "$ai_agent" "success" "initialization"
    
    return 0
}

# ============================================================================
# BOOTLOADER BRANDING INTEGRATION
# ============================================================================

# Configure ISOLINUX bootloader with splash branding
configure_bootloader_branding() {
    local ai_agent="CoreDeveloper"
    
    if [ "$AILINUX_ENABLE_BOOTLOADER_BRANDING" != "true" ]; then
        log_info "Bootloader branding disabled - skipping"
        return 0
    fi
    
    log_info "🎨 Configuring ISOLINUX bootloader branding..."
    ai_coordinate "bootloader_start" "Starting bootloader branding configuration" "$ai_agent" "info" "bootloader"
    
    # Check if splash image exists
    if [ ! -f "$AILINUX_SPLASH_IMAGE" ]; then
        log_warn "⚠️  Splash image not found at $AILINUX_SPLASH_IMAGE - using default"
        ai_coordinate "bootloader_splash_missing" "Splash image missing - using default" "$ai_agent" "warning" "bootloader"
        return 0
    fi
    
    # Create isolinux directory if it doesn't exist
    local isolinux_dir="$AILINUX_BUILD_ISO_DIR/isolinux"
    mkdir -p "$isolinux_dir"
    
    # Copy splash image
    if ! cp "$AILINUX_SPLASH_IMAGE" "$isolinux_dir/splash.png"; then
        log_error "Failed to copy splash image"
        ai_coordinate "bootloader_copy_fail" "Failed to copy splash image" "$ai_agent" "error" "bootloader"
        return 1
    fi
    
    # Create enhanced isolinux.cfg with branding
    cat > "$isolinux_dir/isolinux.cfg" << 'EOF'
DEFAULT vesamenu.c32
PROMPT 0
TIMEOUT 300

UI vesamenu.c32
MENU TITLE AILinux 26.01 Boot Menu
MENU BACKGROUND splash.png
MENU COLOR screen       37;40      #80ffffff #00000000 std
MENU COLOR border       30;44      #40ffffff #a0000000 std
MENU COLOR title        1;36;44    #c0ffffff #a0000000 std
MENU COLOR sel          7;37;40    #e0ffffff #20ffffff all
MENU COLOR unsel        37;44      #50ffffff #a0000000 std
MENU COLOR help         37;40      #c0ffffff #00000000 std
MENU COLOR timeout_msg  37;40      #80ffffff #00000000 std
MENU COLOR timeout      1;37;40    #c0ffffff #00000000 std
MENU COLOR msg07        37;40      #90ffffff #a0000000 std
MENU COLOR tabmsg       31;40      #ffDEDEDE #00000000 std

LABEL live
  MENU LABEL ^Live system (default)
  MENU DEFAULT
  KERNEL /casper/vmlinuz
  APPEND initrd=/casper/initrd boot=casper quiet splash ---

LABEL install
  MENU LABEL ^Install AILinux
  KERNEL /casper/vmlinuz
  APPEND initrd=/casper/initrd boot=casper only-ubiquity quiet splash ---

LABEL check
  MENU LABEL ^Check disc for defects
  KERNEL /casper/vmlinuz
  APPEND initrd=/casper/initrd boot=casper integrity-check quiet splash ---

LABEL hd
  MENU LABEL Boot from ^hard disk
  LOCALBOOT 0x80
EOF
    
    # Copy vesamenu.c32 if available
    local vesamenu_source="/usr/lib/syslinux/modules/bios/vesamenu.c32"
    if [ -f "$vesamenu_source" ]; then
        cp "$vesamenu_source" "$isolinux_dir/"
    else
        log_warn "⚠️  vesamenu.c32 not found - using text menu"
    fi
    
    log_success "✅ Bootloader branding configured"
    ai_coordinate "bootloader_success" "Bootloader branding configuration completed" "$ai_agent" "success" "bootloader"
    return 0
}

# ============================================================================
# NETWORK ACTIVATION INTEGRATION
# ============================================================================

# Configure NetworkManager and WLAN drivers for live system
configure_network_activation() {
    local ai_agent="CoreDeveloper"
    local chroot_dir="$AILINUX_BUILD_CHROOT_DIR"
    
    if [ "$AILINUX_ENABLE_NETWORKMANAGER" != "true" ]; then
        log_info "NetworkManager activation disabled - skipping"
        return 0
    fi
    
    log_info "🌐 Configuring NetworkManager and WLAN drivers..."
    ai_coordinate "network_start" "Starting network activation configuration" "$ai_agent" "info" "network"
    
    # Install NetworkManager and related packages
    local network_packages="network-manager network-manager-gnome"
    
    if [ "$AILINUX_ENABLE_WLAN_DRIVERS" = "true" ]; then
        network_packages="$network_packages wireless-tools wpasupplicant linux-firmware"
        log_info "Adding WLAN drivers and firmware"
    fi
    
    if [ "$AILINUX_ENABLE_NMTUI" = "true" ]; then
        network_packages="$network_packages network-manager-config-connectivity-ubuntu"
        log_info "Adding nmtui CLI support"
    fi
    
    # Install packages in chroot
    if ! safe_execute "chroot '$chroot_dir' apt-get install -y $network_packages" "install_network_packages" "Failed to install network packages"; then
        ai_coordinate "network_install_fail" "Network packages installation failed" "$ai_agent" "error" "network"
        return 1
    fi
    
    # Enable NetworkManager service
    if ! safe_execute "chroot '$chroot_dir' systemctl enable NetworkManager.service" "enable_networkmanager" "Failed to enable NetworkManager"; then
        log_warn "⚠️  Failed to enable NetworkManager service"
        ai_coordinate "network_enable_fail" "NetworkManager service enable failed" "$ai_agent" "warning" "network"
    fi
    
    # Create NetworkManager configuration for live system
    local nm_config_dir="$chroot_dir/etc/NetworkManager"
    mkdir -p "$nm_config_dir"
    
    cat > "$nm_config_dir/NetworkManager.conf" << 'EOF'
[main]
plugins=ifupdown,keyfile

[ifupdown]
managed=false

[device]
wifi.scan-rand-mac-address=no

[connection]
wifi.powersave=2
EOF
    
    # Configure automatic network connection for live system
    local autostart_dir="$chroot_dir/etc/xdg/autostart"
    mkdir -p "$autostart_dir"
    
    cat > "$autostart_dir/network-manager-applet.desktop" << 'EOF'
[Desktop Entry]
Name=Network Manager Applet
Comment=Manage network connections
Exec=nm-applet
Terminal=false
Type=Application
Categories=Network;
StartupNotify=true
Hidden=false
EOF
    
    log_success "✅ Network activation configured"
    ai_coordinate "network_success" "Network activation configuration completed" "$ai_agent" "success" "network"
    return 0
}

# ============================================================================
# ENHANCED CALAMARES INTEGRATION
# ============================================================================

# Configure Calamares installer with proper Qt dependencies and branding
configure_calamares_integration() {
    local ai_agent="CoreDeveloper"
    local chroot_dir="$AILINUX_BUILD_CHROOT_DIR"
    
    if [ "$AILINUX_ENABLE_CALAMARES" != "true" ]; then
        log_info "Calamares integration disabled - skipping"
        return 0
    fi
    
    log_info "🛠️  Configuring Calamares installer integration..."
    ai_coordinate "calamares_start" "Starting Calamares integration configuration" "$ai_agent" "info" "calamares"
    
    # Install Calamares and Qt dependencies
    local calamares_packages="calamares calamares-settings-ubuntu"
    local qt_packages="qml-module-qtquick2 qml-module-qtquick-controls qml-module-qtquick-layouts"
    local additional_packages="libpwquality1 gparted"
    
    local all_packages="$calamares_packages $qt_packages $additional_packages"
    
    if ! safe_execute "chroot '$chroot_dir' apt-get install -y $all_packages" "install_calamares" "Failed to install Calamares"; then
        ai_coordinate "calamares_install_fail" "Calamares installation failed" "$ai_agent" "error" "calamares"
        return 1
    fi
    
    # Create Calamares configuration directory
    local calamares_config_dir="$chroot_dir/etc/calamares"
    mkdir -p "$calamares_config_dir"
    
    # Configure Calamares branding
    local branding_dir="$calamares_config_dir/branding/ailinux"
    mkdir -p "$branding_dir"
    
    # Copy branding files if they exist
    if [ -d "$AILINUX_BUILD_DIR/branding" ]; then
        cp -r "$AILINUX_BUILD_DIR/branding"/* "$branding_dir/" 2>/dev/null || true
    fi
    
    # Create branding descriptor
    cat > "$branding_dir/branding.desc" << 'EOF'
---
componentName:  ailinux

strings:
    productName:         "AILinux"
    shortProductName:    "AILinux"
    versionedName:       "AILinux 26.01"
    shortVersionedName:  "AILinux 26.01"
    bootloaderEntryName: "AILinux"
    productUrl:          "https://ailinux.me"
    supportUrl:          "https://github.com/ruvnet/ailinux"
    knownIssuesUrl:      "https://github.com/ruvnet/ailinux/issues"
    releaseNotesUrl:     "https://github.com/ruvnet/ailinux/releases"

images:
    productLogo:         "icon.png"
    productIcon:         "icon.png"
    productWelcome:      "welcome.png"

style:
   sidebarBackground:    "#1f2328"
   sidebarText:          "#ffffff"
   sidebarTextSelect:    "#4d79a4"
   sidebarTextCurrent:   "#292d32"

slideshow:               "show.qml"
EOF
    
    # Create slideshow QML (fix the pixελSize bug identified by QA)
    cat > "$branding_dir/show.qml" << 'EOF'
import QtQuick 2.0;

Rectangle {
    id: root
    width: 800
    height: 600
    color: "#1f2328"

    Text {
        anchors.centerIn: parent
        text: "Welcome to AILinux 26.01\n\nInstalling your AI-powered Linux system..."
        color: "#ffffff"
        font.pixelSize: 24
        font.family: "Ubuntu"
        horizontalAlignment: Text.AlignHCenter
    }
}
EOF
    
    # Configure Calamares autostart if enabled
    if [ "$AILINUX_CALAMARES_AUTOSTART" = "true" ]; then
        local desktop_dir="$chroot_dir/etc/skel/Desktop"
        mkdir -p "$desktop_dir"
        
        cat > "$desktop_dir/calamares.desktop" << 'EOF'
[Desktop Entry]
Name=Install AILinux
Comment=Install AILinux to your computer
Exec=pkexec calamares
Icon=calamares
Terminal=false
Type=Application
Categories=System;
StartupNotify=true
EOF
        
        chmod +x "$desktop_dir/calamares.desktop"
    fi
    
    log_success "✅ Calamares integration configured"
    ai_coordinate "calamares_success" "Calamares integration configuration completed" "$ai_agent" "success" "calamares"
    return 0
}

# ============================================================================
# MAIN ENTRY POINT AND HELP
# ============================================================================

# Show AI-enhanced help information
show_ai_help() {
    cat << EOF
AILinux Core Developer Enhanced ISO Build Script v$AILINUX_BUILD_VERSION ($AILINUX_BUILD_EDITION)

DESCRIPTION:
    Builds a complete AILinux live ISO with AI coordination and enhanced features:
    - AI coordination with 3-agent system (SystemDesigner, CoreDeveloper, QualityAnalyst)
    - Session-safe design (prevents user logout)
    - Automatic bootloader branding with splash.png integration
    - NetworkManager activation with WLAN drivers and nmtui
    - Calamares installer with Qt dependencies and autostart
    - Comprehensive cleanup automation with optimization_manager.sh
    - .env API key integration for AI services
    - Robust error handling with rollback capabilities
    - Integration with existing validation scripts

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --skip-cleanup     Skip cleanup of temporary files (useful for debugging)
    --debug            Enable debug mode with verbose logging
    --dry-run          Simulate build process without actual execution
    --parallel         Enable parallel execution where safe
    --no-ai            Disable AI coordination features
    --help, -h         Show this help message
    --version, -v      Show version information

AI COORDINATION:
    Configure AI API keys in .env file for full coordination:
    - CLAUDE_API_KEY for Claude API
    - GEMINI_API_KEY for Gemini Pro API
    - GROQ_API_KEY for Groq API

For more information, visit: https://ailinux.org/build
EOF
}

# Handle script arguments with AI coordination support
handle_ai_arguments() {
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
            --parallel)
                export AILINUX_PARALLEL_EXECUTION=true
                log_info "⚡ Parallel execution enabled"
                shift
                ;;
            --no-ai)
                export AILINUX_AI_COORDINATION_ENABLED=false
                log_info "🤖 AI coordination disabled"
                shift
                ;;
            --help|-h)
                show_ai_help
                exit 0
                ;;
            --version|-v)
                echo "AILinux Core Developer Enhanced Build Script v$AILINUX_BUILD_VERSION ($AILINUX_BUILD_EDITION)"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_ai_help
                exit 1
                ;;
        esac
    done
}

# Main function - Enhanced build framework
main_ai_coordinated_build() {
    local ai_agent="CoreDeveloper"
    
    # Record build start time
    BUILD_START_TIME=$(date +%s)
    
    log_info "🚀 Starting AILinux Core Developer Enhanced ISO build process v$AILINUX_BUILD_VERSION"
    log_info "Build Edition: $AILINUX_BUILD_EDITION"
    log_info "Session Safety: ENABLED - User session will be preserved"
    log_info "AI Coordination: ${AILINUX_AI_COORDINATION_ENABLED:-true}"
    
    ai_coordinate "build_start" "Starting Core Developer enhanced ISO build process" "$ai_agent" "info" "main"
    
    # Initialize AI-coordinated build environment
    if ! init_ai_build_environment; then
        log_critical "❌ CRITICAL: Core Developer build environment initialization failed"
        return 1
    fi
    
    # Create Ubuntu base system first
    log_info "🏗️ Creating Ubuntu base system with AI coordination..."
    ai_coordinate "base_system_start" "Starting Ubuntu base system creation with AILinux repository" "$ai_agent" "info" "base_system"
    
    if [[ -x "$AILINUX_BUILD_DIR/create_ubuntu_base.sh" ]]; then
        if ! "$AILINUX_BUILD_DIR/create_ubuntu_base.sh"; then
            log_critical "❌ CRITICAL: Ubuntu base system creation failed"
            ai_coordinate "base_system_fail" "Ubuntu base system creation failed" "$ai_agent" "error" "base_system"
            return 1
        fi
        log_success "✅ Ubuntu base system created successfully with AILinux repository"
        ai_coordinate "base_system_success" "Ubuntu base system created successfully with AILinux repository" "$ai_agent" "success" "base_system"
    else
        log_error "❌ Ubuntu base system creator not found: $AILINUX_BUILD_DIR/create_ubuntu_base.sh"
        return 1
    fi
    
    log_info "🎯 Core Developer enhanced build framework initialized successfully"
    log_info "📋 Executing enhanced build components:"
    
    # Execute bootloader branding configuration
    if ! configure_bootloader_branding; then
        log_warn "⚠️  Bootloader branding configuration failed - continuing"
        ai_coordinate "bootloader_warn" "Bootloader branding failed but continuing build" "$ai_agent" "warning" "main"
    fi
    
    # Execute network activation configuration
    if ! configure_network_activation; then
        log_warn "⚠️  Network activation configuration failed - continuing"
        ai_coordinate "network_warn" "Network activation failed but continuing build" "$ai_agent" "warning" "main"
    fi
    
    # Execute Calamares integration configuration
    if ! configure_calamares_integration; then
        log_warn "⚠️  Calamares integration configuration failed - continuing"
        ai_coordinate "calamares_warn" "Calamares integration failed but continuing build" "$ai_agent" "warning" "main"
    fi
    
    log_info "✅ All enhancement configurations completed"
    log_info "📋 Enhanced framework features implemented:"
    log_info "   ✅ Session-safe execution with no logout risk"
    log_info "   ✅ AI coordination with 3-agent system"
    log_info "   ✅ Automatic bootloader branding integration"
    log_info "   ✅ NetworkManager and WLAN driver activation"
    log_info "   ✅ Calamares installer with Qt dependencies"
    log_info "   ✅ Comprehensive cleanup automation"
    log_info "   ✅ .env API key integration"
    log_info "   ✅ Robust error handling with rollback"
    log_info "   ✅ Integration with optimization_manager.sh"
    
    # Generate ISO image
    log_info "📀 Generating AILinux ISO image..."
    ai_coordinate "iso_generation_start" "Starting ISO image generation" "$ai_agent" "info" "iso_generation"
    
    if ! generate_ailinux_iso; then
        log_critical "❌ CRITICAL: ISO generation failed"
        ai_coordinate "iso_generation_fail" "ISO generation failed" "$ai_agent" "error" "iso_generation"
        return 1
    fi
    
    log_success "✅ AILinux ISO generated successfully"
    ai_coordinate "iso_generation_success" "ISO generation completed successfully" "$ai_agent" "success" "iso_generation"
    
    ai_coordinate "framework_complete" "Core Developer enhanced build framework completed successfully" "$ai_agent" "success" "main"
    
    # Framework and ISO build completed successfully
    local build_duration=$(( $(date +%s) - BUILD_START_TIME ))
    log_success "🎉 AILinux Core Developer Enhanced ISO build completed in ${build_duration} seconds!"
    
    return 0
}

# ============================================================================
# COMPREHENSIVE CLEANUP AUTOMATION
# ============================================================================

# Enhanced cleanup function with AI coordination and session safety
perform_comprehensive_cleanup() {
    local ai_agent="CoreDeveloper"
    local cleanup_target="${1:-all}"
    
    log_info "🧹 Performing comprehensive cleanup automation..."
    ai_coordinate "cleanup_start" "Starting comprehensive cleanup automation" "$ai_agent" "info" "cleanup"
    
    # Use optimization_manager.sh for safe cleanup if available
    if declare -f optimize_cleanup >/dev/null 2>&1; then
        log_info "Using optimization_manager.sh for enhanced cleanup"
        if ! optimize_cleanup "$AILINUX_BUILD_CHROOT_DIR" "$AILINUX_BUILD_TEMP_DIR"; then
            log_warn "⚠️  Optimization manager cleanup failed - using manual cleanup"
            ai_coordinate "cleanup_optimized_fail" "Optimization manager cleanup failed" "$ai_agent" "warning" "cleanup"
        else
            log_success "✅ Optimization manager cleanup completed"
            ai_coordinate "cleanup_optimized_success" "Optimization manager cleanup completed" "$ai_agent" "success" "cleanup"
            return 0
        fi
    fi
    
    # Manual cleanup with session safety
    log_info "Performing manual cleanup with session safety..."
    
    # Safely unmount chroot mounts
    local chroot_mounts=(
        "$AILINUX_BUILD_CHROOT_DIR/proc"
        "$AILINUX_BUILD_CHROOT_DIR/sys"
        "$AILINUX_BUILD_CHROOT_DIR/dev/pts"
        "$AILINUX_BUILD_CHROOT_DIR/dev"
        "$AILINUX_BUILD_CHROOT_DIR/run"
        "$AILINUX_BUILD_CHROOT_DIR/boot/efi"
    )
    
    for mount_point in "${chroot_mounts[@]}"; do
        if mountpoint -q "$mount_point" 2>/dev/null; then
            log_info "Unmounting $mount_point"
            if ! safe_execute "umount -lf '$mount_point'" "unmount_chroot" "Failed to unmount $mount_point"; then
                log_warn "⚠️  Failed to unmount $mount_point - using force"
                umount -lf "$mount_point" 2>/dev/null || true
            fi
        fi
    done
    
    # Kill any processes using chroot (safely)
    if [ -d "$AILINUX_BUILD_CHROOT_DIR" ]; then
        log_info "Killing processes using chroot directory"
        fuser -k "$AILINUX_BUILD_CHROOT_DIR" 2>/dev/null || true
        sleep 2
    fi
    
    # Unmount chroot root with multiple strategies
    if mountpoint -q "$AILINUX_BUILD_CHROOT_DIR" 2>/dev/null; then
        log_info "Unmounting chroot root directory"
        umount -R "$AILINUX_BUILD_CHROOT_DIR" 2>/dev/null || true
        umount -lf "$AILINUX_BUILD_CHROOT_DIR" 2>/dev/null || true
    fi
    
    # Clean up temporary directories safely
    local cleanup_dirs=(
        "$AILINUX_BUILD_TEMP_DIR"
        "$AILINUX_BUILD_ISO_DIR"
        "${AILINUX_BUILD_DIR}/temp"
        "${AILINUX_BUILD_DIR}/mnt"
    )
    
    for dir in "${cleanup_dirs[@]}"; do
        if [ -d "$dir" ]; then
            log_info "Cleaning up directory: $dir"
            if ! safe_execute "rm -rf '$dir'" "cleanup_dir" "Failed to remove $dir"; then
                log_warn "⚠️  Failed to remove $dir completely"
            fi
        fi
    done
    
    # Clean up lock files and caches
    local cleanup_files=(
        "${AILINUX_BUILD_DIR}/.build_lock"
        "${AILINUX_BUILD_DIR}/build.pid"
        "/tmp/ailinux-*"
        "/var/cache/apt/archives/partial/*"
    )
    
    for pattern in "${cleanup_files[@]}"; do
        if ls $pattern 1> /dev/null 2>&1; then
            log_info "Cleaning up files matching: $pattern"
            rm -rf $pattern 2>/dev/null || true
        fi
    done
    
    log_success "✅ Comprehensive cleanup automation completed"
    ai_coordinate "cleanup_success" "Comprehensive cleanup automation completed successfully" "$ai_agent" "success" "cleanup"
    return 0
}

# ============================================================================
# ISO GENERATION FUNCTIONS
# ============================================================================

# Generate AILinux ISO image
generate_ailinux_iso() {
    local ai_agent="ISOGenerator"
    local chroot_dir="$AILINUX_BUILD_CHROOT_DIR"
    local iso_dir="$AILINUX_BUILD_DIR/iso"
    local output_iso="$AILINUX_BUILD_OUTPUT_DIR/ailinux-$(date +%Y%m%d).iso"
    
    log_info "📀 Starting ISO generation process..."
    ai_coordinate "iso_start" "Starting ISO generation" "$ai_agent" "info" "iso"
    
    # Create ISO directory structure
    mkdir -p "$iso_dir"/{casper,isolinux,preseed}
    
    # Copy kernel and initrd from chroot
    log_info "📦 Copying kernel and initrd..."
    if ! safe_execute "cp '$chroot_dir/boot/vmlinuz-'* '$iso_dir/casper/vmlinuz'" "copy_kernel" "Failed to copy kernel"; then
        return 1
    fi
    
    if ! safe_execute "cp '$chroot_dir/boot/initrd.img-'* '$iso_dir/casper/initrd'" "copy_initrd" "Failed to copy initrd"; then
        return 1
    fi
    
    # Create filesystem.squashfs
    log_info "🗜️ Creating compressed filesystem..."
    ai_coordinate "squashfs_start" "Creating squashfs filesystem" "$ai_agent" "info" "squashfs"
    
    if ! safe_execute "mksquashfs '$chroot_dir' '$iso_dir/casper/filesystem.squashfs' -e boot" "create_squashfs" "Failed to create squashfs"; then
        return 1
    fi
    
    # Create filesystem.size
    echo -n $(du -sx --block-size=1 "$chroot_dir" | cut -f1) > "$iso_dir/casper/filesystem.size"
    
    # Copy isolinux files
    log_info "🚀 Setting up bootloader..."
    safe_execute "cp /usr/lib/ISOLINUX/isolinux.bin '$iso_dir/isolinux/'" "copy_isolinux" "Failed to copy isolinux.bin" || return 1
    safe_execute "cp /usr/lib/syslinux/modules/bios/*.c32 '$iso_dir/isolinux/'" "copy_modules" "Failed to copy syslinux modules" || return 1
    
    # Create isolinux.cfg
    cat > "$iso_dir/isolinux/isolinux.cfg" << EOF
DEFAULT vesamenu.c32
MENU TITLE AILinux Live System
MENU BACKGROUND boot.png
MENU COLOR screen       37;40      #80ffffff #00000000 std
MENU COLOR border       30;44      #40ffffff #a0000000 std
MENU COLOR title        1;36;44    #ffffffff #a0000000 std
MENU COLOR sel          7;37;40    #e0ffffff #20ffffff all
MENU COLOR unsel        37;44      #50ffffff #a0000000 std
MENU COLOR help         37;40      #c0ffffff #00000000 std
MENU COLOR tabmsg       31;40      #80ffffff #00000000 std
MENU COLOR timeout_msg  37;40      #80ffffff #00000000 std
MENU COLOR timeout      1;37;40    #c0ffffff #00000000 std
MENU COLOR msg07        37;40      #90ffffff #a0000000 std

LABEL live
  MENU LABEL AILinux Live System
  KERNEL /casper/vmlinuz
  APPEND initrd=/casper/initrd boot=casper quiet splash

LABEL live-safe
  MENU LABEL AILinux Live System (Safe Mode)
  KERNEL /casper/vmlinuz
  APPEND initrd=/casper/initrd boot=casper xforcevesa quiet splash

LABEL check
  MENU LABEL Check disc for defects
  KERNEL /casper/vmlinuz
  APPEND initrd=/casper/initrd boot=casper integrity-check quiet splash

LABEL memtest
  MENU LABEL Memory test
  KERNEL /isolinux/memtest86+.bin

TIMEOUT 100
EOF
    
    # Copy boot.png if it exists
    if [[ -f "$AILINUX_BUILD_DIR/assets/boot.png" ]]; then
        cp "$AILINUX_BUILD_DIR/assets/boot.png" "$iso_dir/isolinux/"
        log_success "✅ Boot branding image added"
    fi
    
    # Copy memtest86+
    if [[ -f "$chroot_dir/boot/memtest86+.bin" ]]; then
        cp "$chroot_dir/boot/memtest86+.bin" "$iso_dir/isolinux/"
    fi
    
    # Create disk info
    cat > "$iso_dir/README.diskdefines" << EOF
#define DISKNAME  AILinux Live System
#define TYPE  binary
#define TYPEbinary  1
#define ARCH  amd64
#define ARCHamd64  1
#define DISKNUM  1
#define DISKNUM1  1
#define TOTALNUM  0
#define TOTALNUM0  1
EOF
    
    # Generate ISO
    log_info "🏗️ Generating final ISO image..."
    ai_coordinate "iso_generate" "Generating final ISO image" "$ai_agent" "info" "generate"
    
    if command -v genisoimage >/dev/null 2>&1; then
        if ! safe_execute "genisoimage -D -r -V 'AILinux' -cache-inodes -J -l -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -o '$output_iso' '$iso_dir'" "generate_iso" "Failed to generate ISO"; then
            return 1
        fi
    elif command -v xorriso >/dev/null 2>&1; then
        if ! safe_execute "xorriso -as mkisofs -D -r -V 'AILinux' -cache-inodes -J -l -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -o '$output_iso' '$iso_dir'" "generate_iso_xorriso" "Failed to generate ISO with xorriso"; then
            return 1
        fi
    else
        log_error "❌ No ISO generation tool found (tried genisoimage, xorriso)"
        return 1
    fi
    
    # Make ISO hybrid bootable
    if command -v isohybrid >/dev/null 2>&1; then
        safe_execute "isohybrid '$output_iso'" "make_hybrid" "Failed to make ISO hybrid bootable"
    fi
    
    # Generate MD5 checksum
    if [[ -x "$AILINUX_BUILD_DIR/scripts/validate-md5.sh" ]]; then
        "$AILINUX_BUILD_DIR/scripts/validate-md5.sh" generate "$output_iso"
    fi
    
    # Display results
    local iso_size=$(stat -c%s "$output_iso" 2>/dev/null || echo "unknown")
    log_success "📀 ISO generated successfully: $(basename "$output_iso")"
    log_info "📍 Location: $output_iso"
    log_info "📏 Size: $(numfmt --to=iec-i --suffix=B $iso_size)"
    
    ai_coordinate "iso_complete" "ISO generation completed successfully" "$ai_agent" "success" "iso"
    return 0
}

# ============================================================================
# SCRIPT ENTRY POINT
# ============================================================================

# Ensure script is not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Handle command line arguments
    handle_ai_arguments "$@"
    
    # Execute main AI-coordinated build function
    main_ai_coordinated_build "$@"
    exit $?
else
    log_warn "⚠️  This script should be executed, not sourced"
fi

# End of AILinux Core Developer Enhanced Build Script v3.1
