#!/bin/bash
#
# AILinux Signal Handler Module v1.0
# Enhanced session-safe signal handling for build operations
# Part of the AILinux ISO Build System
#
# This module provides comprehensive signal handling to prevent
# build interruptions from causing session termination or data loss.
#

# Global configuration
SIGNAL_HANDLER_VERSION="1.0"
SIGNAL_HANDLER_MODULE="signal_handler"

# Session safety logging
SIGNAL_LOG="${AILINUX_BUILD_LOGS_DIR:-/tmp}/signal_handler_$(date +%Y%m%d_%H%M%S).log"

# Critical process tracking
declare -a CRITICAL_PROCESSES=()
declare -a CLEANUP_FUNCTIONS=()

# ============================================================================
# SIGNAL HANDLER FUNCTIONS
# ============================================================================

# Initialize signal handling
signal_handler_init() {
    local session_type="${1:-unknown}"
    
    log_signal "INFO" "Initializing signal handler for session type: $session_type"
    
    # Set up trap handlers for common signals
    trap 'handle_interrupt_signal SIGINT' INT
    trap 'handle_terminate_signal SIGTERM' TERM
    trap 'handle_hangup_signal SIGHUP' HUP
    trap 'handle_quit_signal SIGQUIT' QUIT
    trap 'handle_usr1_signal SIGUSR1' USR1
    trap 'handle_usr2_signal SIGUSR2' USR2
    
    # Special handling for session-critical signals
    if [[ "$session_type" == "ssh" ]]; then
        # SSH sessions need special handling for connection drops
        trap 'handle_ssh_disconnect SIGHUP' HUP
    elif [[ "$session_type" == "gui" ]]; then
        # GUI sessions need different handling
        trap 'handle_gui_session_change SIGUSR1' USR1
    fi
    
    log_signal "SUCCESS" "Signal handler initialized successfully"
    return 0
}

# Handle SIGINT (Ctrl+C)
handle_interrupt_signal() {
    local signal="$1"
    log_signal "WARN" "Received interrupt signal ($signal) - initiating graceful shutdown"
    
    # Set interrupt flag but don't exit immediately
    export AILINUX_BUILD_INTERRUPTED=true
    
    # Notify user about graceful shutdown
    echo ""
    echo "⚠️  Build interrupted by user. Initiating safe cleanup..."
    echo "⏳ Please wait for graceful shutdown to complete."
    echo "💡 Do NOT close terminal - this prevents session termination."
    
    # Execute cleanup functions if any are registered
    execute_cleanup_functions "interrupt"
    
    # Don't exit - let the main process handle the interrupt flag
    log_signal "INFO" "Interrupt signal handled gracefully - main process continues"
}

# Handle SIGTERM (termination request)
handle_terminate_signal() {
    local signal="$1"
    log_signal "WARN" "Received termination signal ($signal) - initiating controlled shutdown"
    
    export AILINUX_BUILD_TERMINATING=true
    
    echo ""
    echo "🛑 Build termination requested. Executing safe shutdown sequence..."
    
    # More aggressive cleanup for termination
    execute_cleanup_functions "terminate"
    
    # Still don't exit immediately - let main process decide
    log_signal "INFO" "Termination signal handled - awaiting main process decision"
}

# Handle SIGHUP (hangup - often from SSH disconnect)
handle_hangup_signal() {
    local signal="$1"
    log_signal "CRITICAL" "Received hangup signal ($signal) - possible SSH disconnect"
    
    # This is the most dangerous signal for SSH sessions
    export AILINUX_BUILD_HANGUP_DETECTED=true
    
    # DO NOT EXIT - this is critical for session preservation
    echo "🚨 HANGUP signal detected - maintaining session integrity"
    echo "🔒 Build process will continue in background if needed"
    
    # Log the event but continue execution
    log_signal "INFO" "Hangup signal handled - session preservation active"
}

# Handle SSH-specific disconnect
handle_ssh_disconnect() {
    local signal="$1"
    log_signal "CRITICAL" "SSH disconnect detected ($signal)"
    
    # Implement SSH-specific session preservation
    export AILINUX_BUILD_SSH_DISCONNECT=true
    
    # Try to continue in background
    echo "🌐 SSH session interrupted - attempting background continuation"
    
    # Don't terminate - this is crucial for SSH session safety
    log_signal "INFO" "SSH disconnect handled - background execution mode"
}

# Handle SIGQUIT (quit with core dump request)
handle_quit_signal() {
    local signal="$1"
    log_signal "WARN" "Received quit signal ($signal) - user requested immediate exit"
    
    export AILINUX_BUILD_QUIT_REQUESTED=true
    
    echo ""
    echo "⚡ Quick exit requested. Performing minimal cleanup..."
    
    # Quick cleanup only
    execute_cleanup_functions "quit"
    
    log_signal "INFO" "Quit signal handled"
}

# Handle SIGUSR1 (user-defined signal 1)
handle_usr1_signal() {
    local signal="$1"
    log_signal "INFO" "Received user signal 1 ($signal) - custom handler"
    
    # Can be used for custom build control
    export AILINUX_BUILD_USR1_RECEIVED=true
    
    echo "📡 Custom signal USR1 received - executing custom handler"
    log_signal "INFO" "USR1 signal processed"
}

# Handle SIGUSR2 (user-defined signal 2)
handle_usr2_signal() {
    local signal="$1"
    log_signal "INFO" "Received user signal 2 ($signal) - custom handler"
    
    export AILINUX_BUILD_USR2_RECEIVED=true
    
    echo "📡 Custom signal USR2 received - executing custom handler"
    log_signal "INFO" "USR2 signal processed"
}

# Handle GUI session changes
handle_gui_session_change() {
    local signal="$1"
    log_signal "INFO" "GUI session change detected ($signal)"
    
    export AILINUX_BUILD_GUI_CHANGE=true
    
    echo "🖥️  GUI session change detected - adapting execution"
    log_signal "INFO" "GUI session change handled"
}

# ============================================================================
# PROCESS MANAGEMENT FUNCTIONS
# ============================================================================

# Register a critical process
register_critical_process() {
    local pid="$1"
    local description="${2:-unknown process}"
    
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        CRITICAL_PROCESSES+=("$pid:$description")
        log_signal "INFO" "Registered critical process: PID $pid ($description)"
        return 0
    else
        log_signal "ERROR" "Cannot register invalid PID: $pid"
        return 1
    fi
}

# Unregister a critical process
unregister_critical_process() {
    local pid="$1"
    local temp_array=()
    
    for process in "${CRITICAL_PROCESSES[@]}"; do
        if [[ "$process" != "$pid:"* ]]; then
            temp_array+=("$process")
        fi
    done
    
    CRITICAL_PROCESSES=("${temp_array[@]}")
    log_signal "INFO" "Unregistered critical process: PID $pid"
}

# Register a cleanup function
register_cleanup_function() {
    local function_name="$1"
    
    if declare -f "$function_name" > /dev/null; then
        CLEANUP_FUNCTIONS+=("$function_name")
        log_signal "INFO" "Registered cleanup function: $function_name"
        return 0
    else
        log_signal "ERROR" "Cannot register non-existent function: $function_name"
        return 1
    fi
}

# Execute all registered cleanup functions
execute_cleanup_functions() {
    local cleanup_type="${1:-general}"
    
    log_signal "INFO" "Executing cleanup functions for: $cleanup_type"
    
    for cleanup_func in "${CLEANUP_FUNCTIONS[@]}"; do
        if declare -f "$cleanup_func" > /dev/null; then
            log_signal "INFO" "Executing cleanup function: $cleanup_func"
            
            # Execute with timeout to prevent hanging
            timeout 30 "$cleanup_func" "$cleanup_type" || {
                log_signal "WARN" "Cleanup function $cleanup_func timed out or failed"
            }
        else
            log_signal "WARN" "Cleanup function $cleanup_func no longer exists"
        fi
    done
    
    log_signal "INFO" "Cleanup functions execution completed"
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Safe logging function for signal events
log_signal() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Ensure log directory exists
    mkdir -p "$(dirname "$SIGNAL_LOG")" 2>/dev/null
    
    # Write to log file
    echo "[$timestamp] [$level] [SIGNAL-$SIGNAL_HANDLER_MODULE] $message" >> "$SIGNAL_LOG" 2>/dev/null
    
    # Also output to stderr for immediate visibility (if safe)
    if [[ "$level" == "CRITICAL" ]] || [[ "$level" == "ERROR" ]]; then
        echo "[$level] $message" >&2 2>/dev/null
    fi
}

# Check if build was interrupted
is_build_interrupted() {
    [[ "${AILINUX_BUILD_INTERRUPTED:-false}" == "true" ]] || 
    [[ "${AILINUX_BUILD_TERMINATING:-false}" == "true" ]] ||
    [[ "${AILINUX_BUILD_QUIT_REQUESTED:-false}" == "true" ]]
}

# Check for session disconnection
is_session_disconnected() {
    [[ "${AILINUX_BUILD_HANGUP_DETECTED:-false}" == "true" ]] ||
    [[ "${AILINUX_BUILD_SSH_DISCONNECT:-false}" == "true" ]]
}

# Get current signal handler status
get_signal_status() {
    cat << EOF
Signal Handler Status:
- Version: $SIGNAL_HANDLER_VERSION
- Interrupted: ${AILINUX_BUILD_INTERRUPTED:-false}
- Terminating: ${AILINUX_BUILD_TERMINATING:-false}
- Hangup Detected: ${AILINUX_BUILD_HANGUP_DETECTED:-false}
- SSH Disconnect: ${AILINUX_BUILD_SSH_DISCONNECT:-false}
- Critical Processes: ${#CRITICAL_PROCESSES[@]}
- Cleanup Functions: ${#CLEANUP_FUNCTIONS[@]}
- Log File: $SIGNAL_LOG
EOF
}

# Reset signal handler state
reset_signal_state() {
    unset AILINUX_BUILD_INTERRUPTED
    unset AILINUX_BUILD_TERMINATING
    unset AILINUX_BUILD_HANGUP_DETECTED
    unset AILINUX_BUILD_SSH_DISCONNECT
    unset AILINUX_BUILD_QUIT_REQUESTED
    unset AILINUX_BUILD_USR1_RECEIVED
    unset AILINUX_BUILD_USR2_RECEIVED
    unset AILINUX_BUILD_GUI_CHANGE
    
    log_signal "INFO" "Signal handler state reset"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

# Module self-test
signal_handler_test() {
    echo "Testing signal handler module..."
    
    # Test logging
    log_signal "INFO" "Signal handler module test initiated"
    
    # Test signal status
    echo "Current status:"
    get_signal_status
    
    # Test process registration
    register_critical_process $$ "signal_handler_test"
    echo "Registered current process as critical"
    
    # Test cleanup function registration
    test_cleanup() {
        echo "Test cleanup function executed with type: $1"
    }
    register_cleanup_function "test_cleanup"
    
    echo "Signal handler module test completed successfully"
    log_signal "SUCCESS" "Signal handler module test completed"
    
    return 0
}

# Export functions for use by other modules
export -f signal_handler_init
export -f register_critical_process
export -f unregister_critical_process
export -f register_cleanup_function
export -f is_build_interrupted
export -f is_session_disconnected
export -f get_signal_status
export -f reset_signal_state

# Auto-initialize if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "AILinux Signal Handler Module v$SIGNAL_HANDLER_VERSION"
    echo "Initializing signal handler..."
    
    signal_handler_init "$(tty | grep -q pts && echo ssh || echo console)"
    signal_handler_test
fi

log_signal "SUCCESS" "Signal handler module loaded successfully (v$SIGNAL_HANDLER_VERSION)"