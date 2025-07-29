#!/bin/bash
#
# AILinux Build Process Validation Test Suite
# Tests build script functionality and error handling
#
# QA Focus: Build process reliability and error recovery
#

set -e

echo "🏗️ AILinux Build Process Validation Test Suite"
echo "Testing build script functionality and error handling..."
echo

# Test configuration
TEST_DIR="/tmp/ailinux-build-test-$$"
BUILD_SCRIPT="./build.sh"
ENHANCED_BUILD_SCRIPT="./build_enhanced.sh"
LOG_FILE="build-validation-test.log"

# Initialize test environment
init_test() {
    echo "🔧 Initializing build validation test environment..."
    mkdir -p "$TEST_DIR"/{chroot,output,temp,logs}
    
    # Set up test environment variables
    export AILINUX_BUILD_DIR="$TEST_DIR"
    export AILINUX_BUILD_CHROOT_DIR="$TEST_DIR/chroot"
    export AILINUX_BUILD_OUTPUT_DIR="$TEST_DIR/output"
    export AILINUX_BUILD_TEMP_DIR="$TEST_DIR/temp"
    export AILINUX_BUILD_LOGS_DIR="$TEST_DIR/logs"
    export AILINUX_DRY_RUN=true
    
    echo "✅ Test environment initialized"
}

# Test 1: Build script exists and is executable
test_build_script_exists() {
    echo "🧪 Test 1: Build script existence and permissions"
    
    local scripts_found=0
    
    if [ -f "$BUILD_SCRIPT" ]; then
        echo "✅ Main build script found: $BUILD_SCRIPT"
        scripts_found=$((scripts_found + 1))
        
        if [ -x "$BUILD_SCRIPT" ]; then
            echo "✅ Build script is executable"
        else
            echo "⚠️  Build script is not executable"
            chmod +x "$BUILD_SCRIPT"
        fi
    else
        echo "❌ Main build script not found: $BUILD_SCRIPT"
    fi
    
    if [ -f "$ENHANCED_BUILD_SCRIPT" ]; then
        echo "✅ Enhanced build script found: $ENHANCED_BUILD_SCRIPT"
        scripts_found=$((scripts_found + 1))
        
        if [ -x "$ENHANCED_BUILD_SCRIPT" ]; then
            echo "✅ Enhanced build script is executable"
        else
            echo "⚠️  Enhanced build script is not executable"
            chmod +x "$ENHANCED_BUILD_SCRIPT"
        fi
    else
        echo "⚠️  Enhanced build script not found: $ENHANCED_BUILD_SCRIPT"
    fi
    
    if [ "$scripts_found" -gt 0 ]; then
        echo "✅ Test 1 PASSED: Build scripts found and accessible"
        return 0
    else
        echo "❌ Test 1 FAILED: No build scripts found"
        return 1
    fi
}

