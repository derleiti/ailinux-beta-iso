#!/bin/bash
#
# Calamares Installer Validation Test Script
# Tests Calamares installer setup and branding
#

echo "🔧 Calamares Installer Validation Test"
echo "======================================"

# Test 1: Check Calamares installation function
echo "Test 1: Checking Calamares installation function..."
if grep -A 5 "install_calamares_installer()" /home/zombie/ailinux-iso/build_enhanced.sh | grep -q "calamares"; then
    echo "✅ PASS: Calamares installation function found"
else
    echo "❌ FAIL: Calamares installation function not found"
    exit 1
fi

# Test 2: Verify Calamares packages
echo ""
echo "Test 2: Checking Calamares packages..."
if grep -q "calamares qml-module-qtquick2" /home/zombie/ailinux-iso/build_enhanced.sh; then
    echo "✅ PASS: Calamares packages configured"
else
    echo "❌ FAIL: Calamares packages not configured"
    exit 1
fi

# Test 3: Check Calamares configuration
echo ""
echo "Test 3: Checking Calamares configuration..."
if grep -A 10 "configure_calamares_installer()" /home/zombie/ailinux-iso/build_enhanced.sh | grep -q "settings.conf"; then
    echo "✅ PASS: Calamares configuration function found"
else
    echo "❌ FAIL: Calamares configuration function not found"
    exit 1
fi

# Test 4: Verify branding setup
echo ""
echo "Test 4: Checking Calamares branding setup..."
if grep -A 10 "setup_calamares_branding()" /home/zombie/ailinux-iso/build_enhanced.sh | grep -q "branding.desc"; then
    echo "✅ PASS: Calamares branding setup found"
else
    echo "❌ FAIL: Calamares branding setup not found"
    exit 1
fi

# Test 5: Check AILinux branding configuration
echo ""
echo "Test 5: Checking AILinux branding configuration..."
if grep -A 20 "branding.desc" /home/zombie/ailinux-iso/build_enhanced.sh | grep -q "productName.*AILinux"; then
    echo "✅ PASS: AILinux branding configuration found"
else
    echo "❌ FAIL: AILinux branding configuration not found"
    exit 1
fi

# Test 6: Verify desktop entry creation
echo ""
echo "Test 6: Checking Calamares desktop entry..."
if grep -A 10 "calamares.desktop" /home/zombie/ailinux-iso/build_enhanced.sh | grep -q "Install AILinux"; then
    echo "✅ PASS: Calamares desktop entry configured"
else
    echo "❌ FAIL: Calamares desktop entry not configured"
    exit 1
fi

# Test 7: Check sequence configuration
echo ""
echo "Test 7: Checking Calamares sequence configuration..."
if grep -A 30 "sequence:" /home/zombie/ailinux-iso/build_enhanced.sh | grep -q "welcome" && grep -A 30 "sequence:" /home/zombie/ailinux-iso/build_enhanced.sh | grep -q "locale" && grep -A 30 "sequence:" /home/zombie/ailinux-iso/build_enhanced.sh | grep -q "keyboard"; then
    echo "✅ PASS: Calamares sequence configured"
else
    echo "❌ FAIL: Calamares sequence not configured"
    exit 1
fi

# Test 8: Check temp configuration files
echo ""
echo "Test 8: Checking temp configuration files..."
if [ -f "/home/zombie/ailinux-iso/temp/settings.conf" ]; then
    echo "✅ PASS: Temp settings.conf exists"
else
    echo "ℹ️  INFO: Temp settings.conf not yet created (normal if build not run)"
fi

if [ -f "/home/zombie/ailinux-iso/temp/branding.desc" ]; then
    echo "✅ PASS: Temp branding.desc exists"
else
    echo "ℹ️  INFO: Temp branding.desc not yet created (normal if build not run)"
fi

echo ""
echo "🎉 Calamares Validation Test Completed!"