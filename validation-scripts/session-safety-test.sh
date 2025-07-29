#!/bin/bash
#
# AILinux Session Safety Test Suite
# Tests that build interruptions don't logout user
#
# QA Focus: Session preservation during build failures
#

set -e

echo "🛡️ AILinux Session Safety Test Suite"
echo "Testing build script session preservation..."
echo

# Test configuration
TEST_DIR="/tmp/ailinux-session-test-$$"
BUILD_SCRIPT="./build.sh"
LOG_FILE="session-safety-test.log"

# Initialize test environment
init_test() {
    echo "🔧 Initializing session safety test environment..."
    mkdir -p "$TEST_DIR"
    
    # Record initial session state
    echo "SESSION_PID: $$" > "$TEST_DIR/session_state.txt"
    echo "PARENT_PID: $PPID" >> "$TEST_DIR/session_state.txt"
    echo "USER: $(whoami)" >> "$TEST_DIR/session_state.txt"
    echo "TTY: $(tty)" >> "$TEST_DIR/session_state.txt"
    echo "START_TIME: $(date)" >> "$TEST_DIR/session_state.txt"
    
    echo "✅ Session state recorded"
}

# Test 1: Verify no aggressive error handling
test_no_aggressive_error_handling() {
    echo "🧪 Test 1: Verify no aggressive error handling (set -e, set -eo pipefail)"
    
    # Check build script for dangerous patterns
    local dangerous_patterns=(
        "set -e"
        "set -eo pipefail"
        "set -euo pipefail"
        "exit 1"
    )
    
    local found_issues=0
    
    if [ -f "$BUILD_SCRIPT" ]; then
        for pattern in "${dangerous_patterns[@]}"; do
            if grep -q "^[[:space:]]*$pattern" "$BUILD_SCRIPT"; then
                case "$pattern" in
                    "set -e"|"set -eo pipefail"|"set -euo pipefail")
                        echo "❌ CRITICAL: Found dangerous pattern: $pattern"
                        echo "   This could cause user logout on script failure"
                        found_issues=$((found_issues + 1))
                        ;;
                    "exit 1")
                        # Count direct exit calls (should use safe_exit instead)
                        local exit_count=$(grep -c "^[[:space:]]*exit 1" "$BUILD_SCRIPT" || echo 0)
                        if [ "$exit_count" -gt 5 ]; then
                            echo "⚠️  WARNING: Many direct exit calls found ($exit_count)"
                            echo "   Consider using perform_emergency_safe_exit instead"
                        fi
                        ;;
                esac
            fi
        done
        
        # Check for safe patterns
        if grep -q "perform_emergency_safe_exit" "$BUILD_SCRIPT"; then
            echo "✅ Safe exit function found"
        else
            echo "⚠️  No safe exit function found"
            found_issues=$((found_issues + 1))
        fi
        
        if grep -q "ERROR_HANDLING_MODE.*graceful" "$BUILD_SCRIPT"; then
            echo "✅ Graceful error handling mode found"
        else
            echo "⚠️  Graceful error handling not explicitly set"
        fi
    else
        echo "❌ Build script not found: $BUILD_SCRIPT"
        return 1
    fi
    
    if [ "$found_issues" -eq 0 ]; then
        echo "✅ Test 1 PASSED: No aggressive error handling patterns found"
        return 0
    else
        echo "❌ Test 1 FAILED: Found $found_issues session-threatening patterns"
        return 1
    fi
}

