#!/bin/bash
#
# KDE 6.3 Installation Module for AILinux Build Script
# Provides KDE 6.3 specific installation and configuration
#
# This module handles the installation and configuration of KDE Plasma 6.3
# desktop environment with AILinux-specific customizations.
#

# Global KDE installation configuration
declare -g KDE_VERSION="6.3"
declare -g KDE_INSTALL_MODE="full"  # Options: minimal, standard, full
declare -g KDE_CUSTOMIZATION_LEVEL="ailinux"  # Options: vanilla, ailinux, custom
declare -g KDE_INSTALLED_PACKAGES=()
declare -g KDE_CONFIG_FILES=()

# Initialize KDE installation system
init_kde_installation() {
    log_info "🎨 Initializing KDE 6.3 installation system..."
    
    # Detect system architecture and capabilities
    detect_system_capabilities
    
    # Set up KDE package repositories
    setup_kde_repositories
    
    # Configure installation mode
    configure_installation_mode
    
    # Set up KDE directories
    setup_kde_directories
    
    log_success "KDE 6.3 installation system initialized (mode: $KDE_INSTALL_MODE)"
}

# Detect system capabilities for KDE installation
detect_system_capabilities() {
    log_info "🔍 Detecting system capabilities for KDE installation..."
    
    # Check available memory
    local total_memory_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_memory_gb=$((total_memory_kb / 1024 / 1024))
    
    # Check available disk space
    local available_disk_gb=$(df --output=avail . | tail -1 | awk '{print int($1/1024/1024)}')
    
    # Adjust installation mode based on resources
    if [ "$total_memory_gb" -lt 2 ] || [ "$available_disk_gb" -lt 5 ]; then
        KDE_INSTALL_MODE="minimal"
        log_warn "⚠️  Limited resources detected - using minimal KDE installation"
    elif [ "$total_memory_gb" -lt 4 ] || [ "$available_disk_gb" -lt 10 ]; then
        KDE_INSTALL_MODE="standard"
        log_info "Standard resources detected - using standard KDE installation"
    else
        KDE_INSTALL_MODE="full"
        log_info "Sufficient resources detected - using full KDE installation"
    fi
    
    # Check graphics capabilities
    if lspci | grep -i vga | grep -i nvidia >/dev/null; then
        log_info "NVIDIA graphics detected"
        export KDE_GRAPHICS_TYPE="nvidia"
    elif lspci | grep -i vga | grep -i amd >/dev/null; then
        log_info "AMD graphics detected"
        export KDE_GRAPHICS_TYPE="amd"
    elif lspci | grep -i vga | grep -i intel >/dev/null; then
        log_info "Intel graphics detected"
        export KDE_GRAPHICS_TYPE="intel"
    else
        log_info "Generic graphics detected"
        export KDE_GRAPHICS_TYPE="generic"
    fi
}

# Set up KDE package repositories
setup_kde_repositories() {
    log_info "📦 Setting up KDE 6.3 package repositories..."
    
    # Add KDE neon repository for latest KDE packages
    local kde_repo_file="/tmp/kde-neon.list"
    
    cat > "$kde_repo_file" << EOF
# KDE neon repository for KDE 6.3
deb http://archive.neon.kde.org/user noble main
deb-src http://archive.neon.kde.org/user noble main
EOF
    
    # Add repository key
    if wget -qO- https://archive.neon.kde.org/public.key 2>/dev/null | gpg --dearmor > /tmp/kde-neon-keyring.gpg 2>/dev/null; then
        log_success "✅ KDE neon repository key downloaded"
    else
        log_warn "⚠️  Could not download KDE neon key, using system packages"
        rm -f "$kde_repo_file"
        return 0
    fi
    
    # Validate repository accessibility
    if wget -q --spider http://archive.neon.kde.org/user/dists/noble/Release 2>/dev/null; then
        log_success "✅ KDE neon repository accessible"
        export KDE_NEON_REPO_AVAILABLE=true
    else
        log_warn "⚠️  KDE neon repository not accessible, using system packages"
        rm -f "$kde_repo_file" /tmp/kde-neon-keyring.gpg
        export KDE_NEON_REPO_AVAILABLE=false
    fi
}

