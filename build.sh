#!/usr/bin/env bash
# ===================================================================
# AILINUX - ISO BUILD SCRIPT (v11.0 - Robustes Mount-Management)
# ===================================================================
# Lizenz: MIT
# Verbesserte Version mit sicherem Mount-Management
# ===================================================================

set -euo pipefail

# --- Farbdefinitionen für Logging ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- Konfigurationsvariablen ---
BUILD_DIR='AILINUX_BUILD'
DISTRO='noble'
ISO_LABEL='AILINUX-2404'
ISO_NAME='ailinux-24.04-amd64.iso'
LOG_FILE="ailinux-build-$(date +%Y%m%d-%H%M%S).log"
UBUNTU_MIRROR='http://archive.ubuntu.com/ubuntu'
SQUASHFS_LEVEL='-Xcompression-level 22'

# --- Mount-Status Tracking ---
declare -A MOUNTED_PATHS
MOUNT_LOCK_FILE="/tmp/ailinux-build-mounts-$$"

# --- Logging-Funktionen ---
log()  { echo -e "${GREEN}[INFO]    $(date '+%Y-%m-%d %H:%M:%S')${NC} | $*" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[WARNING] $(date '+%Y-%m-%d %H:%M:%S')${NC} | $*" | tee -a "$LOG_FILE"; }
debug() { echo -e "${BLUE}[DEBUG]   $(date '+%Y-%m-%d %H:%M:%S')${NC} | $*" | tee -a "$LOG_FILE"; }
error_exit() {
  echo -e "${RED}[ERROR]   $(date '+%Y-%m-%d %H:%M:%S')${NC} | $*" | tee -a "$LOG_FILE"
  safe_cleanup
  log "Build fehlgeschlagen. Siehe Log: $LOG_FILE"
  exit 1
}

# --- Sichere Mount-Funktionen ---
safe_mount() {
    local source="$1"
    local target="$2"
    local fstype="${3:-auto}"
    local options="${4:-}"
    
    debug "Versuche Mount: $source -> $target (Type: $fstype)"
    
    # Prüfe ob Ziel-Verzeichnis existiert
    if [[ ! -d "$target" ]]; then
        debug "Erstelle Mount-Punkt: $target"
        sudo mkdir -p "$target" || {
            warn "Konnte Mount-Punkt nicht erstellen: $target"
            return 1
        }
    fi
    
    # Prüfe ob bereits gemountet
    if mountpoint -q "$target" 2>/dev/null; then
        debug "Bereits gemountet: $target"
        MOUNTED_PATHS["$target"]=1
        return 0
    fi
    
    # Führe Mount aus
    local mount_cmd="sudo mount"
    [[ "$fstype" != "auto" ]] && mount_cmd+=" -t $fstype"
    [[ -n "$options" ]] && mount_cmd+=" -o $options"
    mount_cmd+=" '$source' '$target'"
    
    debug "Mount-Befehl: $mount_cmd"
    
    if eval "$mount_cmd"; then
        MOUNTED_PATHS["$target"]=1
        echo "$target" >> "$MOUNT_LOCK_FILE"
        log "✓ Erfolgreich gemountet: $target"
        return 0
    else
        warn "Mount fehlgeschlagen: $source -> $target"
        return 1
    fi
}

safe_umount() {
    local target="$1"
    local force="${2:-false}"
    
    debug "Versuche Umount: $target (Force: $force)"
    
    # Prüfe ob gemountet
    if ! mountpoint -q "$target" 2>/dev/null; then
        debug "Nicht gemountet: $target"
        unset MOUNTED_PATHS["$target"]
        return 0
    fi
    
    # Normale Umount-Versuche
    local attempts=0
    local max_attempts=5
    
    while [[ $attempts -lt $max_attempts ]]; do
        attempts=$((attempts + 1))
        debug "Umount-Versuch $attempts/$max_attempts für: $target"
        
        if sudo umount "$target" 2>/dev/null; then
            log "✓ Erfolgreich umounted: $target"
            unset MOUNTED_PATHS["$target"]
            return 0
        fi
        
        # Bei Fehlschlag: kurz warten und Prozesse prüfen
        if [[ $attempts -lt $max_attempts ]]; then
            debug "Umount fehlgeschlagen, warte 2 Sekunden..."
            sleep 2
            
            # Prüfe welche Prozesse das Mount verwenden (nur zur Info)
            if command -v lsof >/dev/null 2>&1; then
                debug "Prozesse die $target verwenden:"
                sudo lsof +D "$target" 2>/dev/null | head -5 || true
            fi
        fi
    done
    
    # Force Umount als letzte Option
    if [[ "$force" == "true" ]]; then
        warn "Verwende Force-Umount für: $target"
        if sudo umount -f "$target" 2>/dev/null || sudo umount -l "$target" 2>/dev/null; then
            log "✓ Force-Umount erfolgreich: $target"
            unset MOUNTED_PATHS["$target"]
            return 0
        fi
    fi
    
    warn "Umount fehlgeschlagen: $target"
    return 1
}

# --- Verbesserte Cleanup-Funktion ---
safe_cleanup() {
    log "Starte sicheren Cleanup..."
    
    # Stoppe alle chroot-Prozesse sanft
    cleanup_chroot_processes
    
    # Umounte alle registrierten Mounts in umgekehrter Reihenfolge
    cleanup_mounts
    
    # Entferne Build-Verzeichnis
    cleanup_build_directory
    
    # Cleanup Lock-File
    [[ -f "$MOUNT_LOCK_FILE" ]] && rm -f "$MOUNT_LOCK_FILE"
    
    log "Cleanup abgeschlossen"
}

cleanup_chroot_processes() {
    if [[ ! -d "$BUILD_DIR/chroot" ]]; then
        return 0
    fi
    
    debug "Prüfe auf aktive chroot-Prozesse..."
    
    # Finde Prozesse im chroot (ohne aggressive Terminierung)
    local chroot_pids=()
    if command -v lsof >/dev/null 2>&1; then
        while IFS= read -r pid; do
            [[ -n "$pid" && "$pid" != "PID" ]] && chroot_pids+=("$pid")
        done < <(sudo lsof +D "$BUILD_DIR/chroot" 2>/dev/null | awk 'NR>1 {print $2}' | sort -u || true)
    fi
    
    if [[ ${#chroot_pids[@]} -gt 0 ]]; then
        log "Gefunden ${#chroot_pids[@]} Prozesse im chroot, beende sanft..."
        
        # Sende SIGTERM
        for pid in "${chroot_pids[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                debug "Beende Prozess $pid (SIGTERM)"
                sudo kill -TERM "$pid" 2>/dev/null || true
            fi
        done
        
        sleep 3
        
        # Prüfe verbleibende Prozesse
        local remaining_pids=()
        for pid in "${chroot_pids[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                remaining_pids+=("$pid")
            fi
        done
        
        # SIGKILL für hartnäckige Prozesse
        if [[ ${#remaining_pids[@]} -gt 0 ]]; then
            warn "Beende ${#remaining_pids[@]} hartnäckige Prozesse mit SIGKILL..."
            for pid in "${remaining_pids[@]}"; do
                debug "Beende Prozess $pid (SIGKILL)"
                sudo kill -KILL "$pid" 2>/dev/null || true
            done
            sleep 1
        fi
    fi
}

cleanup_mounts() {
    debug "Bereinige Mounts..."
    
    # Lese Mount-Liste aus Lock-File (falls vorhanden)
    local mount_list=()
    if [[ -f "$MOUNT_LOCK_FILE" ]]; then
        while IFS= read -r mount_point; do
            [[ -n "$mount_point" ]] && mount_list+=("$mount_point")
        done < "$MOUNT_LOCK_FILE"
    fi
    
    # Füge bekannte Mounts hinzu
    for mount_point in "${!MOUNTED_PATHS[@]}"; do
        if [[ -n "$mount_point" ]]; then
            mount_list+=("$mount_point")
        fi
    done
    
    # Füge Standard-chroot-Mounts hinzu (falls vorhanden)
    if [[ -d "$BUILD_DIR/chroot" ]]; then
        for mount_suffix in "run" "sys" "proc" "dev/pts" "dev"; do
            local full_path="$BUILD_DIR/chroot/$mount_suffix"
            if mountpoint -q "$full_path" 2>/dev/null; then
                mount_list+=("$full_path")
            fi
        done
    fi
    
    # Entferne Duplikate und sortiere umgekehrt (längste Pfade zuerst)
    local unique_mounts=($(printf '%s\n' "${mount_list[@]}" | sort -u | sort -r))
    
    if [[ ${#unique_mounts[@]} -gt 0 ]]; then
        log "Umounte ${#unique_mounts[@]} Mount-Punkte..."
        
        # Erster Durchgang: sanfte Umounts
        for mount_point in "${unique_mounts[@]}"; do
            safe_umount "$mount_point" false
        done
        
        # Zweiter Durchgang: Force-Umounts für verbleibende
        for mount_point in "${unique_mounts[@]}"; do
            if mountpoint -q "$mount_point" 2>/dev/null; then
                safe_umount "$mount_point" true
            fi
        done
        
        # Finaler Check
        local remaining_mounts=()
        for mount_point in "${unique_mounts[@]}"; do
            if mountpoint -q "$mount_point" 2>/dev/null; then
                remaining_mounts+=("$mount_point")
            fi
        done
        
        if [[ ${#remaining_mounts[@]} -gt 0 ]]; then
            warn "Verbleibende Mounts: ${remaining_mounts[*]}"
        else
            log "✓ Alle Mounts erfolgreich entfernt"
        fi
    fi
}

cleanup_build_directory() {
    if [[ ! -d "$BUILD_DIR" ]]; then
        return 0
    fi
    
    debug "Entferne Build-Verzeichnis: $BUILD_DIR"
    
    # Prüfe auf verbleibende Mounts
    if mount | grep -q "$BUILD_DIR"; then
        warn "Verbleibende Mounts in $BUILD_DIR gefunden:"
        mount | grep "$BUILD_DIR" | while read -r line; do
            warn "  $line"
        done
        return 1
    fi
    
    # Entferne Verzeichnis
    if sudo rm -rf "$BUILD_DIR" 2>/dev/null; then
        log "✓ Build-Verzeichnis entfernt"
    else
        warn "Konnte Build-Verzeichnis nicht vollständig entfernen"
        # Fallback: Versuch mit find
        debug "Verwende find für Cleanup..."
        sudo find "$BUILD_DIR" -type f -delete 2>/dev/null || true
        sudo find "$BUILD_DIR" -depth -type d -delete 2>/dev/null || true
    fi
}

# --- Cleanup-Hilfsfunktion für externe Aufrufe ---
if [[ "${1:-}" == "--cleanup" ]]; then
    log "AILinux Emergency Cleanup gestartet"
    
    # Bereinige alle AILINUX_BUILD* Verzeichnisse
    for build_dir in AILINUX_BUILD*; do
        if [[ -d "$build_dir" ]]; then
            log "Bereinige: $build_dir"
            BUILD_DIR="$build_dir"
            safe_cleanup
        fi
    done
    
    # Bereinige verwaiste Lock-Files
    rm -f /tmp/ailinux-build-mounts-* 2>/dev/null || true
    
    log "Emergency Cleanup abgeschlossen"
    exit 0
fi

# Setze Trap für Cleanup
trap safe_cleanup EXIT
trap 'error_exit "FEHLER in Zeile $LINENO: Befehl \`$BASH_COMMAND\` schlug mit Status $? fehl."' ERR

# --- 1. Host-Vorbereitung ---
log "AILinux Build Script gestartet (Version 11.0 - Robustes Mount-Management)"

if [[ $(id -u) -eq 0 ]]; then
    error_exit "Bitte Skript nicht als root ausführen"
fi

# Initialer Cleanup
safe_cleanup || true

if [[ -f "$ISO_NAME" ]]; then
    ISO_NAME="ailinux-24.04-amd64-$(date +%Y%m%d-%H%M%S).iso"
    log "ISO existiert bereits. Neuer Name: $ISO_NAME"
fi

log "Installiere Host-Abhängigkeiten..."
sudo apt-get update
sudo apt-get install -y debootstrap squashfs-tools xorriso \
     grub-pc-bin grub-efi-amd64-bin shim-signed ovmf \
     mtools wget curl gnupg isolinux syslinux-common \
     dosfstools psmisc lsof

# --- 2. Build-Verzeichnis anlegen ---
log "Erstelle Verzeichnisstruktur..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/chroot" \
         "$BUILD_DIR/iso"/{casper,boot/grub,isolinux,EFI/boot,.disk}

# --- 3. Bootstrap Basissystem ---
log "Starte debootstrap Basissystem..."
sudo debootstrap --arch=amd64 --variant=minbase \
  --include=gpg,ubuntu-keyring,ca-certificates,wget,systemd \
  "$DISTRO" "$BUILD_DIR/chroot" "$UBUNTU_MIRROR"

# --- 4. Netzwerk und Service-Block im Chroot ---
log "Konfiguriere Netzwerk & blockiere Services im Chroot..."
sudo tee "$BUILD_DIR/chroot/etc/resolv.conf" <<EOF
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF
sudo cp /etc/hosts "$BUILD_DIR/chroot/etc/hosts"
sudo tee "$BUILD_DIR/chroot/usr/sbin/policy-rc.d" <<'EOF'
#!/bin/sh
exit 101
EOF
sudo chmod +x "$BUILD_DIR/chroot/usr/sbin/policy-rc.d"

# --- 5. chroot-Skript erzeugen ---
log "Erzeuge chroot-script.sh..."
sudo tee "$BUILD_DIR/chroot/chroot-script.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 LC_ALL=C.UTF-8 HOME=/root

info_chroot() { echo -e "\033[0;32m[CHROOT-INFO]\033[0m | $*"; }

# --- Hilfsfunktion für sichere Paketinstallation ---
safe_install() {
    local packages="$*"
    info_chroot "Versuche Installation: $packages"
    if apt-get install -y $packages; then
        info_chroot "✓ Erfolgreich installiert: $packages"
        return 0
    else
        info_chroot "✗ Installation fehlgeschlagen: $packages"
        return 1
    fi
}

# --- Chroot Phase 1: Umgebung stabilisieren ---
pre_setup_chroot() {
    info_chroot "Phase 1: Stabilisiere Chroot-Umgebung..."
    apt-get update
    
    # Installiere essentielle Pakete
    apt-get install -y apt-utils locales
    
    # Versuche dialog zu installieren (optional)
    safe_install dialog || info_chroot "WARNUNG: dialog Paket nicht verfügbar - überspringe"
    
    echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
    echo "de_DE.UTF-8 UTF-8" >> /etc/locale.gen
    locale-gen
    dpkg --configure -a
}

# --- Chroot Phase 2: Repositories einrichten ---
setup_repositories() {
    info_chroot "Phase 2: Richte Repositories ein..."
    
    # Stelle sicher, dass curl und wget verfügbar sind
    apt-get install -y curl gnupg software-properties-common wget

    # AILinux Branding setzen
    info_chroot "🧫 Setze AILinux Branding..."
    tee /etc/os-release <<OSEOF
NAME="AILinux"
VERSION="24.04 LTS (Nova Edition)"
ID=ailinux
ID_LIKE="ubuntu debian"
VERSION_ID="24.04"
UBUNTU_CODENAME=noble
PRETTY_NAME="AILinux 24.04 LTS (based on Ubuntu)"
HOME_URL="https://www.ailinux.me/"
SUPPORT_URL="https://www.ailinux.me/"
BUG_REPORT_URL="https://www.ailinux.me/"
PRIVACY_POLICY_URL="https://www.ailinux.me/"
LOGO=ailinux-logo
OSEOF

    tee /etc/lsb-release <<LSBEOF
DISTRIB_ID=AILinux
DISTRIB_RELEASE=24.04
DISTRIB_CODENAME=noble
DISTRIB_DESCRIPTION="AILinux 24.04 LTS (Nova Edition)"
LSBEOF

    # Repository-Konfiguration
    local MIRROR_URL="https://ailinux.me:8443/mirror"
    local KEYRING_DIR="/etc/apt/keyrings"
    mkdir -p "${KEYRING_DIR}"
    
    local AILINUX_KEY="$KEYRING_DIR/ailinux.gpg"
    local CHROME_KEY="$KEYRING_DIR/google-chrome.gpg"
    local WINE_KEY="$KEYRING_DIR/winehq-archive.key"

    info_chroot "🔑 Lade GPG-Keys..."
    
    # AILinux Key
    if curl -fsSL "$MIRROR_URL/ailinux.gpg" | gpg --yes --dearmor -o "$AILINUX_KEY"; then
        info_chroot "✓ AILinux GPG-Key erfolgreich geladen"
    else
        info_chroot "WARNUNG: AILinux GPG-Key konnte nicht geladen werden"
    fi
    
    # Google Chrome Key
    if curl -fsSL "https://dl.google.com/linux/linux_signing_key.pub" | gpg --yes --dearmor -o "$CHROME_KEY"; then
        info_chroot "✓ Google Chrome GPG-Key erfolgreich geladen"
    else
        info_chroot "WARNUNG: Google Chrome GPG-Key konnte nicht geladen werden"
    fi
    
    # Wine Key
    if wget -qO "$WINE_KEY" https://dl.winehq.org/wine-builds/winehq.key; then
        info_chroot "✓ Wine GPG-Key erfolgreich geladen"
    else
        info_chroot "WARNUNG: Wine GPG-Key konnte nicht geladen werden"
    fi

    # Alte Listen entfernen
    rm -f /etc/apt/sources.list.d/*.list /etc/apt/sources.list

    info_chroot "📦 Schreibe AILinux Mirror Sources..."
    if [ -f "$AILINUX_KEY" ]; then
        tee /etc/apt/sources.list.d/ailinux.sources <<AILINUXEOF
Types: deb
URIs: $MIRROR_URL/archive.ubuntu.com/ubuntu
Suites: noble noble-updates noble-security
Components: main universe multiverse restricted
Signed-By: $AILINUX_KEY

Types: deb
URIs: $MIRROR_URL/archive.ailinux.me
Suites: stable
Components: main
Signed-By: $AILINUX_KEY
AILINUXEOF
        info_chroot "✓ AILinux Repository konfiguriert"
    else
        # Fallback auf Standard Ubuntu Repository
        tee /etc/apt/sources.list.d/ubuntu.sources <<UBUNTUEOF
Types: deb
URIs: http://archive.ubuntu.com/ubuntu
Suites: noble noble-updates noble-security
Components: main restricted universe multiverse
UBUNTUEOF
        info_chroot "WARNUNG: Fallback auf Standard Ubuntu Repository"
    fi

    info_chroot "📦 Schreibe externe Sources..."
    
    # Google Chrome Repository
    if [ -f "$CHROME_KEY" ]; then
        tee /etc/apt/sources.list.d/google-chrome.sources <<CHROMEEOF
Types: deb
URIs: https://dl.google.com/linux/chrome/deb/
Suites: stable
Components: main
Architectures: amd64
Signed-By: $CHROME_KEY
CHROMEEOF
    fi

    # WineHQ Repository
    if [ -f "$WINE_KEY" ]; then
        wget -qNP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/ubuntu/dists/noble/winehq-noble.sources || info_chroot "WARNUNG: WineHQ sources konnte nicht geladen werden"
    fi

    info_chroot "🏐 Aktiviere i386 Architektur..."
    if ! dpkg --print-foreign-architectures | grep -q i386; then
        dpkg --add-architecture i386
        info_chroot "✓ i386 Architektur hinzugefügt"
    else
        info_chroot "✓ i386 Architektur bereits aktiv"
    fi

    info_chroot "🔄 apt cleanup & update..."
    apt-get clean
    apt-get update || {
        info_chroot "WARNUNG: Repository-Update fehlgeschlagen - fahre trotzdem fort"
    }
    
    info_chroot "✅ AILinux Repos & Branding vollständig gesetzt!"
}

# --- Chroot Phase 3: Pakete installieren ---
install_packages() {
    info_chroot "Phase 3: Installiere Pakete..."
    
    # Basis-Pakete (müssen installiert werden)
    apt-get install -y \
        ubuntu-standard linux-image-generic linux-headers-generic \
        linux-firmware casper network-manager systemd-sysv

    # Desktop-Umgebung
    apt-get install -y \
        sddm sddm-theme-breeze plymouth plymouth-themes \
        kde-plasma-desktop plasma-nm konsole dolphin kate

    # Anwendungen (mit Fehlerbehandlung)
    safe_install firefox || info_chroot "Firefox nicht verfügbar"
    safe_install thunderbird || info_chroot "Thunderbird nicht verfügbar"
    safe_install vlc || info_chroot "VLC nicht verfügbar"
    
    # LibreOffice mit Fallback-Strategie
    if ! safe_install libreoffice libreoffice-l10n-de; then
        safe_install libreoffice-core libreoffice-writer libreoffice-calc || info_chroot "LibreOffice nicht verfügbar"
    fi
    
    safe_install gimp || info_chroot "GIMP nicht verfügbar"
    safe_install inkscape || info_chroot "Inkscape nicht verfügbar"
    
    # Optionale Pakete
    safe_install google-chrome-stable || info_chroot "Google Chrome nicht verfügbar"
    safe_install winehq-staging || info_chroot "Wine nicht verfügbar"
    safe_install steam-installer || info_chroot "Steam nicht verfügbar"
    
    # AILinux spezifische Pakete (falls verfügbar)
    info_chroot "Prüfe AILinux spezifische Pakete..."
    safe_install ailinux-app || info_chroot "AILinux App nicht verfügbar"
    safe_install ailinux-tools || info_chroot "AILinux Tools nicht verfügbar"
    safe_install ailinux-themes || info_chroot "AILinux Themes nicht verfügbar"
    
    # Installer
    safe_install calamares || info_chroot "Calamares nicht verfügbar - versuche Alternative"
    if ! dpkg -l calamares >/dev/null 2>&1; then
        safe_install ubiquity || info_chroot "Kein Installer verfügbar"
    fi
}

# --- Chroot Phase 4: System konfigurieren ---
configure_system() {
    info_chroot "Phase 4: Konfiguriere System..."
    
    # Benutzer erstellen
    useradd -m -s /bin/bash -G sudo,adm,cdrom,dip,plugdev,lpadmin ailinux || true
    echo "ailinux:ailinux" | chpasswd
    echo "ailinux ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/99-live-user
    chmod 0440 /etc/sudoers.d/99-live-user

    # Hostname
    echo "ailinux" > /etc/hostname
    echo "127.0.1.1 ailinux" >> /etc/hosts

    # SDDM Autologin
    mkdir -p /etc/sddm.conf.d
    tee /etc/sddm.conf.d/autologin.conf <<SDDMEOF
[Autologin]
User=ailinux
Session=plasmax11.desktop
SDDMEOF

    # Services aktivieren
    systemctl enable sddm || true
    systemctl enable NetworkManager || true

    # Desktop-Icon für Installer (falls vorhanden)
    if command -v calamares >/dev/null 2>&1 || command -v ubiquity >/dev/null 2>&1; then
        configure_installer
    fi
}

# --- Installer konfigurieren ---
configure_installer() {
    info_chroot "Konfiguriere Installer..."
    
    local DESKTOP_DIR="/home/ailinux/Desktop"
    mkdir -p "${DESKTOP_DIR}"
    
    if command -v calamares >/dev/null 2>&1; then
        # Calamares Konfiguration
        tee /usr/local/bin/calamares-wrapper <<WRAPPEREOF
#!/bin/bash
export DISPLAY="\${DISPLAY:-:0}"
export HOME="\${HOME:-/root}"
if [ -z "\$XDG_RUNTIME_DIR" ]; then
    export XDG_RUNTIME_DIR="/run/user/\$(id -u)"
fi
exec /usr/bin/calamares "\$@"
WRAPPEREOF
        chmod +x /usr/local/bin/calamares-wrapper

        tee "${DESKTOP_DIR}/install-ailinux.desktop" <<DESKTOPEOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Install AILinux 24.04 LTS
Exec=pkexec /usr/local/bin/calamares-wrapper
Icon=calamares
Terminal=false
Categories=System;
DESKTOPEOF
    elif command -v ubiquity >/dev/null 2>&1; then
        # Ubiquity als Fallback
        tee "${DESKTOP_DIR}/install-ailinux.desktop" <<DESKTOPEOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Install AILinux 24.04 LTS
Exec=ubiquity
Icon=ubiquity
Terminal=false
Categories=System;
DESKTOPEOF
    fi
    
    chmod +x "${DESKTOP_DIR}/install-ailinux.desktop"
    chown -R ailinux:ailinux /home/ailinux
}

# --- Chroot Phase 5: Bereinigung ---
cleanup_chroot() {
    info_chroot "Phase 5: Führe Bereinigung durch..."
    apt-get autoremove -y --purge
    apt-get clean
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
    rm -f /usr/sbin/policy-rc.d
    rm -f /chroot-script.sh
    find /var/log -type f -exec truncate -s 0 {} \; || true
}

# --- Main Chroot Logic ---
main() {
    pre_setup_chroot
    setup_repositories
    install_packages
    configure_system
    cleanup_chroot
}

main
EOF
sudo chmod +x "$BUILD_DIR/chroot/chroot-script.sh"

# --- 6. Sichere Chroot-Ausführung ---
log "Starte sichere Chroot-Ausführung..."

# Stelle sicher, dass Mount-Punkte existieren
sudo mkdir -p "$BUILD_DIR/chroot"/{dev,dev/pts,proc,sys,run}

# Mount Pseudo-FS mit verbesserter Fehlerbehandlung
log "Mounte Pseudo-Dateisysteme..."

if safe_mount "/dev" "$BUILD_DIR/chroot/dev" "auto" "bind"; then
    if safe_mount "/dev/pts" "$BUILD_DIR/chroot/dev/pts" "auto" "bind"; then
        log "✓ /dev und /dev/pts erfolgreich gemountet"
    else
        warn "/dev/pts Mount fehlgeschlagen"
    fi
else
    error_exit "/dev Mount fehlgeschlagen"
fi

if safe_mount "none" "$BUILD_DIR/chroot/proc" "proc"; then
    log "✓ /proc erfolgreich gemountet"
else
    error_exit "/proc Mount fehlgeschlagen"
fi

if safe_mount "none" "$BUILD_DIR/chroot/run" "tmpfs"; then
    log "✓ /run erfolgreich gemountet"
else
    warn "/run Mount fehlgeschlagen - fahre ohne fort"
fi

# /sys wird übersprungen wegen Problemen mit schreibgeschützten Dateien
log "Überspringe /sys Mount (vermeidet Probleme mit schreibgeschützten Dateien)"

# Chroot ausführen
log "Führe Chroot-Skript aus..."
if ! sudo chroot "$BUILD_DIR/chroot" /chroot-script.sh 2>&1 | tee -a "$LOG_FILE"; then
    error_exit "Chroot-Ausführung fehlgeschlagen"
fi

# --- 7. Post-Chroot Cleanup ---
log "Post-Chroot Cleanup..."

# Sanfte Umount aller Pseudo-FS
cleanup_mounts

# --- 8. ISO vorbereiten ---
log "Bereite ISO-Verzeichnis vor..."

# Kernel-Version ermitteln
KVER=$(ls "$BUILD_DIR/chroot/boot/vmlinuz-"* 2>/dev/null | sed 's|.*/vmlinuz-||' | sort -V | tail -n1 || true)
if [[ -z "$KVER" ]]; then 
    error_exit "Kein Kernel im Chroot gefunden"
fi
log "Kernel-Version: $KVER"

# Kernel und Initrd kopieren
sudo cp "$BUILD_DIR/chroot/boot/vmlinuz-$KVER" "$BUILD_DIR/iso/casper/vmlinuz"
sudo cp "$BUILD_DIR/chroot/boot/initrd.img-$KVER" "$BUILD_DIR/iso/casper/initrd"

log "Erstelle SquashFS..."
sudo mksquashfs "$BUILD_DIR/chroot" "$BUILD_DIR/iso/casper/filesystem.squashfs" \
  -e boot -noappend -no-exports -no-recovery -no-fragments -no-duplicates \
  -b 1M -comp zstd $SQUASHFS_LEVEL -processors "$(nproc)"

log "Erstelle Manifest & Metadaten..."
sudo chroot "$BUILD_DIR/chroot" dpkg-query -W --showformat='${Package}\t${Version}\n' \
  | sudo tee "$BUILD_DIR/iso/casper/filesystem.manifest"
sudo du -sx --block-size=1 "$BUILD_DIR/chroot" | cut -f1 \
  | sudo tee "$BUILD_DIR/iso/casper/filesystem.size"
echo "AILinux 24.04 LTS – Release $(date +%Y%m%d)" \
  | sudo tee "$BUILD_DIR/iso/.disk/info"

# --- 9. Bootloader konfigurieren ---
log "Konfiguriere Bootloader (BIOS & UEFI)..."

# ISOLINUX für BIOS-Boot
sudo cp /usr/lib/ISOLINUX/isolinux.bin "$BUILD_DIR/iso/isolinux/"
sudo cp /usr/lib/syslinux/modules/bios/*.c32 "$BUILD_DIR/iso/isolinux/"
sudo tee "$BUILD_DIR/iso/isolinux/isolinux.cfg" <<CFG
DEFAULT vesamenu.c32
TIMEOUT 50
MENU TITLE AILinux 24.04 LTS
LABEL live
  MENU LABEL ^Start or Install AILinux 24.04 LTS
  KERNEL /casper/vmlinuz
  APPEND initrd=/casper/initrd boot=casper quiet splash ---
CFG

# GRUB für UEFI-Boot
sudo tee "$BUILD_DIR/iso/boot/grub/grub.cfg" <<CFG
set default=0
set timeout=5
menuentry "Start or Install AILinux 24.04 LTS" {
  linux /casper/vmlinuz boot=casper quiet splash ---
  initrd /casper/initrd
}
CFG

# EFI Boot-Image erstellen
log "Erstelle EFI Boot-Image..."
EFI_IMG="$BUILD_DIR/iso/boot/grub/efi.img"
sudo dd if=/dev/zero of="$EFI_IMG" bs=1M count=10
sudo mkfs.fat -F 12 -n "EFIBOOT" "$EFI_IMG"

# EFI-Verzeichnis mounten und konfigurieren
EFI_MOUNT=$(mktemp -d)
sudo mount -o loop "$EFI_IMG" "$EFI_MOUNT"

sudo mkdir -p "$EFI_MOUNT/EFI/boot"

# UEFI-Binaries kopieren
if [[ -f "$BUILD_DIR/chroot/usr/lib/shim/shimx64.efi.signed" ]]; then
    sudo cp "$BUILD_DIR/chroot/usr/lib/shim/shimx64.efi.signed" "$EFI_MOUNT/EFI/boot/bootx64.efi"
    sudo cp "$EFI_MOUNT/EFI/boot/bootx64.efi" "$BUILD_DIR/iso/EFI/boot/" || true
fi

if [[ -f "$BUILD_DIR/chroot/usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed" ]]; then
    sudo cp "$BUILD_DIR/chroot/usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed" "$EFI_MOUNT/EFI/boot/grubx64.efi"
    sudo cp "$EFI_MOUNT/EFI/boot/grubx64.efi" "$BUILD_DIR/iso/EFI/boot/" || true
fi

# GRUB-Konfiguration ins EFI-Image
sudo cp "$BUILD_DIR/iso/boot/grub/grub.cfg" "$EFI_MOUNT/EFI/boot/"

sudo umount "$EFI_MOUNT"
rmdir "$EFI_MOUNT"

# --- 10. Finale ISO erstellen ---
log "Erstelle finale ISO: $ISO_NAME"
MBR_TEMPLATE="/usr/lib/ISOLINUX/isohdpfx.bin"
if [[ ! -f "$MBR_TEMPLATE" ]]; then 
    MBR_TEMPLATE="/usr/lib/syslinux/mbr/isohdpfx.bin"
fi
if [[ ! -f "$MBR_TEMPLATE" ]]; then 
    error_exit "Kein MBR Template (isohdpfx.bin) gefunden"
fi

sudo xorriso -as mkisofs \
  -r -V "$ISO_LABEL" -o "$ISO_NAME" \
  -J -joliet-long -l \
  -isohybrid-mbr "$MBR_TEMPLATE" \
  -c isolinux/boot.cat -b isolinux/isolinux.bin \
  -no-emul-boot -boot-load-size 4 -boot-info-table \
  -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot -isohybrid-gpt-basdat \
  "$BUILD_DIR/iso" 2>&1 | tee -a "$LOG_FILE"

# --- 11. Abschluss ---
log "✅ AILinux ISO $ISO_NAME erfolgreich erstellt!"
log "Dateigröße: $(du -h "$ISO_NAME" | cut -f1)"
log "SHA256: $(sha256sum "$ISO_NAME" | cut -d' ' -f1)"
log ""
log "💡 Tipp: Bei Cleanup-Problemen verwende: ./$(basename "$0") --cleanup"

# Erfolgreicher Abschluss - deaktiviere Trap und führe normalen Cleanup durch
trap - EXIT ERR
safe_cleanup
log "Build erfolgreich abgeschlossen!"
exit 0