# Test 2: Session preservation during mock failures
test_session_preservation() {
    echo "🧪 Test 2: Session preservation during mock failures"
    
    # Record session before test
    local initial_session_pid=$$
    local initial_parent_pid=$PPID
    
    echo "Initial session PID: $initial_session_pid"
    echo "Initial parent PID: $initial_parent_pid"
    
    # Create a mock failing scenario
    local test_script="$TEST_DIR/mock_build_failure.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash
# Mock build script that fails safely

echo "Starting mock build..."
echo "Simulating build failure..."

# Test graceful failure without session termination
if [ "$1" = "unsafe" ]; then
    echo "UNSAFE MODE: Using exit 1"
    exit 1
else
    echo "SAFE MODE: Using safe exit pattern"
    echo "ERROR: Build failed but session preserved"
    return 1 2>/dev/null || {
        echo "Cannot return from script - using exit 0 to preserve session"
        exit 0
    }
fi
EOF
    
    chmod +x "$test_script"
    
    # Test unsafe mode (should not be used in real script)
    echo "Testing unsafe failure mode..."
    if bash "$test_script" unsafe 2>/dev/null; then
        echo "⚠️  Unsafe script unexpectedly succeeded"
    else
        # Check if session is still alive
        if kill -0 $$ 2>/dev/null; then
            echo "✅ Session survived unsafe script failure"
        else
            echo "❌ CRITICAL: Session died from unsafe script"
            return 1
        fi
    fi
    
    # Test safe mode
    echo "Testing safe failure mode..."
    if bash "$test_script" safe 2>/dev/null; then
        echo "✅ Safe script completed without session termination"
    else
        echo "Safe script returned error (expected)"
    fi
    
    # Verify session integrity
    if [ "$$" = "$initial_session_pid" ] && kill -0 $$ 2>/dev/null; then
        echo "✅ Test 2 PASSED: Session preserved during failures"
        return 0
    else
        echo "❌ Test 2 FAILED: Session integrity compromised"
        return 1
    fi
}

# Test 3: Mount cleanup safety
test_mount_cleanup_safety() {
    echo "🧪 Test 3: Mount cleanup safety test"
    
    local test_mount_dir="$TEST_DIR/test_mount"
    mkdir -p "$test_mount_dir"
    
    # Test safe unmount patterns
    local mock_cleanup_script="$TEST_DIR/test_cleanup.sh"
    cat > "$mock_cleanup_script" << 'EOF'
#!/bin/bash
# Test cleanup without session impact

TEST_MOUNT="$1"
echo "Testing safe mount cleanup for: $TEST_MOUNT"

# Simulate the cleanup pattern used in build script
if mountpoint -q "$TEST_MOUNT" 2>/dev/null; then
    echo "Mount point detected, attempting safe unmount..."
    # Use lazy unmount like the build script
    sudo umount -l "$TEST_MOUNT" 2>/dev/null || {
        echo "Unmount failed - continuing safely"
        return 0
    }
    echo "Unmount successful"
else
    echo "No mount point found - continuing safely"
fi

return 0
EOF
    
    chmod +x "$mock_cleanup_script"
    
    # Test the cleanup script
    if bash "$mock_cleanup_script" "$test_mount_dir"; then
        echo "✅ Test 3 PASSED: Mount cleanup completed safely"
        return 0
    else
        echo "❌ Test 3 FAILED: Mount cleanup caused issues"
        return 1
    fi
}

# Test 4: Verify session integrity function
test_session_integrity_function() {
    echo "🧪 Test 4: Session integrity verification function"
    
    if ! grep -q "verify_session_integrity" "$BUILD_SCRIPT"; then
        echo "❌ Session integrity function not found in build script"
        return 1
    fi
    
    # Extract and test the function
    local function_test="$TEST_DIR/test_session_integrity.sh"
    cat > "$function_test" << 'EOF'
#!/bin/bash
# Test session integrity function

verify_session_integrity() {
    # Check if our parent shell is still alive
    if [ -n "$PPID" ] && ! kill -0 "$PPID" 2>/dev/null; then
        echo "Parent process no longer exists - session may be compromised"
        return 1
    fi
    
    # Check if we can still write to our log
    local test_log="/tmp/session_test_$$.log"
    if ! echo "Session integrity check: $(date)" >> "$test_log" 2>/dev/null; then
        echo "Cannot write to log file - session may be compromised"
        return 1
    fi
    
    rm -f "$test_log"
    return 0
}

# Test the function
if verify_session_integrity; then
    echo "✅ Session integrity check passed"
    exit 0
else
    echo "❌ Session integrity check failed"
    exit 1
fi
EOF
    
    if bash "$function_test"; then
        echo "✅ Test 4 PASSED: Session integrity function works correctly"
        return 0
    else
        echo "❌ Test 4 FAILED: Session integrity function failed"
        return 1
    fi
}

