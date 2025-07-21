#!/usr/bin/env bash
# ===================================================================
# AILINUX - ISO BUILD SCRIPT (v16.1 - UEFI Bootloader Fix)
# ===================================================================
# Lizenz: MIT
# Beschreibung: Dieses Skript automatisiert die Erstellung einer 
#               bootfähigen AILinux Live-ISO inklusive des grafischen
#               Calamares-Installers.
#
# --- Build-Prozess Übersicht ---
#
# 1.  Host vorbereiten:
#     Installiert alle benötigten Tools (debootstrap, xorriso, etc.).
#
# 2.  Build-Verzeichnisstruktur anlegen:
#     Erstellt eine saubere Arbeitsumgebung (chroot/, iso/).
#
# 3.  Basissystem mit debootstrap:
#     Installiert ein Ubuntu-Minimalsystem in das chroot-Verzeichnis.
#
# 4.  Netzwerk und Service-Block im Chroot:
#     Konfiguriert DNS und verhindert den automatischen Start von
#     Diensten während des Builds.
#
# 5.  Chroot-Skript erstellen:
#     Generiert ein Skript, das alle Konfigurationen innerhalb
#     der Chroot-Umgebung durchführt.
#
# 6.  Chroot-Umgebung ausführen & System installieren:
#     Mountet Pseudo-Dateisysteme (/dev, /proc, /sys), führt das
#     Chroot-Skript aus, um Repositories, Pakete (Desktop, Calamares, Apps)
#     und die Systemkonfiguration (Benutzer, Autologin) einzurichten.
#
# 7.  Pseudo-Dateisysteme unmounten:
#     Bereinigt alle Mounts nach Verlassen des Chroots.
#
# 8.  SquashFS erzeugen:
#     Komprimiert das gesamte Chroot-Dateisystem in eine einzige
#     Datei (filesystem.squashfs).
#
# 9.  Manifest & Metadaten generieren:
#     Erstellt die Paketliste (manifest) und andere ISO-Metadaten.
#
# 10. Bootloader einrichten (BIOS & UEFI):
#     Konfiguriert ISOLINUX für den Legacy-Boot und GRUB für UEFI.
#
# 11. Finale ISO erzeugen:
#     Baut mit xorriso die bootfähige Hybrid-ISO-Datei.
#
# 12. Abschluss und Validierung:
#     Setzt die Dateiberechtigungen, gibt Größe und SHA256-Prüfsumme aus.
#
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

# --- System- und Benutzerinformationen ---
readonly ORIGINAL_USER=${SUDO_USER:-$(whoami)}
readonly ORIGINAL_GROUP=$(id -gn "$ORIGINAL_USER")

# --- Mount-Status Tracking ---
declare -A MOUNTED_PATHS
MOUNT_LOCK_FILE="/tmp/ailinux-build-mounts-$$"

# --- Logging-Funktionen ---
log()   { echo -e "${GREEN}[INFO]    $(date '+%Y-%m-%d %H:%M:%S')${NC} | $*" | tee -a "$LOG_FILE"; }
warn()  { echo -e "${YELLOW}[WARNING] $(date '+%Y-%m-%d %H:%M:%S')${NC} | $*" | tee -a "$LOG_FILE"; }
debug() { echo -e "${BLUE}[DEBUG]   $(date '+%Y-%m-%d %H:%M:%S')${NC} | $*" | tee -a "$LOG_FILE"; }
error_exit() {
  echo -e "${RED}[ERROR]   $(date '+%Y-%m-%d %H:%M:%S')${NC} | $*" | tee -a "$LOG_FILE"
  safe_cleanup
  log "Build fehlgeschlagen. Siehe Log: $LOG_FILE"
  exit 1
}

