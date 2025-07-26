#!/bin/bash
#
# Error Handling Module for AILinux Build Script
# Provides granular error handling without aggressive exits
#
# This module replaces the problematic 'set -eo pipefail' with intelligent
# error handling that doesn't terminate the user session.
#

# Global error handling configuration
declare -g ERROR_HANDLING_MODE="graceful"  # Options: graceful, strict, permissive
declare -g RECOVERY_ATTEMPTS=3
declare -g ENABLE_AUTO_RECOVERY=true
declare -g ERROR_LOG_FILE=""
declare -g OPERATION_STACK=()
declare -g FAILED_OPERATIONS=()

# Initialize error handling system
init_error_handling() {
    log_info "🛠️  Initializing intelligent error handling system..."
    
    # Set error handling mode
    configure_error_mode
    
    # Set up error logging
    setup_error_logging
    
    # Configure recovery mechanisms
    setup_recovery_mechanisms
    
    # Initialize operation tracking
    init_operation_tracking
    
    log_success "Error handling system initialized in $ERROR_HANDLING_MODE mode"
}

# Configure error handling mode based on environment
configure_error_mode() {
    # Check if in development environment
    if [ -n "$AILINUX_DEV_MODE" ]; then
        ERROR_HANDLING_MODE="permissive"
        log_info "Development mode detected - using permissive error handling"
    # Check if in CI/automated environment
    elif [ -n "$CI" ] || [ -n "$AUTOMATED_BUILD" ]; then
        ERROR_HANDLING_MODE="strict"
        log_info "Automated environment detected - using strict error handling"
    else
        ERROR_HANDLING_MODE="graceful"
        log_info "Interactive environment detected - using graceful error handling"
    fi
    
    # Disable aggressive bash error handling
    set +e  # Don't exit on error
    set +o pipefail  # Don't exit on pipe failures
    
    # But keep undefined variable protection with modification
    set -u
}

# Set up comprehensive error logging
setup_error_logging() {
    ERROR_LOG_FILE="${LOG_FILE}.errors"
    
    # Create error log with header
    cat > "$ERROR_LOG_FILE" << EOF
# AILinux Build Error Log
# Started: $(date)
# Mode: $ERROR_HANDLING_MODE
# Session: $AILINUX_BUILD_SESSION_TYPE
# PID: $$
EOF
    
    log_info "Error logging initialized: $ERROR_LOG_FILE"
}

# Set up recovery mechanisms
setup_recovery_mechanisms() {
    # Set up recovery checkpoint directory
    mkdir -p "/tmp/ailinux_recovery_$$"
    export AILINUX_RECOVERY_DIR="/tmp/ailinux_recovery_$$"
    
    # Initialize recovery state
    echo "0" > "$AILINUX_RECOVERY_DIR/recovery_count"
    echo "$(date)" > "$AILINUX_RECOVERY_DIR/recovery_started"
    
    log_info "Recovery mechanisms initialized"
}

# Initialize operation tracking
init_operation_tracking() {
    OPERATION_STACK=()
    FAILED_OPERATIONS=()
    
    # Create operation tracking file
    echo "# Operation Stack" > "/tmp/ailinux_operations_$$"
    export AILINUX_OPERATIONS_FILE="/tmp/ailinux_operations_$$"
}

# Enhanced safe execution function
safe_execute() {
    local cmd="$1"
    local operation_name="${2:-unknown_operation}"
    local error_msg="${3:-Command failed}"
    local recovery_action="${4:-}"
    local allow_failure="${5:-false}"
    
    # Track operation start
    track_operation_start "$operation_name" "$cmd"
    
    log_info "🔧 Executing: $operation_name"
    
    local exit_code=0
    local output=""
    local start_time=$(date +%s)
    
    # Execute command with output capture
    if output=$(eval "$cmd" 2>&1); then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        track_operation_success "$operation_name" "$duration"
        log_success "✅ $operation_name completed in ${duration}s"
        return 0
    else
        exit_code=$?
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        # Log the error
        log_error_details "$operation_name" "$cmd" "$exit_code" "$output" "$duration"
        
        # Handle error based on mode and recovery options
        handle_operation_error "$operation_name" "$cmd" "$exit_code" "$output" "$recovery_action" "$allow_failure"
        
        return $exit_code
    fi
}

