#!/bin/bash
#
# AILinux Build System Comprehensive Test Script
# Tests all components of the AI-coordinated ISO build system
#

set -u
set +e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Logging
log_test() {
    local level="$1"
    local message="$2"
    case "$level" in
        "PASS")
            echo -e "${GREEN}✅ [PASS]${NC} $message"
            ((TESTS_PASSED++))
            ;;
        "FAIL")
            echo -e "${RED}❌ [FAIL]${NC} $message"
            ((TESTS_FAILED++))
            ;;
        "SKIP")
            echo -e "${YELLOW}⏭️  [SKIP]${NC} $message"
            ((TESTS_SKIPPED++))
            ;;
        "INFO")
            echo -e "${BLUE}ℹ️  [INFO]${NC} $message"
            ;;
    esac
}

# Test environment setup
test_environment_setup() {
    log_test "INFO" "Testing environment setup..."
    
    # Test if we're in the right directory
    if [[ ! -f "build.sh" ]]; then
        log_test "FAIL" "build.sh not found in current directory"
        return 1
    fi
    log_test "PASS" "build.sh found"
    
    # Test if create_ubuntu_base.sh exists
    if [[ ! -f "create_ubuntu_base.sh" ]]; then
        log_test "FAIL" "create_ubuntu_base.sh not found"
        return 1
    fi
    log_test "PASS" "create_ubuntu_base.sh found"
    
    # Test required directories
    local required_dirs=("modules" "scripts" "assets")
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            log_test "FAIL" "Required directory missing: $dir"
            return 1
        fi
        log_test "PASS" "Directory exists: $dir"
    done
    
    return 0
}

# Test required tools
test_required_tools() {
    log_test "INFO" "Testing required tools availability..."
    
    local required_tools=("debootstrap" "chroot" "mksquashfs" "xorriso" "isohybrid" "curl" "jq")
    local missing_tools=()
    
    for tool in "${required_tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            log_test "PASS" "Tool available: $tool"
        else
            missing_tools+=("$tool")
            log_test "FAIL" "Tool missing: $tool"
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_test "INFO" "Missing tools: ${missing_tools[*]}"
        return 1
    fi
    
    return 0
}

# Test script syntax
test_script_syntax() {
    log_test "INFO" "Testing script syntax..."
    
    local scripts=("build.sh" "create_ubuntu_base.sh" "scripts/validate-md5.sh" "modules/signal_handler.sh" "modules/ai_integrator_enhanced.sh")
    
    for script in "${scripts[@]}"; do
        if [[ -f "$script" ]]; then
            if bash -n "$script" 2>/dev/null; then
                log_test "PASS" "Syntax valid: $script"
            else
                log_test "FAIL" "Syntax error: $script"
                return 1
            fi
        else
            log_test "SKIP" "Script not found: $script"
        fi
    done
    
    return 0
}

# Test module loading
test_module_loading() {
    log_test "INFO" "Testing module loading..."
    
    # Test signal handler module
    if [[ -f "modules/signal_handler.sh" ]]; then
        if source "modules/signal_handler.sh" 2>/dev/null; then
            log_test "PASS" "Signal handler module loads successfully"
        else
            log_test "FAIL" "Signal handler module failed to load"
            return 1
        fi
    fi
    
    # Test AI integrator module
    if [[ -f "modules/ai_integrator_enhanced.sh" ]]; then
        if source "modules/ai_integrator_enhanced.sh" 2>/dev/null; then
            log_test "PASS" "AI integrator module loads successfully"
        else
            log_test "FAIL" "AI integrator module failed to load"
            return 1
        fi
    fi
    
    return 0
}

# Test MD5 validation script
test_md5_validation() {
    log_test "INFO" "Testing MD5 validation script..."
    
    if [[ -x "scripts/validate-md5.sh" ]]; then
        if "scripts/validate-md5.sh" test >/dev/null 2>&1; then
            log_test "PASS" "MD5 validation self-test passed"
        else
            log_test "FAIL" "MD5 validation self-test failed"
            return 1
        fi
    else
        log_test "SKIP" "MD5 validation script not executable"
    fi
    
    return 0
}