# Configure installation mode settings
configure_installation_mode() {
    log_info "⚙️  Configuring KDE installation mode: $KDE_INSTALL_MODE"
    
    case "$KDE_INSTALL_MODE" in
        "minimal")
            export KDE_CORE_PACKAGES="plasma-desktop plasma-workspace sddm kde-config-sddm"
            export KDE_OPTIONAL_PACKAGES=""
            export KDE_APPLICATIONS=""
            ;;
        "standard")
            export KDE_CORE_PACKAGES="plasma-desktop plasma-workspace plasma-nm plasma-pa sddm kde-config-sddm"
            export KDE_OPTIONAL_PACKAGES="dolphin konsole kate spectacle gwenview okular"
            export KDE_APPLICATIONS="firefox-esr libreoffice"
            ;;
        "full")
            export KDE_CORE_PACKAGES="kde-plasma-desktop plasma-workspace plasma-nm plasma-pa sddm kde-config-sddm"
            export KDE_OPTIONAL_PACKAGES="dolphin konsole kate spectacle gwenview okular ark filelight kcalc kcharselect kcolorchooser kdf"
            export KDE_APPLICATIONS="firefox-esr libreoffice krita kdenlive kmail kontact korganizer"
            ;;
    esac
    
    # Add AILinux-specific packages
    if [ "$KDE_CUSTOMIZATION_LEVEL" = "ailinux" ]; then
        export KDE_AILINUX_PACKAGES="ailinux-kde-theme ailinux-wallpapers ailinux-welcome"
    fi
}

# Set up KDE directories and structure
setup_kde_directories() {
    local chroot_dir="${AILINUX_BUILD_CHROOT_DIR:-/tmp/ailinux_chroot}"
    
    log_info "📁 Setting up KDE directories in chroot..."
    
    # Essential KDE directories
    local kde_dirs=(
        "/etc/skel/.config"
        "/etc/skel/.local/share"
        "/usr/share/sddm/themes"
        "/usr/share/plasma/shells"
        "/usr/share/plasma/plasmoids"
        "/usr/share/kde4/config"
        "/var/lib/sddm"
    )
    
    for dir in "${kde_dirs[@]}"; do
        if [ -d "$chroot_dir" ]; then
            safe_execute "mkdir -p '$chroot_dir$dir'" "create_kde_dir_$dir" "Failed to create KDE directory: $dir"
        fi
    done
}

# Install KDE base packages
install_kde_base() {
    local chroot_dir="${1:-$AILINUX_BUILD_CHROOT_DIR}"
    
    if [ ! -d "$chroot_dir" ]; then
        log_error "❌ Chroot directory not found: $chroot_dir"
        return 1
    fi
    
    log_info "📦 Installing KDE 6.3 base packages..."
    
    # Update package lists first
    enter_chroot_safely "$chroot_dir" "apt-get update" || {
        log_error "❌ Failed to update package lists in chroot"
        return 1
    }
    
    # Install core KDE packages
    local install_cmd="DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $KDE_CORE_PACKAGES"
    
    if ! enter_chroot_safely "$chroot_dir" "$install_cmd"; then
        log_error "❌ Failed to install KDE core packages"
        return 1
    fi
    
    log_success "✅ KDE core packages installed successfully"
    
    # Track installed packages
    for package in $KDE_CORE_PACKAGES; do
        KDE_INSTALLED_PACKAGES+=("$package")
    done
    
    # Install optional packages if specified
    if [ -n "$KDE_OPTIONAL_PACKAGES" ]; then
        log_info "📦 Installing KDE optional packages..."
        
        local optional_cmd="DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $KDE_OPTIONAL_PACKAGES"
        
        if enter_chroot_safely "$chroot_dir" "$optional_cmd"; then
            log_success "✅ KDE optional packages installed successfully"
            
            for package in $KDE_OPTIONAL_PACKAGES; do
                KDE_INSTALLED_PACKAGES+=("$package")
            done
        else
            log_warn "⚠️  Some KDE optional packages failed to install, continuing..."
        fi
    fi
    
    # Install applications if specified
    if [ -n "$KDE_APPLICATIONS" ]; then
        log_info "📦 Installing KDE applications..."
        
        local apps_cmd="DEBIAN_FRONTEND=noninteractive apt-get install -y $KDE_APPLICATIONS"
        
        if enter_chroot_safely "$chroot_dir" "$apps_cmd"; then
            log_success "✅ KDE applications installed successfully"
            
            for app in $KDE_APPLICATIONS; do
                KDE_INSTALLED_PACKAGES+=("$app")
            done
        else
            log_warn "⚠️  Some KDE applications failed to install, continuing..."
        fi
    fi
    
    # Clean up package cache
    enter_chroot_safely "$chroot_dir" "apt-get clean" || true
    
    log_success "🎨 KDE base installation completed"
}

# Configure KDE desktop settings
configure_kde_settings() {
    local chroot_dir="${1:-$AILINUX_BUILD_CHROOT_DIR}"
    
    if [ ! -d "$chroot_dir" ]; then
        log_error "❌ Chroot directory not found: $chroot_dir"
        return 1
    fi
    
    log_info "⚙️  Configuring KDE desktop settings..."
    
    # Configure SDDM display manager
    configure_sddm_settings "$chroot_dir"
    
    # Set up default KDE configuration
    setup_default_kde_config "$chroot_dir"
    
    # Configure Plasma desktop
    configure_plasma_desktop "$chroot_dir"
    
    # Apply AILinux customizations
    apply_ailinux_customizations "$chroot_dir"
    
    log_success "✅ KDE desktop settings configured"
}

# Configure SDDM display manager
configure_sddm_settings() {
    local chroot_dir="$1"
    
    log_info "🖥️  Configuring SDDM display manager..."
    
    # Create SDDM configuration
    local sddm_config="$chroot_dir/etc/sddm.conf"
    
    cat > "$sddm_config" << EOF
[Autologin]
# Automatic login settings
Relogin=false
Session=
User=

[General]
# General SDDM settings
HaltCommand=/usr/bin/systemctl poweroff
RebootCommand=/usr/bin/systemctl reboot
Numlock=none

[Theme]
# SDDM theme settings
Current=breeze
CursorTheme=breeze_cursors
Font=Noto Sans,10,-1,0,50,0,0,0,0,0

[Users]
# User settings
MaximumUid=60000
MinimumUid=1000
HideUsers=
HideShells=

[Wayland]
# Wayland session settings
SessionCommand=/usr/bin/sddm-helper --socket \$DISPLAY --id \$\$ --start \$DESKTOP_SESSION
SessionDir=/usr/share/wayland-sessions

[X11]
# X11 session settings
ServerPath=/usr/bin/X
ServerArguments=-nolisten tcp auth Required pam_service sddm-autologin
SessionCommand=/etc/sddm/Xsession
SessionDir=/usr/share/xsessions
XephyrPath=/usr/bin/Xephyr
EOF
    
    # Enable SDDM service
    enter_chroot_safely "$chroot_dir" "systemctl enable sddm" || {
        log_warn "⚠️  Could not enable SDDM service"
    }
    
    log_success "✅ SDDM configured"
}

# Set up default KDE configuration
setup_default_kde_config() {
    local chroot_dir="$1"
    
    log_info "🔧 Setting up default KDE configuration..."
    
    # Create default user configuration
    local skel_config="$chroot_dir/etc/skel/.config"
    
    # Plasma configuration
    mkdir -p "$skel_config"
    
    # Basic Plasma desktop configuration
    cat > "$skel_config/plasmarc" << EOF
[PlasmaViews][Panel 1]
alignment=132
panelVisibility=0

[PlasmaViews][Panel 1][Defaults]
thickness=44

[PlasmaViews][Panel 1][Horizontal1920]
thickness=44
EOF
    
    # Dolphin file manager configuration
    cat > "$skel_config/dolphinrc" << EOF
[General]
Version=200
ViewPropsTimestamp=2024,1,1,0,0,0
EOF
    
    # Kate text editor configuration
    cat > "$skel_config/katerc" << EOF
[General]
Config Revision=10
Days Meta Infos=30
Save Meta Infos=true
Show Full Path in Title=false
Show Menu Bar=true
Show Status Bar=true
Show Tab Bar=true
EOF
    
    # Konsole terminal configuration
    mkdir -p "$skel_config/konsole"
    cat > "$skel_config/konsole/konsolerc" << EOF
[Desktop Entry]
DefaultProfile=Profile 1.profile

[General]
ConfigVersion=1
EOF
    
    # Add configuration files to tracking
    KDE_CONFIG_FILES+=(
        "$skel_config/plasmarc"
        "$skel_config/dolphinrc"
        "$skel_config/katerc"
        "$skel_config/konsole/konsolerc"
    )
    
    log_success "✅ Default KDE configuration set up"
}

# Configure Plasma desktop environment
configure_plasma_desktop() {
    local chroot_dir="$1"
    
    log_info "🖥️  Configuring Plasma desktop environment..."
    
    # Set up Plasma shell configuration
    local plasma_config="$chroot_dir/etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc"
    
    cat > "$plasma_config" << EOF
[ActionPlugins][0]
RightButton;NoModifier=org.kde.contextmenu

[ActionPlugins][1]
RightButton;NoModifier=org.kde.contextmenu

[Containments][1]
activityId=
formfactor=0
immutability=1
lastScreen=0
location=0
plugin=org.kde.plasma.folder
wallpaperplugin=org.kde.image

[Containments][1][Wallpaper][org.kde.image][General]
Image=file:///usr/share/wallpapers/Next/contents/images/1920x1080.jpg
SlidePaths=/usr/share/wallpapers/

[Containments][2]
activityId=
formfactor=2
immutability=1
lastScreen=0
location=4
plugin=org.kde.panel

[Containments][2][Applets][3]
immutability=1
plugin=org.kde.plasma.kickoff

[Containments][2][Applets][4]
immutability=1
plugin=org.kde.plasma.pager

[Containments][2][Applets][5]
immutability=1
plugin=org.kde.plasma.systemtray

[Containments][2][Applets][6]
immutability=1
plugin=org.kde.plasma.digitalclock

[Containments][2][General]
alignment=132
length=1920
EOF
    
    # Set up KDE system settings
    local kde_globals="$chroot_dir/etc/skel/.config/kdeglobals"
    
    cat > "$kde_globals" << EOF
[ColorEffects:Disabled]
Color=56,56,56
ColorAmount=0
ColorEffect=0
ContrastAmount=0.65
ContrastEffect=1
IntensityAmount=0.1
IntensityEffect=2

[Colors:Button]
BackgroundAlternate=189,195,199
BackgroundNormal=239,240,241
DecorationFocus=61,174,233
DecorationHover=147,206,233
ForegroundActive=61,174,233
ForegroundInactive=127,140,141
ForegroundLink=41,128,185
ForegroundNegative=218,68,83
ForegroundNeutral=246,116,0
ForegroundNormal=35,38,39
ForegroundPositive=39,174,96
ForegroundVisited=127,140,141

[General]
ColorScheme=Breeze
Name=Breeze
shadeSortColumn=true

[Icons]
Theme=breeze

[KDE]
SingleClick=true

[WM]
activeBackground=71,80,87
activeBlend=255,255,255
activeForeground=255,255,255
inactiveBackground=239,240,241
inactiveBlend=75,71,67
inactiveForeground=189,195,199
EOF
    
    KDE_CONFIG_FILES+=("$plasma_config" "$kde_globals")
    
    log_success "✅ Plasma desktop configured"
}

# Apply AILinux-specific customizations
apply_ailinux_customizations() {
    local chroot_dir="$1"
    
    if [ "$KDE_CUSTOMIZATION_LEVEL" != "ailinux" ]; then
        log_info "Skipping AILinux customizations (level: $KDE_CUSTOMIZATION_LEVEL)"
        return 0
    fi
    
    log_info "🎨 Applying AILinux-specific KDE customizations..."
    
    # Set up AILinux wallpapers
    setup_ailinux_wallpapers "$chroot_dir"
    
    # Configure AILinux branding
    setup_ailinux_branding "$chroot_dir"
    
    # Set up AILinux welcome application
    setup_ailinux_welcome "$chroot_dir"
    
    # Configure AILinux menu customizations
    setup_ailinux_menu "$chroot_dir"
    
    log_success "✅ AILinux customizations applied"
}

# Set up AILinux wallpapers
setup_ailinux_wallpapers() {
    local chroot_dir="$1"
    
    log_info "🖼️  Setting up AILinux wallpapers..."
    
    local wallpaper_dir="$chroot_dir/usr/share/wallpapers/AILinux"
    mkdir -p "$wallpaper_dir/contents/images"
    
    # Create a simple AILinux wallpaper (placeholder)
    cat > "$wallpaper_dir/metadata.desktop" << EOF
[Desktop Entry]
Name=AILinux
X-KDE-PluginInfo-Author=AILinux Team
X-KDE-PluginInfo-Email=team@ailinux.org
X-KDE-PluginInfo-License=GPL
X-KDE-PluginInfo-Name=ailinux
X-KDE-PluginInfo-Version=1.0
EOF
    
    # Update Plasma configuration to use AILinux wallpaper
    local plasma_config="$chroot_dir/etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc"
    if [ -f "$plasma_config" ]; then
        sed -i 's|Image=file:///usr/share/wallpapers/Next/contents/images/1920x1080.jpg|Image=file:///usr/share/wallpapers/AILinux/contents/images/1920x1080.jpg|' "$plasma_config"
    fi
}

# Set up AILinux branding
setup_ailinux_branding() {
    local chroot_dir="$1"
    
    log_info "🏷️  Setting up AILinux branding..."
    
    # Create SDDM AILinux theme
    local sddm_theme_dir="$chroot_dir/usr/share/sddm/themes/ailinux"
    mkdir -p "$sddm_theme_dir"
    
    cat > "$sddm_theme_dir/theme.conf" << EOF
[General]
type=image
color=#1e3a8a
fontSize=24
background=background.jpg
logo=logo.png
EOF
    
    # Update SDDM configuration to use AILinux theme
    local sddm_config="$chroot_dir/etc/sddm.conf"
    if [ -f "$sddm_config" ]; then
        sed -i 's/Current=breeze/Current=ailinux/' "$sddm_config"
    fi
}

# Set up AILinux welcome application
setup_ailinux_welcome() {
    local chroot_dir="$1"
    
    log_info "👋 Setting up AILinux welcome application..."
    
    # Create welcome application desktop entry
    local welcome_desktop="$chroot_dir/etc/skel/.config/autostart/ailinux-welcome.desktop"
    mkdir -p "$(dirname "$welcome_desktop")"
    
    cat > "$welcome_desktop" << EOF
[Desktop Entry]
Name=AILinux Welcome
Comment=Welcome to AILinux
Exec=/opt/ailinux/welcome
Icon=system-help
Type=Application
Categories=System;
StartupNotify=true
X-GNOME-Autostart-enabled=true
X-KDE-autostart-after=panel
EOF
}

# Set up AILinux menu customizations
setup_ailinux_menu() {
    local chroot_dir="$1"
    
    log_info "📋 Setting up AILinux menu customizations..."
    
    # Create AILinux menu directory structure
    local menu_dir="$chroot_dir/etc/skel/.local/share/applications"
    mkdir -p "$menu_dir"
    
    # Create AILinux category
    cat > "$chroot_dir/etc/xdg/menus/applications-merged/ailinux.menu" << EOF
<!DOCTYPE Menu PUBLIC "-//freedesktop//DTD Menu 1.0//EN"
 "http://www.freedesktop.org/standards/menu-spec/1.0/menu.dtd">
<Menu>
  <Name>Applications</Name>
  <Menu>
    <Name>AILinux</Name>
    <Directory>ailinux.directory</Directory>
    <Include>
      <Category>AILinux</Category>
    </Include>
  </Menu>
</Menu>
EOF
    
    # Create directory entry
    cat > "$chroot_dir/usr/share/desktop-directories/ailinux.directory" << EOF
[Desktop Entry]
Version=1.0
Type=Directory
Name=AILinux
Comment=AILinux specific applications
Icon=computer
EOF
}

# Set up KDE themes
setup_kde_themes() {
    local chroot_dir="${1:-$AILINUX_BUILD_CHROOT_DIR}"
    
    log_info "🎨 Setting up KDE themes..."
    
    # Install additional themes if in full mode
    if [ "$KDE_INSTALL_MODE" = "full" ]; then
        local theme_packages="breeze-gtk-theme oxygen-icon-theme"
        
        local theme_cmd="DEBIAN_FRONTEND=noninteractive apt-get install -y $theme_packages"
        
        if enter_chroot_safely "$chroot_dir" "$theme_cmd"; then
            log_success "✅ Additional KDE themes installed"
        else
            log_warn "⚠️  Some KDE themes failed to install"
        fi
    fi
    
    # Apply default theme settings
    apply_default_theme_settings "$chroot_dir"
}