# Enhanced error logging with context
log_error_details() {
    local operation="$1"
    local command="$2"
    local exit_code="$3"
    local output="$4"
    local duration="$5"
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Log to main log
    log_error "❌ $operation failed (exit code: $exit_code, duration: ${duration}s)"
    
    # Log detailed error information
    cat >> "$ERROR_LOG_FILE" << EOF

[$timestamp] ERROR: $operation
Command: $command
Exit Code: $exit_code
Duration: ${duration}s
Output:
$output
---
EOF
    
    # Track in swarm coordination
    swarm_coordinate "operation_failed" "$operation failed with exit code $exit_code" "error" "execution"
}

# Handle operation errors intelligently
handle_operation_error() {
    local operation="$1"
    local command="$2"
    local exit_code="$3"
    local output="$4"
    local recovery_action="$5"
    local allow_failure="$6"
    
    # Track failed operation
    FAILED_OPERATIONS+=("$operation:$exit_code")
    
    # Check if failure is allowed
    if [ "$allow_failure" = "true" ]; then
        log_warn "⚠️  $operation failed but failure is allowed, continuing..."
        track_operation_allowed_failure "$operation"
        return 0
    fi
    
    # Handle based on error handling mode
    case "$ERROR_HANDLING_MODE" in
        "permissive")
            handle_permissive_error "$operation" "$command" "$exit_code" "$recovery_action"
            ;;
        "strict")
            handle_strict_error "$operation" "$command" "$exit_code" "$recovery_action"
            ;;
        "graceful")
            handle_graceful_error "$operation" "$command" "$exit_code" "$recovery_action"
            ;;
    esac
}

# Handle errors in permissive mode
handle_permissive_error() {
    local operation="$1"
    local command="$2"
    local exit_code="$3"
    local recovery_action="$4"
    
    log_warn "⚠️  $operation failed in permissive mode - attempting to continue"
    
    # Try recovery if available
    if [ -n "$recovery_action" ] && [ "$ENABLE_AUTO_RECOVERY" = "true" ]; then
        attempt_recovery "$operation" "$recovery_action"
    fi
    
    # Continue execution
    return 0
}

# Handle errors in strict mode
handle_strict_error() {
    local operation="$1"
    local command="$2"
    local exit_code="$3"
    local recovery_action="$4"
    
    log_error "💥 $operation failed in strict mode"
    
    # Try recovery if available
    if [ -n "$recovery_action" ] && [ "$ENABLE_AUTO_RECOVERY" = "true" ]; then
        if attempt_recovery "$operation" "$recovery_action"; then
            log_success "🔄 Recovery successful, continuing in strict mode"
            return 0
        fi
    fi
    
    # In strict mode, we still don't exit immediately to preserve session
    log_critical "🚨 Critical failure in strict mode - build cannot continue safely"
    
    # Perform safe cleanup
    perform_safe_failure_cleanup
    
    # Return error code but don't exit
    return $exit_code
}

# Handle errors in graceful mode (default)
handle_graceful_error() {
    local operation="$1"
    local command="$2"
    local exit_code="$3"
    local recovery_action="$4"
    
    log_warn "⚠️  $operation failed - analyzing recovery options..."
    
    # Analyze error type
    local error_type=$(analyze_error_type "$exit_code" "$output")
    
    # Try intelligent recovery
    if attempt_intelligent_recovery "$operation" "$command" "$error_type" "$recovery_action"; then
        log_success "🔄 Graceful recovery successful"
        return 0
    fi
    
    # If recovery fails, check if we can continue
    if can_continue_after_failure "$operation"; then
        log_warn "⚠️  Continuing build despite $operation failure"
        return 0
    fi
    
    # If we can't continue, perform safe cleanup
    log_error "💥 Cannot continue after $operation failure"
    perform_safe_failure_cleanup
    return $exit_code
}

# Analyze error type for intelligent recovery
analyze_error_type() {
    local exit_code="$1"
    local output="$2"
    
    # Common error patterns
    if echo "$output" | grep -q -i "permission denied"; then
        echo "permission"
    elif echo "$output" | grep -q -i "no space left"; then
        echo "disk_space"
    elif echo "$output" | grep -q -i "network\|connection\|timeout"; then
        echo "network"
    elif echo "$output" | grep -q -i "package\|apt\|dpkg"; then
        echo "package"
    elif echo "$output" | grep -q -i "mount\|busy"; then
        echo "mount"
    elif [ "$exit_code" -eq 130 ]; then
        echo "interrupted"
    else
        echo "unknown"
    fi
}

