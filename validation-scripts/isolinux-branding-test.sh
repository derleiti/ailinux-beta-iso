#!/bin/bash
#
# ISOLINUX Branding Test Script
# Tests the ISOLINUX boot splash integration
#

echo "🎨 ISOLINUX Branding Validation Test"
echo "==================================="

# Test 1: Check branding directory setup
echo "Test 1: Checking branding directory setup..."
if [ -d "/home/zombie/ailinux-iso/branding" ]; then
    echo "✅ PASS: Branding directory exists"
else
    echo "❌ FAIL: Branding directory not found"
    exit 1
fi

# Test 2: Check for boot.png file
echo ""
echo "Test 2: Checking for boot splash image..."
if [ -f "/home/zombie/ailinux-iso/branding/boot.png" ]; then
    echo "✅ PASS: Boot splash image (boot.png) found"
    ls -lh /home/zombie/ailinux-iso/branding/boot.png
else
    echo "⚠️  WARNING: Boot splash image (boot.png) not found - text menu will be used"
fi

# Test 3: Verify ISOLINUX configuration generation
echo ""
echo "Test 3: Checking ISOLINUX configuration function..."
if grep -A 20 "setup_isolinux_branding()" /home/zombie/ailinux-iso/build_enhanced.sh | grep -q "isolinux.cfg"; then
    echo "✅ PASS: ISOLINUX configuration generation found"
else
    echo "❌ FAIL: ISOLINUX configuration generation not found"
    exit 1
fi

# Test 4: Check ISOLINUX binary copying
echo ""
echo "Test 4: Checking ISOLINUX binary copying..."
if grep -q "isolinux.bin" /home/zombie/ailinux-iso/build_enhanced.sh; then
    echo "✅ PASS: ISOLINUX binary copying configured"
else
    echo "❌ FAIL: ISOLINUX binary copying not configured"
    exit 1
fi

# Test 5: Verify splash image integration
echo ""
echo "Test 5: Checking splash image integration..."
if grep -q "MENU BACKGROUND splash.png" /home/zombie/ailinux-iso/build_enhanced.sh; then
    echo "✅ PASS: Splash image integration configured"
else
    echo "❌ FAIL: Splash image integration not configured"
    exit 1
fi

# Test 6: Check if temp ISO directory has been created with ISOLINUX files
echo ""
echo "Test 6: Checking temp ISO directory structure..."
if [ -d "/home/zombie/ailinux-iso/temp/iso/isolinux" ]; then
    echo "✅ PASS: ISOLINUX directory structure exists"
    ls -la /home/zombie/ailinux-iso/temp/iso/isolinux/
else
    echo "ℹ️  INFO: ISOLINUX directory not yet created (normal if build not run)"
fi

echo ""
echo "🎉 ISOLINUX Branding Test Completed!"