# --- Sichere Mount-Funktionen (ohne eval) ---
safe_mount() {
    local source="$1"
    local target="$2"
    local fstype="${3:-auto}"
    local options="${4:-}"

    debug "Versuche Mount: $source -> $target (Type: $fstype, Options: $options)"

    if [[ ! -d "$target" ]]; then
        debug "Erstelle Mount-Punkt: $target"
        sudo mkdir -p "$target" || {
            warn "Konnte Mount-Punkt nicht erstellen: $target"
            return 1
        }
    fi

    if mountpoint -q "$target" 2>/dev/null; then
        debug "Bereits gemountet: $target"
        MOUNTED_PATHS["$target"]=1
        return 0
    fi

    local mount_args=()
    [[ "$fstype" != "auto" ]] && mount_args+=("-t" "$fstype")
    [[ -n "$options" ]] && mount_args+=("-o" "$options")
    mount_args+=("$source" "$target")

    debug "Mount-Befehl: sudo mount ${mount_args[*]}"

    if sudo mount "${mount_args[@]}"; then
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

    if ! mountpoint -q "$target" 2>/dev/null; then
        debug "Nicht gemountet: $target"
        unset MOUNTED_PATHS["$target"]
        return 0
    fi

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

        if [[ $attempts -lt $max_attempts ]]; then
            debug "Umount fehlgeschlagen, warte 2 Sekunden..."
            sleep 2

            if command -v lsof >/dev/null 2>&1; then
                debug "Prozesse die $target verwenden:"
                sudo lsof +D "$target" 2>/dev/null | head -5 || true
            fi
        fi
    done

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

    cleanup_chroot_processes
    cleanup_mounts
    cleanup_build_directory

    [[ -f "$MOUNT_LOCK_FILE" ]] && rm -f "$MOUNT_LOCK_FILE"

    log "Cleanup abgeschlossen"
}