# Attempt intelligent recovery based on error type
attempt_intelligent_recovery() {
    local operation="$1"
    local command="$2"
    local error_type="$3"
    local recovery_action="$4"
    
    log_info "🔄 Attempting intelligent recovery for $error_type error..."
    
    case "$error_type" in
        "permission")
            recover_permission_error "$operation" "$command"
            ;;
        "disk_space")
            recover_disk_space_error "$operation" "$command"
            ;;
        "network")
            recover_network_error "$operation" "$command"
            ;;
        "package")
            recover_package_error "$operation" "$command"
            ;;
        "mount")
            recover_mount_error "$operation" "$command"
            ;;
        "interrupted")
            log_info "Operation was interrupted - no recovery needed"
            return 0
            ;;
        *)
            # Try custom recovery action if provided
            if [ -n "$recovery_action" ]; then
                attempt_recovery "$operation" "$recovery_action"
            else
                return 1
            fi
            ;;
    esac
}

# Recovery for permission errors
recover_permission_error() {
    local operation="$1"
    local command="$2"
    
    log_info "🔐 Attempting permission recovery..."
    
    # Check if command needs sudo
    if echo "$command" | grep -q -v "sudo"; then
        log_info "Retrying with sudo privileges..."
        local sudo_command="sudo $command"
        
        if safe_execute "$sudo_command" "${operation}_recovery" "Sudo recovery failed" "" "true"; then
            return 0
        fi
    fi
    
    return 1
}

# Recovery for disk space errors
recover_disk_space_error() {
    local operation="$1"
    local command="$2"
    
    log_info "💾 Attempting disk space recovery..."
    
    # Clean up temporary files
    sudo rm -rf /tmp/debootstrap* 2>/dev/null || true
    sudo rm -rf /var/cache/apt/archives/*.deb 2>/dev/null || true
    
    # Clean package cache
    sudo apt-get clean 2>/dev/null || true
    
    log_info "Disk space cleanup completed - retrying operation..."
    
    # Retry the original command
    if eval "$command" >/dev/null 2>&1; then
        return 0
    fi
    
    return 1
}

# Recovery for network errors
recover_network_error() {
    local operation="$1"
    local command="$2"
    
    log_info "🌐 Attempting network recovery..."
    
    # Wait for network to stabilize
    sleep 5
    
    # Test network connectivity
    if wget -q --spider http://archive.ubuntu.com/ubuntu/dists/noble/Release; then
        log_info "Network connectivity restored - retrying operation..."
        
        # Retry the original command
        if eval "$command" >/dev/null 2>&1; then
            return 0
        fi
    fi
    
    return 1
}

# Recovery for package errors
recover_package_error() {
    local operation="$1"
    local command="$2"
    
    log_info "📦 Attempting package recovery..."
    
    # Update package lists
    sudo apt-get update >/dev/null 2>&1 || true
    
    # Fix broken packages
    sudo apt-get --fix-broken install -y >/dev/null 2>&1 || true
    
    # Clean package cache
    sudo apt-get clean >/dev/null 2>&1 || true
    
    # Retry the original command
    if eval "$command" >/dev/null 2>&1; then
        return 0
    fi
    
    return 1
}

# Recovery for mount errors
recover_mount_error() {
    local operation="$1"
    local command="$2"
    
    log_info "🗂️  Attempting mount recovery..."
    
    # Try to unmount any stuck mounts
    if echo "$command" | grep -q "mount"; then
        local mount_point=$(echo "$command" | grep -o "/[^ ]*" | head -1)
        if [ -n "$mount_point" ]; then
            sudo umount -l "$mount_point" 2>/dev/null || true
            sleep 2
        fi
    fi
    
    # Retry the original command
    if eval "$command" >/dev/null 2>&1; then
        return 0
    fi
    
    return 1
}

# Generic recovery attempt
attempt_recovery() {
    local operation="$1"
    local recovery_action="$2"
    
    local recovery_count_file="$AILINUX_RECOVERY_DIR/recovery_count"
    local current_count=$(cat "$recovery_count_file" 2>/dev/null || echo "0")
    
    if [ "$current_count" -ge "$RECOVERY_ATTEMPTS" ]; then
        log_error "❌ Maximum recovery attempts ($RECOVERY_ATTEMPTS) exceeded for $operation"
        return 1
    fi
    
    local new_count=$((current_count + 1))
    echo "$new_count" > "$recovery_count_file"
    
    log_info "🔄 Recovery attempt $new_count/$RECOVERY_ATTEMPTS for $operation"
    
    # Execute recovery action
    if eval "$recovery_action"; then
        log_success "✅ Recovery action successful"
        
        # Reset recovery count on success
        echo "0" > "$recovery_count_file"
        return 0
    else
        log_error "❌ Recovery action failed"
        return 1
    fi
}

# Check if build can continue after a failure
can_continue_after_failure() {
    local operation="$1"
    
    # Critical operations that prevent continuation
    local critical_operations=(
        "debootstrap"
        "bootstrap_system"
        "create_base_system"
        "mount_essential_filesystems"
    )
    
    for critical in "${critical_operations[@]}"; do
        if [[ "$operation" == *"$critical"* ]]; then
            return 1  # Cannot continue
        fi
    done
    
    return 0  # Can continue
}

# Perform safe cleanup on failure
perform_safe_failure_cleanup() {
    log_info "🧹 Performing safe failure cleanup..."
    
    # Source session safety module for safe cleanup
    if [ -f "modules/session_safety.sh" ]; then
        source modules/session_safety.sh
        cleanup_build_processes_safely
    fi
    
    # Clean up temporary recovery files
    if [ -n "$AILINUX_RECOVERY_DIR" ] && [ -d "$AILINUX_RECOVERY_DIR" ]; then
        rm -rf "$AILINUX_RECOVERY_DIR"
    fi
    
    # Generate failure report
    generate_failure_report
}

# Generate comprehensive failure report
generate_failure_report() {
    local failure_report="/tmp/ailinux_build_failure_report_$$.txt"
    
    cat > "$failure_report" << EOF
AILinux Build Failure Report
===========================
Date: $(date)
Session Type: $AILINUX_BUILD_SESSION_TYPE
Error Handling Mode: $ERROR_HANDLING_MODE
Total Failed Operations: ${#FAILED_OPERATIONS[@]}

Failed Operations:
$(printf '%s\n' "${FAILED_OPERATIONS[@]}")

Error Log Location: $ERROR_LOG_FILE
Recovery Directory: $AILINUX_RECOVERY_DIR

Session Status: $(verify_session_integrity 2>&1 || echo "Session integrity check failed")

Recommendations:
1. Check the detailed error log: $ERROR_LOG_FILE
2. Verify system resources (disk space, memory)
3. Check network connectivity
4. Review failed operations above
5. Consider running in permissive mode for testing

EOF
    
    log_error "💥 Build failed - detailed report: $failure_report"
    swarm_coordinate "build_failed" "Build failure report generated: $failure_report" "error" "cleanup"
}

# Track operation start
track_operation_start() {
    local operation="$1"
    local command="$2"
    
    OPERATION_STACK+=("$operation")
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] START: $operation - $command" >> "$AILINUX_OPERATIONS_FILE"
}

# Track operation success
track_operation_success() {
    local operation="$1"
    local duration="$2"
    
    # Remove from stack
    local new_stack=()
    for op in "${OPERATION_STACK[@]}"; do
        [ "$op" != "$operation" ] && new_stack+=("$op")
    done
    OPERATION_STACK=("${new_stack[@]}")
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $operation (${duration}s)" >> "$AILINUX_OPERATIONS_FILE"
}

# Track allowed failure
track_operation_allowed_failure() {
    local operation="$1"
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ALLOWED_FAILURE: $operation" >> "$AILINUX_OPERATIONS_FILE"
}

# Wrapper for commands that should never fail
critical_execute() {
    local cmd="$1"
    local operation_name="${2:-critical_operation}"
    local error_msg="${3:-Critical command failed}"
    
    if ! safe_execute "$cmd" "$operation_name" "$error_msg"; then
        log_critical "🚨 Critical operation failed: $operation_name"
        perform_safe_failure_cleanup
        return 1
    fi
}

# Wrapper for commands that can fail
optional_execute() {
    local cmd="$1"
    local operation_name="${2:-optional_operation}"
    local error_msg="${3:-Optional command failed}"
    
    safe_execute "$cmd" "$operation_name" "$error_msg" "" "true"
}

# Wrapper for commands with custom recovery
recoverable_execute() {
    local cmd="$1"
    local operation_name="${2:-recoverable_operation}"
    local error_msg="${3:-Recoverable command failed}"
    local recovery_action="${4:-}"
    
    safe_execute "$cmd" "$operation_name" "$error_msg" "$recovery_action"
}

# Export functions for use in other modules
export -f init_error_handling
export -f safe_execute
export -f critical_execute
export -f optional_execute
export -f recoverable_execute
export -f can_continue_after_failure
export -f perform_safe_failure_cleanup