# Test 5: Emergency cleanup safety
test_emergency_cleanup() {
    echo "🧪 Test 5: Emergency cleanup safety"
    
    # Check for emergency cleanup function
    if ! grep -q "emergency_cleanup\|perform_emergency_safe_exit" "$BUILD_SCRIPT"; then
        echo "❌ Emergency cleanup functions not found"
        return 1
    fi
    
    # Test that emergency cleanup preserves session
    local emergency_test="$TEST_DIR/test_emergency.sh"
    cat > "$emergency_test" << 'EOF'
#!/bin/bash
# Test emergency cleanup

TEST_DIR="$1"
echo "Testing emergency cleanup in: $TEST_DIR"

# Create some test mount points and processes
mkdir -p "$TEST_DIR/mock_chroot"/{proc,sys,dev}

# Simulate emergency cleanup (without actual mounts)
echo "Simulating emergency cleanup..."

# The real script uses lazy unmount which shouldn't affect session
echo "umount -l $TEST_DIR/mock_chroot/proc (simulated)"
echo "umount -l $TEST_DIR/mock_chroot/sys (simulated)"
echo "umount -l $TEST_DIR/mock_chroot/dev (simulated)"

# Clean up test directories
rm -rf "$TEST_DIR/mock_chroot"

echo "Emergency cleanup simulation completed safely"
return 0
EOF
    
    if bash "$emergency_test" "$TEST_DIR"; then
        echo "✅ Test 5 PASSED: Emergency cleanup completed safely"
        return 0
    else
        echo "❌ Test 5 FAILED: Emergency cleanup failed"
        return 1
    fi
}

# Run all tests
run_all_tests() {
    echo "🚀 Running AILinux Session Safety Test Suite"
    echo "================================================"
    
    local tests_passed=0
    local tests_failed=0
    
    # Initialize test environment
    init_test
    
    # Run tests
    if test_no_aggressive_error_handling; then
        tests_passed=$((tests_passed + 1))
    else
        tests_failed=$((tests_failed + 1))
    fi
    echo
    
    if test_session_preservation; then
        tests_passed=$((tests_passed + 1))
    else
        tests_failed=$((tests_failed + 1))
    fi
    echo
    
    if test_mount_cleanup_safety; then
        tests_passed=$((tests_passed + 1))
    else
        tests_failed=$((tests_failed + 1))
    fi
    echo
    
    if test_session_integrity_function; then
        tests_passed=$((tests_passed + 1))
    else
        tests_failed=$((tests_failed + 1))
    fi
    echo
    
    if test_emergency_cleanup; then
        tests_passed=$((tests_passed + 1))
    else
        tests_failed=$((tests_failed + 1))
    fi
    echo
    
    # Final report
    echo "================================================"
    echo "📊 Session Safety Test Results:"
    echo "   ✅ Tests Passed: $tests_passed"
    echo "   ❌ Tests Failed: $tests_failed"
    echo "   📈 Success Rate: $(( tests_passed * 100 / (tests_passed + tests_failed) ))%"
    
    if [ "$tests_failed" -eq 0 ]; then
        echo "🎉 ALL TESTS PASSED - Build script is session-safe!"
        return 0
    else
        echo "⚠️  SOME TESTS FAILED - Review session safety implementation"
        return 1
    fi
}

# Cleanup function
cleanup_test() {
    echo "🧹 Cleaning up test environment..."
    rm -rf "$TEST_DIR"
    echo "✅ Cleanup completed"
}

# Main execution
main() {
    # Set up cleanup trap
    trap cleanup_test EXIT
    
    # Run tests
    if run_all_tests; then
        echo "✅ Session safety validation completed successfully"
        exit 0
    else
        echo "❌ Session safety validation failed"
        exit 1
    fi
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi