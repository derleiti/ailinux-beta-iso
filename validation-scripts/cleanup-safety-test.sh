#!/bin/bash
#
# Cleanup Safety Test Script
# Tests cleanup safety mechanisms and mount handling
#

echo "🧹 Cleanup Safety Validation Test"
echo "================================="

# Test 1: Check emergency cleanup function
echo "Test 1: Checking emergency cleanup function..."
if grep -A 20 "emergency_cleanup()" /home/zombie/ailinux-iso/build_enhanced.sh | grep -q "preserves user session"; then
    echo "✅ PASS: Emergency cleanup function with session preservation found"
else
    echo "❌ FAIL: Emergency cleanup function not found"
    exit 1
fi

# Test 2: Verify lazy unmount usage
echo ""
echo "Test 2: Checking lazy unmount usage..."
lazy_unmount_count=$(grep -c "umount -l" /home/zombie/ailinux-iso/build_enhanced.sh)
echo "Found $lazy_unmount_count uses of lazy unmount"
if [ "$lazy_unmount_count" -ge 5 ]; then
    echo "✅ PASS: Good usage of lazy unmount for safety"
else
    echo "⚠️  WARNING: Limited lazy unmount usage (expected 5+)"
fi

# Test 3: Check mount point cleanup order
echo ""
echo "Test 3: Checking mount point cleanup order..."
if grep -A 10 "mount_points=(" /home/zombie/ailinux-iso/build_enhanced.sh | grep -q "dev/pts.*dev.*proc.*sys.*run"; then
    echo "✅ PASS: Proper mount point cleanup order (deepest first)"
else
    echo "⚠️  WARNING: Mount point cleanup order may not be optimal"
fi

# Test 4: Verify process safety checks
echo ""
echo "Test 4: Checking process safety mechanisms..."
if grep -q "fuser" /home/zombie/ailinux-iso/build_enhanced.sh && grep -q "kill -TERM" /home/zombie/ailinux-iso/build_enhanced.sh; then
    echo "✅ PASS: Process safety checks found"
else
    echo "⚠️  WARNING: Process safety checks may be limited"
fi

# Test 5: Check session integrity verification during cleanup
echo ""
echo "Test 5: Checking session integrity verification during cleanup..."
if grep -A 5 "verify_session_integrity" /home/zombie/ailinux-iso/build_enhanced.sh | grep -q "cleanup"; then
    echo "✅ PASS: Session integrity verification during cleanup found"
else
    echo "⚠️  WARNING: Limited session integrity verification during cleanup"
fi

# Test 6: Verify safe cleanup resource handling
echo ""
echo "Test 6: Checking safe cleanup resource handling..."
if grep -q "AILINUX_SKIP_CLEANUP.*false" /home/zombie/ailinux-iso/build_enhanced.sh; then
    echo "✅ PASS: Safe cleanup resource handling configured"
else
    echo "❌ FAIL: Safe cleanup resource handling not configured"
    exit 1
fi

# Test 7: Check chroot directory safety
echo ""
echo "Test 7: Checking chroot directory safety..."
if grep -q "AILINUX_BUILD_AS_ROOT.*false.*rm -rf.*CHROOT_DIR" /home/zombie/ailinux-iso/build_enhanced.sh; then
    echo "✅ PASS: Chroot directory safety for non-root users configured"
else
    echo "⚠️  WARNING: Chroot directory safety check may be limited"
fi

# Test 8: Verify cleanup completion verification
echo ""
echo "Test 8: Checking cleanup completion verification..."
if grep -A 5 "Session integrity preserved during cleanup" /home/zombie/ailinux-iso/build_enhanced.sh; then
    echo "✅ PASS: Cleanup completion verification found"
else
    echo "❌ FAIL: Cleanup completion verification not found"
    exit 1
fi

echo ""
echo "🎉 Cleanup Safety Test Completed!"