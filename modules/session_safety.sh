#!/bin/bash
#
# Session Safety Module for AILinux Build Script
# Provides isolation patterns and session protection mechanisms
#
# This module ensures that build operations do not interfere with the user's
# current session, preventing logout or session termination issues.
#

# Global session safety configuration
declare -g SESSION_TYPE=""
declare -g SESSION_PID=""
declare -g INITIAL_SESSION_PROCS=""
declare -g SESSION_SERVICES=()
declare -g PROTECTED_PROCESSES=()

# Initialize session safety monitoring
init_session_safety() {
    log_info "🛡️  Initializing session safety monitoring..."
    
    # Detect session type
    detect_session_type
    
    # Store initial session state
    capture_session_state
    
    # Set up session monitoring
    setup_session_monitoring
    
    # Configure protection mechanisms
    configure_session_protection
    
    log_success "Session safety monitoring initialized for $SESSION_TYPE session"
}

# Detect the type of session (SSH, GUI, console)
detect_session_type() {
    if [ -n "$SSH_CLIENT" ] || [ -n "$SSH_TTY" ] || [ -n "$SSH_CONNECTION" ]; then
        SESSION_TYPE="ssh"
        log_info "SSH session detected: ${SSH_CLIENT:-$SSH_TTY}"
    elif [ "$XDG_SESSION_TYPE" = "x11" ] || [ "$XDG_SESSION_TYPE" = "wayland" ]; then
        SESSION_TYPE="gui"
        log_info "Graphical session detected: $XDG_SESSION_TYPE"
    elif [ -t 0 ] && [ -t 1 ] && [ -t 2 ]; then
        SESSION_TYPE="console"
        log_info "Console session detected"
    else
        SESSION_TYPE="unknown"
        log_warn "Unknown session type detected"
    fi
    
    # Store session PID for monitoring
    SESSION_PID="$$"
    export AILINUX_BUILD_SESSION_TYPE="$SESSION_TYPE"
    export AILINUX_BUILD_SESSION_PID="$SESSION_PID"
}

# Capture initial session state for comparison
capture_session_state() {
    log_info "📊 Capturing initial session state..."
    
    # Count initial processes
    INITIAL_SESSION_PROCS=$(pgrep -u "$USER" | wc -l)
    
    # Identify session-critical services
    identify_session_services
    
    # Store parent process information
    store_parent_process_info
    
    # Create session state checkpoint
    create_session_checkpoint
}

# Identify services that are critical to the user session
identify_session_services() {
    SESSION_SERVICES=()
    
    case "$SESSION_TYPE" in
        "gui")
            # GUI session services
            SESSION_SERVICES+=(
                "display-manager"
                "gdm3"
                "lightdm"
                "sddm"
                "NetworkManager"
                "pulseaudio"
                "pipewire"
                "dbus"
            )
            ;;
        "ssh")
            # SSH session services
            SESSION_SERVICES+=(
                "ssh"
                "sshd"
                "NetworkManager"
                "systemd-logind"
            )
            ;;
        "console")
            # Console session services
            SESSION_SERVICES+=(
                "getty"
                "systemd-logind"
                "NetworkManager"
            )
            ;;
    esac
    
    log_info "Identified ${#SESSION_SERVICES[@]} session-critical services"
}

# Store parent process information for protection
store_parent_process_info() {
    local parent_pid="$PPID"
    
    # Store parent process tree
    PROTECTED_PROCESSES=("$parent_pid")
    
    # Add all ancestor processes
    while [ "$parent_pid" -gt 1 ]; do
        parent_pid=$(ps -o ppid= -p "$parent_pid" 2>/dev/null | tr -d ' ')
        if [ -n "$parent_pid" ] && [ "$parent_pid" -gt 1 ]; then
            PROTECTED_PROCESSES+=("$parent_pid")
        else
            break
        fi
    done
    
    log_info "Protected ${#PROTECTED_PROCESSES[@]} parent processes from termination"
}