# Apply default theme settings
apply_default_theme_settings() {
    local chroot_dir="$1"
    
    # Set GTK theme for better integration
    local gtk_config="$chroot_dir/etc/skel/.config/gtk-3.0/settings.ini"
    mkdir -p "$(dirname "$gtk_config")"
    
    cat > "$gtk_config" << EOF
[Settings]
gtk-theme-name=Breeze
gtk-icon-theme-name=breeze
gtk-font-name=Noto Sans 10
gtk-cursor-theme-name=breeze_cursors
gtk-cursor-theme-size=24
gtk-toolbar-style=GTK_TOOLBAR_BOTH_HORIZ
gtk-toolbar-icon-size=GTK_ICON_SIZE_LARGE_TOOLBAR
gtk-button-images=0
gtk-menu-images=0
gtk-enable-event-sounds=1
gtk-enable-input-feedback-sounds=1
EOF
    
    KDE_CONFIG_FILES+=("$gtk_config")
}

# Validate KDE installation
validate_kde_install() {
    local chroot_dir="${1:-$AILINUX_BUILD_CHROOT_DIR}"
    
    log_info "🔍 Validating KDE installation..."
    
    local validation_errors=0
    
    # Check if essential KDE packages are installed
    for package in $KDE_CORE_PACKAGES; do
        if ! enter_chroot_safely "$chroot_dir" "dpkg -l $package" >/dev/null 2>&1; then
            log_error "❌ Essential KDE package not installed: $package"
            ((validation_errors++))
        fi
    done
    
    # Check if SDDM is configured
    if [ ! -f "$chroot_dir/etc/sddm.conf" ]; then
        log_error "❌ SDDM configuration file missing"
        ((validation_errors++))
    fi
    
    # Check if KDE configuration files exist
    local missing_configs=0
    for config_file in "${KDE_CONFIG_FILES[@]}"; do
        if [ ! -f "$config_file" ]; then
            log_warn "⚠️  KDE configuration file missing: $(basename "$config_file")"
            ((missing_configs++))
        fi
    done
    
    if [ $missing_configs -gt 0 ]; then
        log_warn "⚠️  $missing_configs KDE configuration files are missing"
    fi
    
    # Check if desktop session files exist
    if [ ! -d "$chroot_dir/usr/share/xsessions" ]; then
        log_error "❌ X sessions directory missing"
        ((validation_errors++))
    fi
    
    if [ $validation_errors -eq 0 ]; then
        log_success "✅ KDE installation validation passed"
        return 0
    else
        log_error "❌ KDE installation validation failed with $validation_errors errors"
        return 1
    fi
}

# Clean up KDE installation resources
cleanup_kde_installation() {
    log_info "🧹 Cleaning up KDE installation resources..."
    
    # Clean up temporary files
    rm -f /tmp/kde-neon.list /tmp/kde-neon-keyring.gpg
    
    # Generate installation report
    create_kde_installation_report
    
    log_success "KDE installation cleanup completed"
}

# Create KDE installation report
create_kde_installation_report() {
    local report_file="/tmp/ailinux_kde_installation_report_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "# AILinux KDE 6.3 Installation Report"
        echo "# Generated: $(date)"
        echo "# Installation Mode: $KDE_INSTALL_MODE"
        echo "# Customization Level: $KDE_CUSTOMIZATION_LEVEL"
        echo ""
        
        echo "== INSTALLED PACKAGES =="
        printf '%s\n' "${KDE_INSTALLED_PACKAGES[@]}"
        echo ""
        
        echo "== CONFIGURATION FILES =="
        printf '%s\n' "${KDE_CONFIG_FILES[@]}"
        echo ""
        
        echo "== SYSTEM CAPABILITIES =="
        echo "Graphics Type: $KDE_GRAPHICS_TYPE"
        echo "KDE Neon Repository: ${KDE_NEON_REPO_AVAILABLE:-false}"
        echo ""
        
    } > "$report_file"
    
    log_success "📄 KDE installation report created: $report_file"
    
    # Coordinate through swarm
    swarm_coordinate "kde_installation" "KDE 6.3 installation completed successfully" "success" "installation" || true
}

# Export functions for use in other modules
export -f init_kde_installation
export -f install_kde_base
export -f configure_kde_settings
export -f setup_kde_themes
export -f validate_kde_install
export -f cleanup_kde_installation