cleanup_chroot_processes() {
    if [[ ! -d "$BUILD_DIR/chroot" ]]; then return 0; fi
    debug "Prüfe auf aktive chroot-Prozesse..."

    local chroot_pids=()
    if command -v lsof >/dev/null 2>&1; then
        while IFS= read -r pid; do
            [[ -n "$pid" && "$pid" != "PID" ]] && chroot_pids+=("$pid")
        done < <(sudo lsof +D "$BUILD_DIR/chroot" 2>/dev/null | awk 'NR>1 {print $2}' | sort -u || true)
    fi

    if [[ ${#chroot_pids[@]} -gt 0 ]]; then
        log "Gefunden ${#chroot_pids[@]} Prozesse im chroot, beende sanft..."
        sudo kill -TERM "${chroot_pids[@]}" 2>/dev/null || true
        sleep 3
        sudo kill -KILL "${chroot_pids[@]}" 2>/dev/null || true
    fi
}

cleanup_mounts() {
    debug "Bereinige Mounts..."

    local mount_list=()
    if [[ -f "$MOUNT_LOCK_FILE" ]]; then
        mapfile -t mount_list < "$MOUNT_LOCK_FILE"
    fi

    for mount_point in "${!MOUNTED_PATHS[@]}"; do
        [[ -n "$mount_point" ]] && mount_list+=("$mount_point")
    done

    if [[ -d "$BUILD_DIR/chroot" ]]; then
        for mount_suffix in "run" "sys" "proc" "dev/pts" "dev"; do
            local full_path="$BUILD_DIR/chroot/$mount_suffix"
            if mountpoint -q "$full_path" 2>/dev/null; then
                mount_list+=("$full_path")
            fi
        done
    fi

    local unique_mounts=($(printf '%s\n' "${mount_list[@]}" | sort -ur))

    if [[ ${#unique_mounts[@]} -gt 0 ]]; then
        log "Umounte ${#unique_mounts[@]} Mount-Punkte..."

        for mount_point in "${unique_mounts[@]}"; do
            safe_umount "$mount_point" false
        done

        for mount_point in "${unique_mounts[@]}"; do
            if mountpoint -q "$mount_point" 2>/dev/null; then
                safe_umount "$mount_point" true
            fi
        done
    fi
}

cleanup_build_directory() {
    if [[ ! -d "$BUILD_DIR" ]]; then return 0; fi
    debug "Entferne Build-Verzeichnis: $BUILD_DIR"

    if command -v findmnt &> /dev/null && findmnt -rno TARGET | grep -q "^$(realpath "$BUILD_DIR")"; then
        warn "Verbleibende Mounts in $BUILD_DIR gefunden. Cleanup wird übersprungen."
        findmnt -rno TARGET | grep "^$(realpath "$BUILD_DIR")" | while read -r line; do warn "  - $line"; done
        return 1
    fi

    if ! sudo rm -rf "$BUILD_DIR"; then
        warn "Konnte Build-Verzeichnis nicht vollständig entfernen."
    else
        log "✓ Build-Verzeichnis entfernt"
    fi
}

# --- Notfall-Cleanup ---
if [[ "${1:-}" == "--cleanup" ]]; then
    log "AILinux Notfall-Cleanup gestartet"
    for build_dir in AILINUX_BUILD*; do
        if [[ -d "$build_dir" ]]; then
            log "Bereinige: $build_dir"
            BUILD_DIR="$build_dir"
            safe_cleanup
        fi
    done
    rm -f /tmp/ailinux-build-mounts-* 2>/dev/null || true
    log "Notfall-Cleanup abgeschlossen"
    exit 0
fi

# --- Traps für automatischen Cleanup ---
trap safe_cleanup EXIT
trap 'error_exit "FEHLER in Zeile $LINENO: Befehl \`$BASH_COMMAND\` schlug mit Status $? fehl."' ERR

# ===================================================================
# --- HAUPTSKRIPT START ---
# ===================================================================

log "AILinux Build Script gestartet (v16.1 - UEFI Bootloader Fix)"

if [[ $(id -u) -eq 0 ]]; then
    error_exit "Bitte Skript nicht als root ausführen. Es werden bei Bedarf sudo-Rechte angefordert."
fi

# Lock-File für sauberen Start leeren
rm -f "$MOUNT_LOCK_FILE"

# Initialer Cleanup vor dem Start
safe_cleanup || true

if [[ -f "$ISO_NAME" ]]; then
    ISO_NAME="ailinux-24.04-amd64-$(date +%Y%m%d-%H%M%S).iso"
    log "ISO existiert bereits. Neuer Name: $ISO_NAME"
fi

# --- 1. Host vorbereiten ---
log "[Schritt 1/12] Installiere Host-Abhängigkeiten..."
sudo apt-get update
sudo apt-get install -y debootstrap squashfs-tools xorriso \
    grub-pc-bin grub-efi-amd64-bin shim-signed ovmf \
    mtools wget curl gnupg isolinux syslinux-common \
    dosfstools psmisc lsof

# --- 2. Build-Verzeichnisstruktur anlegen ---
log "[Schritt 2/12] Erstelle Verzeichnisstruktur..."
mkdir -p "$BUILD_DIR/chroot" \
         "$BUILD_DIR/iso"/{casper,boot/grub,isolinux,EFI/boot,.disk}

# --- 3. Basissystem mit debootstrap ---
log "[Schritt 3/12] Starte debootstrap Basissystem..."
sudo debootstrap --arch=amd64 --variant=minbase \
  --include=gpg,ubuntu-keyring,ca-certificates,wget,systemd \
  "$DISTRO" "$BUILD_DIR/chroot" "$UBUNTU_MIRROR"

# --- 4. Netzwerk und Service-Block innerhalb chroot ---
log "[Schritt 4/12] Konfiguriere Netzwerk & blockiere Services im Chroot..."
sudo tee "$BUILD_DIR/chroot/etc/resolv.conf" >/dev/null <<EOF
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF
sudo cp /etc/hosts "$BUILD_DIR/chroot/etc/hosts"
sudo tee "$BUILD_DIR/chroot/usr/sbin/policy-rc.d" >/dev/null <<'EOF'
#!/bin/sh
exit 101
EOF
sudo chmod +x "$BUILD_DIR/chroot/usr/sbin/policy-rc.d"

# --- 5. Chroot-Skript erstellen ---
log "[Schritt 5/12] Erzeuge Chroot-Skript..."
sudo tee "$BUILD_DIR/chroot/chroot-script.sh" >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 LC_ALL=C.UTF-8 HOME=/root

info_chroot() { echo -e "\033[0;32m[CHROOT-INFO]\033[0m | $*"; }
warn() { echo -e "\033[1;33m[CHROOT-WARN]\033[0m | $*"; }

safe_install() {
    local pkgs=("$@")
    if [[ ${#pkgs[@]} -eq 0 ]]; then
        info_chroot "Keine Pakete zur Installation ausgewählt."
        return 0
    fi
    info_chroot "Versuche Installation von ${#pkgs[@]} Paket(en): ${pkgs[*]}"
    if apt-get install -y --no-install-recommends "${pkgs[@]}"; then
        info_chroot "✓ Erfolgreich installiert: ${pkgs[*]}"
        return 0
    else
        info_chroot "✗ Installation fehlgeschlagen für: ${pkgs[*]}"
        return 1
    fi
}

# --- Chroot Phase 1: Umgebung stabilisieren ---
pre_setup_chroot() {
    info_chroot "Phase 1: Stabilisiere Chroot-Umgebung..."
    apt-get update
    apt-get install -y apt-utils locales
    echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
    echo "de_DE.UTF-8 UTF-8" >> /etc/locale.gen
    locale-gen
    dpkg --configure -a
}

# --- Chroot Phase 2: Repositories und Branding einrichten ---
setup_repositories() {
    info_chroot "Phase 2: Richte Repositories und Branding ein..."
    apt-get install -y curl wget

    info_chroot "🚀 Führe zentrales AILinux Repository-Setup-Skript aus..."
    curl -fsSL "https://ailinux.me:8443/mirror/add-ailinux-repo.sh" | bash
    
    info_chroot "✓ Repository-Setup via externem Skript abgeschlossen."
}

# --- Chroot Phase 3: Pakete installieren ---
install_packages() {
    info_chroot "Phase 3: Installiere Pakete..."
    
    # Desktop-Umgebung, Basissystem, Bootloader und Calamares Installer
    apt-get install -y \
        ubuntu-standard linux-image-generic linux-headers-generic \
        linux-firmware casper network-manager systemd-sysv \
        sddm sddm-theme-breeze plymouth plymouth-themes \
        kde-full plasma-nm konsole dolphin kate \
        calamares grub-efi-amd64-signed shim-signed

    # Standard-Anwendungen
    info_chroot "Installiere Standard-Anwendungen..."
    safe_install firefox thunderbird libreoffice gimp inkscape vlc filezilla steam-installer

    # Bedingte Installation von Drittanbieter-Paketen
    if [[ -f /etc/apt/keyrings/google-chrome.gpg ]]; then
        safe_install google-chrome-stable || warn "Installation von Google Chrome fehlgeschlagen."
    fi
    if [[ -f /etc/apt/keyrings/winehq-archive.key ]]; then
        safe_install winehq-staging winetricks || warn "Installation von Wine fehlgeschlagen."
    fi

    # Optionale Installation der AILinux-Pakete
    info_chroot "Versuche, AILinux-spezifische Pakete zu installieren..."
    safe_install ailinux-app || warn "Paket 'ailinux-app' nicht gefunden, wird übersprungen."
}

# --- Chroot Phase 4: System konfigurieren ---
configure_system() {
    info_chroot "Phase 4: Konfiguriere System..."
    useradd -m -s /bin/bash -G sudo,adm,cdrom,dip,plugdev,lpadmin ailinux
    echo "ailinux:ailinux" | chpasswd
    echo "ailinux ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/99-live-user
    chmod 0440 /etc/sudoers.d/99-live-user

    echo "ailinux" > /etc/hostname
    echo "127.0.1.1 ailinux" >> /etc/hosts

    mkdir -p /etc/sddm.conf.d
    tee /etc/sddm.conf.d/autologin.conf <<SDDMEOF
[Autologin]
User=ailinux
Session=plasma-x11.desktop
SDDMEOF

    systemctl enable sddm NetworkManager

    # Calamares Konfiguration und Desktop-Launcher
    info_chroot "Konfiguriere Calamares Installer..."
    local DESKTOP_DIR="/home/ailinux/Desktop"
    mkdir -p "${DESKTOP_DIR}"
    
    # Erstelle einen einfachen Desktop-Launcher
    tee "${DESKTOP_DIR}/install-ailinux.desktop" <<DESKTOPEOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Install AILinux
Exec=pkexec calamares
Icon=calamares
Terminal=false
Categories=System;
DESKTOPEOF
    
    # Setze Dateiberechtigungen für den Launcher und das Home-Verzeichnis
    chmod +x "${DESKTOP_DIR}/install-ailinux.desktop"
    chown -R ailinux:ailinux /home/ailinux
    
    # Grundlegendes Branding für Calamares
    if [ -d /etc/calamares/branding ]; then
        mkdir -p /etc/calamares/branding/ailinux
        # Hier könnten Logo-Dateien und eine branding.desc platziert werden
        # Beispiel: cp /pfad/zu/logo.png /etc/calamares/branding/ailinux/
        
        # settings.conf anpassen, um das Branding zu verwenden
        sed -i 's/^branding:.*$/branding: ailinux/' /etc/calamares/settings.conf || true
    fi
}

# --- Chroot Phase 5: Bereinigung ---
cleanup_chroot() {
    info_chroot "Phase 5: Führe Bereinigung durch..."
    apt-get autoremove -y --purge
    apt-get clean
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
    rm -f /usr/sbin/policy-rc.d /chroot-script.sh
    find /var/log -type f -exec truncate -s 0 {} \;
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

# --- 6. Chroot-Umgebung ausführen und System installieren ---
log "[Schritt 6/12] Starte sichere Chroot-Ausführung..."
log "Mounte Pseudo-Dateisysteme..."
safe_mount "/dev"     "$BUILD_DIR/chroot/dev"     "auto" "bind"    || error_exit "/dev Mount fehlgeschlagen"
safe_mount "/dev/pts" "$BUILD_DIR/chroot/dev/pts" "auto" "bind"    || error_exit "/dev/pts Mount fehlgeschlagen"
safe_mount "none"     "$BUILD_DIR/chroot/proc"    "proc" ""        || error_exit "/proc Mount fehlgeschlagen"
safe_mount "none"     "$BUILD_DIR/chroot/sys"     "sysfs" ""       || error_exit "/sys Mount fehlgeschlagen"
safe_mount "none"     "$BUILD_DIR/chroot/run"     "tmpfs" ""       || warn "/run Mount fehlgeschlagen"

log "Führe Chroot-Skript aus..."
if ! sudo chroot "$BUILD_DIR/chroot" /chroot-script.sh 2>&1 | tee -a "$LOG_FILE"; then
    error_exit "Chroot-Ausführung fehlgeschlagen"
fi

# --- 7. Post-Chroot Cleanup (Pseudo-Dateisysteme unmounten) ---
log "[Schritt 7/12] Post-Chroot Cleanup der Pseudo-Dateisysteme..."
cleanup_mounts

# --- 8. SquashFS erzeugen ---
log "[Schritt 8/12] Erstelle SquashFS..."
sudo mksquashfs "$BUILD_DIR/chroot" "$BUILD_DIR/iso/casper/filesystem.squashfs" \
  -e boot -noappend -no-exports -no-recovery -no-fragments -no-duplicates \
  -b 1M -comp zstd $SQUASHFS_LEVEL -processors "$(nproc)"

# --- 9. Manifest & Metadaten generieren ---
log "[Schritt 9/12] Erstelle Manifest & Metadaten..."
sudo chroot "$BUILD_DIR/chroot" dpkg-query -W --showformat='${Package}\t${Version}\n' | sudo tee "$BUILD_DIR/iso/casper/filesystem.manifest" >/dev/null
sudo du -sx --block-size=1 "$BUILD_DIR/chroot" | cut -f1 | sudo tee "$BUILD_DIR/iso/casper/filesystem.size" >/dev/null
echo "AILinux 24.04 LTS – Release $(date +%Y%m%d)" | sudo tee "$BUILD_DIR/iso/.disk/info" >/dev/null

# --- 10. Bootloader einrichten (BIOS & UEFI) ---
log "[Schritt 10/12] Konfiguriere Bootloader (BIOS & UEFI)..."
sudo cp /usr/lib/ISOLINUX/isolinux.bin "$BUILD_DIR/iso/isolinux/"
sudo cp /usr/lib/syslinux/modules/bios/*.c32 "$BUILD_DIR/iso/isolinux/"
sudo tee "$BUILD_DIR/iso/isolinux/isolinux.cfg" >/dev/null <<CFG
DEFAULT vesamenu.c32
TIMEOUT 50
MENU TITLE AILinux 24.04 LTS
LABEL live
  MENU LABEL ^Start or Install AILinux 24.04 LTS
  KERNEL /casper/vmlinuz
  APPEND initrd=/casper/initrd boot=casper quiet splash ---
CFG

sudo tee "$BUILD_DIR/iso/boot/grub/grub.cfg" >/dev/null <<CFG
set default=0
set timeout=5
menuentry "Start or Install AILinux 24.04 LTS (UEFI)" {
  linux /casper/vmlinuz boot=casper quiet splash ---
  initrd /casper/initrd
}
CFG

log "Erstelle EFI Boot-Image..."
EFI_IMG="$BUILD_DIR/iso/boot/grub/efi.img"
sudo dd if=/dev/zero of="$EFI_IMG" bs=1M count=20
sudo mkfs.fat -F 12 -n "EFIBOOT" "$EFI_IMG"
EFI_MOUNT=$(mktemp -d)
sudo mount -o loop "$EFI_IMG" "$EFI_MOUNT"
sudo mkdir -p "$EFI_MOUNT/EFI/boot"
sudo cp "$BUILD_DIR/chroot/usr/lib/shim/shimx64.efi.signed" "$EFI_MOUNT/EFI/boot/bootx64.efi"
sudo cp "$BUILD_DIR/chroot/usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed" "$EFI_MOUNT/EFI/boot/grubx64.efi"
sudo cp "$BUILD_DIR/iso/boot/grub/grub.cfg" "$EFI_MOUNT/EFI/boot/"
sudo umount "$EFI_MOUNT"
rmdir "$EFI_MOUNT"
sudo cp -r "$BUILD_DIR/iso/boot" "$BUILD_DIR/iso/EFI/"

# --- 11. Finale ISO erzeugen ---
log "[Schritt 11/12] Erstelle finale ISO: $ISO_NAME"
MBR_TEMPLATE="/usr/lib/ISOLINUX/isohdpfx.bin"
if [[ ! -f "$MBR_TEMPLATE" ]]; then MBR_TEMPLATE="/usr/lib/syslinux/mbr/isohdpfx.bin"; fi
if [[ ! -f "$MBR_TEMPLATE" ]]; then error_exit "Kein MBR Template (isohdpfx.bin) gefunden"; fi

sudo xorriso -as mkisofs \
  -r -V "$ISO_LABEL" -o "$ISO_NAME" \
  -J -joliet-long -l \
  -isohybrid-mbr "$MBR_TEMPLATE" \
  -c isolinux/boot.cat -b isolinux/isolinux.bin \
  -no-emul-boot -boot-load-size 4 -boot-info-table \
  -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot -isohybrid-gpt-basdat \
  "$BUILD_DIR/iso" 2>&1 | tee -a "$LOG_FILE"

# --- 12. Abschluss und Validierung ---
log "[Schritt 12/12] Abschluss und Validierung..."
if [[ -f "$ISO_NAME" ]]; then
    log "Korrigiere Dateiberechtigungen für $ISO_NAME..."
    sudo chown "$ORIGINAL_USER:$ORIGINAL_GROUP" "$ISO_NAME"
    log "✓ ISO-Eigentümer auf $ORIGINAL_USER:$ORIGINAL_GROUP gesetzt."
fi

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