# Create a session state checkpoint
create_session_checkpoint() {
    local checkpoint_file="/tmp/ailinux_session_checkpoint_$$"
    
    {
        echo "# AILinux Build Session Checkpoint"
        echo "SESSION_TYPE=$SESSION_TYPE"
        echo "SESSION_PID=$SESSION_PID"
        echo "INITIAL_PROCS=$INITIAL_SESSION_PROCS"
        echo "TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')"
        echo "USER=$USER"
        echo "PWD=$PWD"
        echo "PROTECTED_PROCESSES=(${PROTECTED_PROCESSES[*]})"
        
        # Store environment variables
        echo "# Environment Variables"
        env | grep -E '^(DISPLAY|XDG_|SSH_|TERM|HOME|USER)' | while read -r var; do
            echo "SAVED_$var"
        done
        
        # Store running services
        echo "# Running Services"
        systemctl --user list-units --state=running 2>/dev/null | grep -E '\.service' || true
        
    } > "$checkpoint_file"
    
    export AILINUX_SESSION_CHECKPOINT="$checkpoint_file"
    log_info "Session checkpoint created: $checkpoint_file"
}

# Set up continuous session monitoring
setup_session_monitoring() {
    # Monitor session process count
    monitor_process_count &
    local monitor_pid=$!
    
    # Store monitor PID for cleanup
    echo "$monitor_pid" > "/tmp/ailinux_session_monitor_pid_$$"
    
    # Set up signal handlers for session protection
    setup_session_signal_handlers
}

# Monitor session process count for unexpected changes
monitor_process_count() {
    while sleep 30; do
        local current_procs=$(pgrep -u "$USER" | wc -l)
        local proc_diff=$((current_procs - INITIAL_SESSION_PROCS))
        
        if [ "$proc_diff" -lt -10 ]; then
            log_warn "⚠️  Significant process reduction detected: $proc_diff processes"
            verify_session_integrity
        elif [ "$proc_diff" -gt 50 ]; then
            log_warn "⚠️  Process explosion detected: +$proc_diff processes"
        fi
        
        # Update process count
        INITIAL_SESSION_PROCS="$current_procs"
    done
}

# Configure session protection mechanisms
configure_session_protection() {
    # Set safe process limits
    ulimit -u 4096 2>/dev/null || true
    
    # Configure safe signal handling
    set +e  # Disable aggressive error handling
    
    # Set up cleanup traps that preserve session
    trap 'safe_cleanup_on_exit' EXIT
    trap 'safe_cleanup_on_signal' INT TERM
    
    log_info "Session protection mechanisms configured"
}

# Set up signal handlers that protect the session
setup_session_signal_handlers() {
    # Handle SIGINT (Ctrl+C) gracefully
    trap 'handle_session_interrupt' INT
    
    # Handle SIGTERM gracefully
    trap 'handle_session_termination' TERM
    
    # Handle script exit
    trap 'handle_session_exit' EXIT
}

# Handle session interrupt (Ctrl+C)
handle_session_interrupt() {
    log_warn "🛑 Build interrupted by user - performing safe cleanup..."
    
    # Stop monitoring
    stop_session_monitoring
    
    # Clean up build processes without affecting session
    cleanup_build_processes_safely
    
    # Verify session is still intact
    verify_session_integrity
    
    log_info "Safe interrupt cleanup completed"
    exit 130  # Standard exit code for SIGINT
}

# Handle session termination signal
handle_session_termination() {
    log_warn "🛑 Build termination requested - performing safe cleanup..."
    
    # Emergency session protection
    protect_session_from_termination
    
    # Clean up safely
    cleanup_build_processes_safely
    
    # Verify session integrity
    verify_session_integrity
    
    log_info "Safe termination cleanup completed"
    exit 143  # Standard exit code for SIGTERM
}

# Handle script exit
handle_session_exit() {
    local exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        log_warn "Build script exiting with code $exit_code - verifying session safety"
        verify_session_integrity
    fi
    
    # Clean up monitoring
    stop_session_monitoring
    
    # Remove checkpoint file
    if [ -n "$AILINUX_SESSION_CHECKPOINT" ] && [ -f "$AILINUX_SESSION_CHECKPOINT" ]; then
        rm -f "$AILINUX_SESSION_CHECKPOINT"
    fi
}

# Check if a service is critical to the user session
is_session_critical_service() {
    local service="$1"
    
    for critical_service in "${SESSION_SERVICES[@]}"; do
        if [[ "$service" == *"$critical_service"* ]]; then
            return 0
        fi
    done
    
    return 1
}

# Check if a process should be protected from termination
is_protected_process() {
    local pid="$1"
    
    for protected_pid in "${PROTECTED_PROCESSES[@]}"; do
        if [ "$pid" = "$protected_pid" ]; then
            return 0
        fi
    done
    
    return 1
}

# Verify session integrity
verify_session_integrity() {
    log_info "🔍 Verifying session integrity..."
    
    local issues=0
    
    # Check if parent shell is still running
    if ! kill -0 "$PPID" 2>/dev/null; then
        log_error "❌ Parent shell process appears to be terminated"
        ((issues++))
    fi
    
    # Check session services
    for service in "${SESSION_SERVICES[@]}"; do
        if systemctl is-active "$service" >/dev/null 2>&1; then
            continue
        elif systemctl --user is-active "$service" >/dev/null 2>&1; then
            continue
        else
            log_warn "⚠️  Session service $service is not running"
        fi
    done
    
    # Check session environment
    case "$SESSION_TYPE" in
        "gui")
            if [ -z "$DISPLAY" ] && [ -z "$WAYLAND_DISPLAY" ]; then
                log_warn "⚠️  No display environment found"
                ((issues++))
            fi
            ;;
        "ssh")
            if [ -z "$SSH_CLIENT" ] && [ -z "$SSH_TTY" ]; then
                log_warn "⚠️  SSH environment variables missing"
                ((issues++))
            fi
            ;;
    esac
    
    if [ $issues -eq 0 ]; then
        log_success "✅ Session integrity verified"
        return 0
    else
        log_warn "⚠️  Session integrity issues detected: $issues"
        return 1
    fi
}

# Protect session from termination
protect_session_from_termination() {
    log_info "🛡️  Activating emergency session protection..."
    
    # Ensure parent processes are not killed
    for pid in "${PROTECTED_PROCESSES[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            # Send SIGSTOP to prevent termination, then SIGCONT to resume
            kill -STOP "$pid" 2>/dev/null || true
            sleep 0.1
            kill -CONT "$pid" 2>/dev/null || true
        fi
    done
}

# Stop session monitoring
stop_session_monitoring() {
    local monitor_pid_file="/tmp/ailinux_session_monitor_pid_$$"
    
    if [ -f "$monitor_pid_file" ]; then
        local monitor_pid=$(cat "$monitor_pid_file")
        if kill -0 "$monitor_pid" 2>/dev/null; then
            kill "$monitor_pid" 2>/dev/null || true
        fi
        rm -f "$monitor_pid_file"
    fi
}

# Safely clean up build processes without affecting session
cleanup_build_processes_safely() {
    log_info "🧹 Cleaning up build processes safely..."
    
    # List of build-specific processes to clean up
    local build_processes=(
        "debootstrap"
        "mksquashfs"
        "xorriso"
        "grub-install"
        "update-grub"
    )
    
    for process in "${build_processes[@]}"; do
        local pids=$(pgrep -f "$process" 2>/dev/null || true)
        
        for pid in $pids; do
            # Only kill if it's not a protected process
            if ! is_protected_process "$pid"; then
                log_info "Terminating build process: $process (PID: $pid)"
                kill -TERM "$pid" 2>/dev/null || true
                
                # Wait for graceful termination
                sleep 2
                
                # Force kill if still running
                if kill -0 "$pid" 2>/dev/null; then
                    kill -KILL "$pid" 2>/dev/null || true
                fi
            fi
        done
    done
}

# Safe cleanup on script exit
safe_cleanup_on_exit() {
    local exit_code=$?
    
    # Don't interfere if exiting successfully
    if [ $exit_code -eq 0 ]; then
        stop_session_monitoring
        return
    fi
    
    log_info "🛡️  Performing safe cleanup on exit (code: $exit_code)..."
    
    # Clean up build processes
    cleanup_build_processes_safely
    
    # Stop monitoring
    stop_session_monitoring
    
    # Verify session is intact
    verify_session_integrity
}

# Safe cleanup on signal
safe_cleanup_on_signal() {
    log_info "🛡️  Performing safe cleanup on signal..."
    
    # Protect session
    protect_session_from_termination
    
    # Clean up build processes
    cleanup_build_processes_safely
    
    # Verify session integrity
    verify_session_integrity
}

# Export functions for use in other modules
export -f init_session_safety
export -f detect_session_type
export -f is_session_critical_service
export -f is_protected_process
export -f verify_session_integrity
export -f cleanup_build_processes_safely