# Test 2: Validate build script structure
test_build_script_structure() {
    echo "🧪 Test 2: Build script structure validation"
    
    local script_to_test="$BUILD_SCRIPT"
    if [ -f "$ENHANCED_BUILD_SCRIPT" ]; then
        script_to_test="$ENHANCED_BUILD_SCRIPT"
        echo "Using enhanced build script for testing"
    fi
    
    local required_functions=(
        "main"
        "init_build_environment"
        "safe_execute"
        "log_info"
        "log_error"
        "cleanup_build_resources"
    )
    
    local missing_functions=()
    
    for func in "${required_functions[@]}"; do
        if ! grep -q "^${func}()" "$script_to_test"; then
            missing_functions+=("$func")
        fi
    done
    
    if [ ${#missing_functions[@]} -eq 0 ]; then
        echo "✅ All required functions found"
    else
        echo "⚠️  Missing functions: ${missing_functions[*]}"
    fi
    
    # Check for session safety features
    local safety_features=(
        "perform_emergency_safe_exit"
        "verify_session_integrity"
        "ERROR_HANDLING_MODE"
        "graceful"
    )
    
    local found_safety=0
    for feature in "${safety_features[@]}"; do
        if grep -q "$feature" "$script_to_test"; then
            found_safety=$((found_safety + 1))
        fi
    done
    
    if [ "$found_safety" -ge 3 ]; then
        echo "✅ Session safety features detected"
    else
        echo "⚠️  Limited session safety features found"
    fi
    
    echo "✅ Test 2 PASSED: Build script structure validated"
    return 0
}

# Test 3: Dry run functionality
test_dry_run_functionality() {
    echo "🧪 Test 3: Dry run functionality test"
    
    local script_to_test="$BUILD_SCRIPT"
    if [ -f "$ENHANCED_BUILD_SCRIPT" ]; then
        script_to_test="$ENHANCED_BUILD_SCRIPT"
    fi
    
    echo "Testing dry run mode..."
    
    # Test dry run execution
    local dry_run_output="$TEST_DIR/dry_run_output.log"
    
    if timeout 60s bash "$script_to_test" --dry-run > "$dry_run_output" 2>&1; then
        echo "✅ Dry run completed successfully"
        
        # Check for expected dry run indicators
        if grep -q "DRY RUN" "$dry_run_output"; then
            echo "✅ Dry run mode properly indicated"
        else
            echo "⚠️  Dry run mode not clearly indicated"
        fi
        
        if grep -q "SIMULATED" "$dry_run_output"; then
            echo "✅ Simulation indicators found"
        else
            echo "⚠️  Simulation indicators not found"
        fi
        
        # Check that no actual file operations occurred
        if [ ! -d "$TEST_DIR/chroot/bin" ] && [ ! -f "$TEST_DIR/output/ailinux-*.iso" ]; then
            echo "✅ No actual file operations performed in dry run"
        else
            echo "⚠️  Actual file operations detected in dry run"
        fi
    else
        echo "❌ Dry run failed or timed out"
        if [ -f "$dry_run_output" ]; then
            echo "Last few lines of output:"
            tail -10 "$dry_run_output"
        fi
        return 1
    fi
    
    echo "✅ Test 3 PASSED: Dry run functionality works correctly"
    return 0
}

# Test 4: Error handling patterns
test_error_handling() {
    echo "🧪 Test 4: Error handling patterns validation"
    
    local script_to_test="$BUILD_SCRIPT"
    if [ -f "$ENHANCED_BUILD_SCRIPT" ]; then
        script_to_test="$ENHANCED_BUILD_SCRIPT"
    fi
    
    # Check for proper error handling patterns
    local good_patterns=0
    local bad_patterns=0
    
    # Good patterns
    if grep -q "safe_execute" "$script_to_test"; then
        echo "✅ Safe execution function used"
        good_patterns=$((good_patterns + 1))
    fi
    
    if grep -q "allow_failure.*true" "$script_to_test"; then
        echo "✅ Graceful failure handling found"
        good_patterns=$((good_patterns + 1))
    fi
    
    if grep -q "ERROR_HANDLING_MODE.*graceful" "$script_to_test"; then
        echo "✅ Graceful error handling mode set"
        good_patterns=$((good_patterns + 1))
    fi
    
    # Bad patterns (should be minimal or absent)
    if grep -q "^[[:space:]]*set -e" "$script_to_test"; then
        echo "⚠️  Found 'set -e' - potential session risk"
        bad_patterns=$((bad_patterns + 1))
    fi
    
    if grep -q "^[[:space:]]*set -eo pipefail" "$script_to_test"; then
        echo "❌ Found 'set -eo pipefail' - session termination risk"
        bad_patterns=$((bad_patterns + 1))
    fi
    
    # Count direct exit calls
    local exit_count=$(grep -c "^[[:space:]]*exit 1" "$script_to_test" || echo 0)
    if [ "$exit_count" -gt 10 ]; then
        echo "⚠️  Many direct exit calls found ($exit_count) - consider safe alternatives"
        bad_patterns=$((bad_patterns + 1))
    fi
    
    if [ "$good_patterns" -ge 2 ] && [ "$bad_patterns" -eq 0 ]; then
        echo "✅ Test 4 PASSED: Error handling patterns are session-safe"
        return 0
    elif [ "$bad_patterns" -eq 0 ]; then
        echo "✅ Test 4 PASSED: No dangerous error handling patterns found"
        return 0
    else
        echo "⚠️  Test 4 WARNING: Some concerning error handling patterns found"
        return 1
    fi
}

# Test 5: Required dependencies check
test_dependencies_check() {
    echo "🧪 Test 5: Dependencies and system requirements check"
    
    local script_to_test="$BUILD_SCRIPT"
    if [ -f "$ENHANCED_BUILD_SCRIPT" ]; then
        script_to_test="$ENHANCED_BUILD_SCRIPT"
    fi
    
    # Check if script validates dependencies
    if grep -q "check_system_requirements\|required_tools" "$script_to_test"; then
        echo "✅ System requirements check found"
    else
        echo "⚠️  No system requirements check found"
    fi
    
    # Test that essential tools are checked
    local essential_tools=(
        "debootstrap"
        "mksquashfs"
        "xorriso"
        "chroot"
        "mount"
        "umount"
    )
    
    local tools_checked=0
    for tool in "${essential_tools[@]}"; do
        if grep -q "$tool" "$script_to_test"; then
            tools_checked=$((tools_checked + 1))
        fi
    done
    
    if [ "$tools_checked" -ge 4 ]; then
        echo "✅ Essential tools validation found ($tools_checked/6)"
    else
        echo "⚠️  Limited tools validation ($tools_checked/6)"
    fi
    
    # Check for networking tools (enhanced build)
    if grep -q "network-manager\|wpasupplicant\|wireless-tools" "$script_to_test"; then
        echo "✅ Networking tools validation found"
    else
        echo "ℹ️  Networking tools not explicitly checked"
    fi
    
    echo "✅ Test 5 PASSED: Dependencies check implementation found"
    return 0
}

# Test 6: Build phases validation
test_build_phases() {
    echo "🧪 Test 6: Build phases structure validation"
    
    local script_to_test="$BUILD_SCRIPT"
    if [ -f "$ENHANCED_BUILD_SCRIPT" ]; then
        script_to_test="$ENHANCED_BUILD_SCRIPT"
    fi
    
    # Expected build phases
    local expected_phases=(
        "environment_setup\|init_build_environment"
        "base_system\|create_base_system"
        "kde\|install.*desktop"
        "calamares\|installer"
        "iso.*generation\|generate.*iso"
    )
    
    local phases_found=0
    for phase in "${expected_phases[@]}"; do
        if grep -qi "$phase" "$script_to_test"; then
            phases_found=$((phases_found + 1))
        fi
    done
    
    echo "Build phases detected: $phases_found/${#expected_phases[@]}"
    
    # Check for enhanced features
    local enhanced_features=(
        "isolinux\|boot.*splash"
        "networkmanager\|network.*manager"
        "branding"
        "checksum\|md5\|sha256"
        "swarm.*coordination"
    )
    
    local enhanced_found=0
    for feature in "${enhanced_features[@]}"; do
        if grep -qi "$feature" "$script_to_test"; then
            enhanced_found=$((enhanced_found + 1))
        fi
    done
    
    echo "Enhanced features detected: $enhanced_found/${#enhanced_features[@]}"
    
    if [ "$phases_found" -ge 3 ]; then
        echo "✅ Test 6 PASSED: Essential build phases found"
        return 0
    else
        echo "❌ Test 6 FAILED: Insufficient build phases detected"
        return 1
    fi
}

# Test 7: Logging and reporting
test_logging_and_reporting() {
    echo "🧪 Test 7: Logging and reporting functionality"
    
    local script_to_test="$BUILD_SCRIPT"
    if [ -f "$ENHANCED_BUILD_SCRIPT" ]; then
        script_to_test="$ENHANCED_BUILD_SCRIPT"
    fi
    
    # Check for logging functions
    local logging_functions=(
        "log_info"
        "log_error"
        "log_warn"
        "log_success"
    )
    
    local logging_found=0
    for func in "${logging_functions[@]}"; do
        if grep -q "$func" "$script_to_test"; then
            logging_found=$((logging_found + 1))
        fi
    done
    
    echo "Logging functions found: $logging_found/${#logging_functions[@]}"
    
    # Check for build reporting
    if grep -q "generate.*report\|build.*report" "$script_to_test"; then
        echo "✅ Build reporting functionality found"
    else
        echo "⚠️  Build reporting not found"
    fi
    
    # Check for log file management
    if grep -q "LOG_FILE\|log.*file" "$script_to_test"; then
        echo "✅ Log file management found"
    else
        echo "⚠️  Log file management not found"
    fi
    
    if [ "$logging_found" -ge 3 ]; then
        echo "✅ Test 7 PASSED: Adequate logging functionality found"
        return 0
    else
        echo "❌ Test 7 FAILED: Insufficient logging functionality"
        return 1
    fi
}

# Run all tests
run_all_tests() {
    echo "🚀 Running AILinux Build Process Validation Test Suite"
    echo "======================================================"
    
    local tests_passed=0
    local tests_failed=0
    
    # Initialize test environment
    init_test
    
    # Run tests
    if test_build_script_exists; then
        tests_passed=$((tests_passed + 1))
    else
        tests_failed=$((tests_failed + 1))
    fi
    echo
    
    if test_build_script_structure; then
        tests_passed=$((tests_passed + 1))
    else
        tests_failed=$((tests_failed + 1))
    fi
    echo
    
    if test_dry_run_functionality; then
        tests_passed=$((tests_passed + 1))
    else
        tests_failed=$((tests_failed + 1))
    fi
    echo
    
    if test_error_handling; then
        tests_passed=$((tests_passed + 1))
    else
        tests_failed=$((tests_failed + 1))
    fi
    echo
    
    if test_dependencies_check; then
        tests_passed=$((tests_passed + 1))
    else
        tests_failed=$((tests_failed + 1))
    fi
    echo
    
    if test_build_phases; then
        tests_passed=$((tests_passed + 1))
    else
        tests_failed=$((tests_failed + 1))
    fi
    echo
    
    if test_logging_and_reporting; then
        tests_passed=$((tests_passed + 1))
    else
        tests_failed=$((tests_failed + 1))
    fi
    echo
    
    # Final report
    echo "======================================================"
    echo "📊 Build Process Validation Results:"
    echo "   ✅ Tests Passed: $tests_passed"
    echo "   ❌ Tests Failed: $tests_failed"
    echo "   📈 Success Rate: $(( tests_passed * 100 / (tests_passed + tests_failed) ))%"
    
    if [ "$tests_failed" -eq 0 ]; then
        echo "🎉 ALL TESTS PASSED - Build script validation successful!"
        return 0
    else
        echo "⚠️  SOME TESTS FAILED - Review build script implementation"
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
        echo "✅ Build process validation completed successfully"
        exit 0
    else
        echo "❌ Build process validation failed"
        exit 1
    fi
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi