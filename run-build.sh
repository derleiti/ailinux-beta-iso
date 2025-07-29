#!/bin/bash
#
# AILinux Build Runner with Sudo Authentication
# This script handles sudo authentication and runs the build
#

set -e

echo "🚀 AILinux ISO Build Runner"
echo "This script will build the AILinux ISO and requires sudo privileges."
echo

# Test sudo access and cache credentials
echo "🔐 Authenticating sudo access..."
if ! sudo -v; then
    echo "❌ Sudo authentication failed. Please ensure you have sudo privileges."
    exit 1
fi

echo "✅ Sudo authentication successful"
echo

# Function to keep sudo alive during long builds
keep_sudo_alive() {
    while true; do
        sleep 60
        sudo -n true
        kill -0 "$$" || exit
    done 2>/dev/null &
}

# Start keep-alive process
keep_sudo_alive

echo "🏗️  Starting AILinux Enhanced ISO build..."
echo "Build will take 30-60 minutes depending on your system."
echo

# Run the actual build script
if ./build.sh; then
    echo
    echo "🎉 AILinux ISO build completed successfully!"
    echo
    
    # Show the generated ISO
    if [ -f "ailinux-*.iso" ]; then
        iso_file=$(ls -1 ailinux-*.iso | head -1)
        iso_size=$(du -h "$iso_file" | cut -f1)
        echo "📀 Generated ISO: $iso_file ($iso_size)"
        
        # Show checksum if available
        if [ -f "${iso_file}.sha256" ]; then
            echo "🔐 Checksum: ${iso_file}.sha256"
        fi
    fi
    
    echo
    echo "✅ Build completed successfully! You can now:"
    echo "   • Flash the ISO to a USB drive"
    echo "   • Use it in a virtual machine"
    echo "   • Verify the checksum"
    
else
    echo
    echo "❌ Build failed. Check the logs for details:"
    echo "   • Latest log: logs/build_$(date +%Y%m%d)*.log"
    echo "   • Error details in the log files"
    exit 1
fi