# Test Ubuntu base system creation (dry run)
test_ubuntu_base_creation() {
    log_test "INFO" "Testing Ubuntu base system creation (dry run)..."
    
    if [[ -x "create_ubuntu_base.sh" ]]; then
        if "./create_ubuntu_base.sh" --dry-run >/dev/null 2>&1; then
            log_test "PASS" "Ubuntu base system creation dry-run passed"
        else
            log_test "FAIL" "Ubuntu base system creation dry-run failed"
            return 1
        fi
    else
        log_test "FAIL" "create_ubuntu_base.sh not executable"
        return 1
    fi
    
    return 0
}

# Test build script initialization
test_build_script_init() {
    log_test "INFO" "Testing build script initialization..."
    
    # Test if build script can source its modules
    if bash -c 'source build.sh; echo "Build script sourced successfully"' >/dev/null 2>&1; then
        log_test "PASS" "Build script can be sourced"
    else
        log_test "FAIL" "Build script cannot be sourced"
        return 1
    fi
    
    return 0
}

# Test permissions
test_permissions() {
    log_test "INFO" "Testing file permissions..."
    
    local executable_files=("build.sh" "create_ubuntu_base.sh" "scripts/validate-md5.sh")
    
    for file in "${executable_files[@]}"; do
        if [[ -f "$file" ]]; then
            if [[ -x "$file" ]]; then
                log_test "PASS" "File is executable: $file"
            else
                log_test "FAIL" "File is not executable: $file"
                chmod +x "$file" 2>/dev/null && log_test "INFO" "Fixed permissions for: $file"
            fi
        fi
    done
    
    return 0
}

# Test configuration files
test_configuration() {
    log_test "INFO" "Testing configuration files..."
    
    # Test if .env example exists
    if [[ -f ".env.example" ]] || [[ -f ".env" ]]; then
        log_test "PASS" "Environment configuration available"
    else
        log_test "SKIP" "No environment configuration found"
    fi
    
    # Test if assets directory has required files
    if [[ -d "assets" ]]; then
        if [[ -n "$(ls -A assets/ 2>/dev/null)" ]]; then
            log_test "PASS" "Assets directory contains files"
        else
            log_test "SKIP" "Assets directory is empty"
        fi
    fi
    
    return 0
}

# Test system integration
test_system_integration() {
    log_test "INFO" "Testing system integration readiness..."
    
    # Check if we can create directories
    local test_dir="/tmp/ailinux-test-$$"
    if mkdir -p "$test_dir" 2>/dev/null; then
        rmdir "$test_dir" 2>/dev/null
        log_test "PASS" "Can create temporary directories"
    else
        log_test "FAIL" "Cannot create temporary directories"
        return 1
    fi
    
    # Check disk space (need at least 5GB for build)
    local available_space=$(df . | tail -1 | awk '{print $4}')
    if [[ $available_space -gt 5242880 ]]; then # 5GB in KB
        log_test "PASS" "Sufficient disk space available"
    else
        log_test "FAIL" "Insufficient disk space (need at least 5GB)"
        return 1
    fi
    
    return 0
}

# Main test execution
main() {
    echo "🧪 AILinux Build System Comprehensive Test Suite"
    echo "=============================================="
    echo
    
    # Run tests
    test_environment_setup || exit 1
    test_required_tools
    test_script_syntax || exit 1
    test_module_loading
    test_md5_validation
    test_ubuntu_base_creation || exit 1
    test_build_script_init
    test_permissions
    test_configuration
    test_system_integration
    
    # Final results
    echo
    echo "🏁 Test Results Summary"
    echo "======================"
    echo -e "✅ Passed:  ${GREEN}$TESTS_PASSED${NC}"
    echo -e "❌ Failed:  ${RED}$TESTS_FAILED${NC}"
    echo -e "⏭️  Skipped: ${YELLOW}$TESTS_SKIPPED${NC}"
    echo -e "📊 Total:   $(($TESTS_PASSED + $TESTS_FAILED + $TESTS_SKIPPED))"
    echo
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}🎉 All critical tests passed! Build system is ready.${NC}"
        return 0
    else
        echo -e "${RED}⚠️  Some tests failed. Please fix issues before building.${NC}"
        return 1
    fi
}

# Execute if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi