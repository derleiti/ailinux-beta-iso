# AILinux Assets Directory

This directory contains branding and visual assets for the AILinux ISO build system.

## Files:

- `boot.png` - ISOLINUX boot menu background image (recommended: 640x480 PNG)
- Other branding assets as needed

## Boot Image Requirements:

For the boot.png file:
- Format: PNG
- Resolution: 640x480 pixels (recommended)
- Color depth: 8-bit indexed color for best compatibility
- File size: Keep under 1MB for fast loading

## Usage:

The boot.png file is automatically copied to the ISO during the build process if present in this directory.