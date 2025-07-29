#!/bin/bash
#
# NetworkManager Configuration Test Script
# Tests NetworkManager setup for live system
#

echo "🌐 NetworkManager Configuration Validation Test"
echo "=============================================="

# Test 1: Check NetworkManager package inclusion
echo "Test 1: Checking NetworkManager package inclusion..."
if grep -q "network-manager" /home/zombie/ailinux-iso/build_enhanced.sh; then
    echo "✅ PASS: NetworkManager packages included in build"
else
    echo "❌ FAIL: NetworkManager packages not found in build"
    exit 1
fi

# Test 2: Verify NetworkManager configuration function
echo ""
echo "Test 2: Checking NetworkManager configuration function..."
if grep -A 10 "configure_network_manager()" /home/zombie/ailinux-iso/build_enhanced.sh | grep -q "NetworkManager"; then
    echo "✅ PASS: NetworkManager configuration function found"
else
    echo "❌ FAIL: NetworkManager configuration function not found"
    exit 1
fi

# Test 3: Check service enablement
echo ""
echo "Test 3: Checking NetworkManager service enablement..."
if grep -q "systemctl enable NetworkManager" /home/zombie/ailinux-iso/build_enhanced.sh; then
    echo "✅ PASS: NetworkManager service enablement configured"
else
    echo "❌ FAIL: NetworkManager service enablement not configured"
    exit 1
fi

# Test 4: Verify NetworkManager.conf creation
echo ""
echo "Test 4: Checking NetworkManager.conf creation..."
if grep -A 5 "NetworkManager.conf" /home/zombie/ailinux-iso/build_enhanced.sh | grep -q "plugins=ifupdown,keyfile"; then
    echo "✅ PASS: NetworkManager.conf configuration found"
else
    echo "❌ FAIL: NetworkManager.conf configuration not found"
    exit 1
fi

# Test 5: Check wireless packages inclusion
echo ""
echo "Test 5: Checking wireless packages inclusion..."
if grep -q "wpasupplicant.*wireless-tools.*iw.*linux-firmware" /home/zombie/ailinux-iso/build_enhanced.sh; then
    echo "✅ PASS: Wireless packages included"
else
    echo "❌ FAIL: Wireless packages not found"
    exit 1
fi

# Test 6: Verify network interface management
echo ""
echo "Test 6: Checking network interface management..."
if grep -q "rm -f /etc/network/interfaces.d" /home/zombie/ailinux-iso/build_enhanced.sh; then
    echo "✅ PASS: Conflicting network configs removal configured"
else
    echo "❌ FAIL: Network interface management not configured"
    exit 1
fi

# Test 7: Check for temp NetworkManager.conf file
echo ""
echo "Test 7: Checking temp NetworkManager configuration file..."
if [ -f "/home/zombie/ailinux-iso/temp/NetworkManager.conf" ]; then
    echo "✅ PASS: Temp NetworkManager.conf exists"
    cat /home/zombie/ailinux-iso/temp/NetworkManager.conf
else
    echo "ℹ️  INFO: Temp NetworkManager.conf not yet created (normal if build not run)"
fi

echo ""
echo "🎉 NetworkManager Test Completed!"