#!/bin/bash
#
# MD5 Validation Test Script
# Tests MD5 checksum generation and validation
#

echo "🔐 MD5 Validation Test"
echo "====================="

# Test 1: Check MD5 checksum generation function
echo "Test 1: Checking MD5 checksum generation function..."
if grep -q "validate_and_checksum_iso" /home/zombie/ailinux-iso/build_enhanced.sh && grep -A 20 "validate_and_checksum_iso()" /home/zombie/ailinux-iso/build_enhanced.sh | grep -q "md5sum"; then
    echo "✅ PASS: MD5 checksum generation function found"
else
    echo "❌ FAIL: MD5 checksum generation function not found"
    exit 1
fi

# Test 2: Verify SHA256 checksum generation
echo ""
echo "Test 2: Checking SHA256 checksum generation..."
if grep -q "sha256sum.*ailinux-1.0-checksums.sha256" /home/zombie/ailinux-iso/build_enhanced.sh; then
    echo "✅ PASS: SHA256 checksum generation configured"
else
    echo "❌ FAIL: SHA256 checksum generation not configured"
    exit 1
fi

# Test 3: Check checksum file naming
echo ""
echo "Test 3: Checking checksum file naming..."
if grep -q "ailinux-1.0-checksums.md5" /home/zombie/ailinux-iso/build_enhanced.sh; then
    echo "✅ PASS: MD5 checksum file naming configured"
else
    echo "❌ FAIL: MD5 checksum file naming not configured"
    exit 1
fi

# Test 4: Verify ISO validation before checksum
echo ""
echo "Test 4: Checking ISO validation before checksum..."
if grep -A 5 "validate_and_checksum_iso" /home/zombie/ailinux-iso/build_enhanced.sh | grep -q "if.*not.*found"; then
    echo "✅ PASS: ISO validation before checksum found"
else
    echo "❌ FAIL: ISO validation before checksum not found"
    exit 1
fi

# Test 5: Check checksum display functionality
echo ""
echo "Test 5: Checking checksum display functionality..."
if grep -A 10 "ISO validation completed" /home/zombie/ailinux-iso/build_enhanced.sh | grep -q "MD5.*iso_md5"; then
    echo "✅ PASS: Checksum display functionality found"
else
    echo "❌ FAIL: Checksum display functionality not found"
    exit 1
fi

# Test 6: Check existing checksum files
echo ""
echo "Test 6: Checking for existing checksum files..."
if [ -f "/home/zombie/ailinux-iso/output/"*.md5 ]; then
    echo "✅ PASS: MD5 checksum files found in output directory"
    ls -la /home/zombie/ailinux-iso/output/*.md5
else
    echo "ℹ️  INFO: No MD5 checksum files found (normal if build not completed)"
fi

if [ -f "/home/zombie/ailinux-iso/output/"*.sha256 ]; then
    echo "✅ PASS: SHA256 checksum files found in output directory"
    ls -la /home/zombie/ailinux-iso/output/*.sha256
else
    echo "ℹ️  INFO: No SHA256 checksum files found (normal if build not completed)"
fi

# Test 7: Verify checksum generation in build report
echo ""
echo "Test 7: Checking checksum generation in build report..."
if grep -A 5 "MD5 checksum validation" /home/zombie/ailinux-iso/build_enhanced.sh | grep -q "generate_build_report"; then
    echo "✅ PASS: Checksum information included in build report"
else
    echo "❌ FAIL: Checksum information not included in build report"
    exit 1
fi

# Test 8: Check error handling for checksum generation
echo ""
echo "Test 8: Checking error handling for checksum generation..."
if grep -q "Failed to generate.*checksum" /home/zombie/ailinux-iso/build_enhanced.sh; then
    echo "✅ PASS: Error handling for checksum generation found"
else
    echo "⚠️  WARNING: Limited error handling for checksum generation"
fi

echo ""
echo "🎉 MD5 Validation Test Completed!"