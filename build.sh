#!/usr/bin/env bash
# ===================================================================
# AILINUX - ISO BUILD SCRIPT (v10.37 - Korrigierte Version)
# ===================================================================
# Lizenz: MIT
# ===================================================================

set -euo pipefail

# --- Farbdefinitionen für Logging ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# --- Konfigurationsvariablen ---
BUILD_DIR='AILINUX_BUILD'
DISTRO='noble'
ISO_LABEL='AILINUX-2404'
ISO_NAME='ailinux-24.04-amd64.iso'
LOG_FILE="ailinux-build-$(date +%Y%m%d-%H%M%S).log"
UBUNTU_MIRROR='http://archive.ubuntu.com/ubuntu'
SQUASHFS_LEVEL='-Xcompression-level 22'

# --- Logging-Funktionen ---
log()  { echo -e "${GREEN}[INFO]    $(date '+%Y-%m-%d %H:%M:%S')${NC} | $*" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[WARNING] $(date '+%Y-%m-%d %H:%M:%S')${NC} | $*" | tee -a "$LOG_FILE"; }
error_exit() {
  echo -e "${RED}[ERROR]   $(date '+%Y-%m-%d %H:%M:%S')${NC} | $*" | tee -a "$LOG_FILE"
  cleanup_mounts
  log "Build fehlgeschlagen. Siehe Log: $LOG_FILE"
  exit 1
}

# --- Cleanup-Funktion für Pseudo-FS und Verzeichnis ---
cleanup_mounts() {
  set +e
  log "Cleanup: Unmount Pseudo-FS..."
  for m in dev/pts dev proc sys run; do
    if mountpoint -q "$BUILD_DIR/chroot/$m" 2>/dev/null; then
      sudo umount -lf "$BUILD_DIR/chroot/$m"
    fi
  done
  set -e
}

cleanup() {
  cleanup_mounts
  if [ -d "$BUILD_DIR" ]; then
    log "Cleanup: Entferne Build-Verzeichnis..."
    sudo rm -rf "$BUILD_DIR"
  fi
}

# --- Initial cleanup von vorherigen Builds ---
initial_cleanup() {
  log "Führe initialen Cleanup durch..."
  
  # Prüfe auf gemountete Verzeichnisse von vorherigen Builds
  set +e
  for m in dev/pts dev proc sys run; do
    if mountpoint -q "$BUILD_DIR/chroot/$m" 2>/dev/null; then
      log "Unmounte vorheriges Build-Verzeichnis: $BUILD_DIR/chroot/$m"
      sudo umount -lf "$BUILD_DIR/chroot/$m"
    fi
  done
  set -e
  
  # Entferne alte Build-Verzeichnisse
  if [ -d "$BUILD_DIR" ]; then
    log "Entferne vorheriges Build-Verzeichnis..."
    sudo rm -rf "$BUILD_DIR"
  fi
}

trap cleanup EXIT
trap 'error_exit "FEHLER in Zeile $LINENO: Befehl \`$BASH_COMMAND\` schlug mit Status $? fehl."' ERR

# --- 1. Host-Vorbereitung ---
log "AILinux Build Script gestartet (Version 10.39 - Offizielles AILinux Repository Script)"

if [[ $(id -u) -eq 0 ]]; then
  error_exit "Bitte Skript nicht als root ausführen"
fi

# Initialer Cleanup von vorherigen Builds
initial_cleanup

if [ -f "$ISO_NAME" ]; then
    ISO_NAME="ailinux-24.04-amd64-$(date +%Y%m%d-%H%M%S).iso"
    log "ISO existiert bereits. Neuer Name: $ISO_NAME"
fi

log "Installiere Host-Abhängigkeiten..."
sudo apt-get update
sudo apt-get install -y debootstrap squashfs-tools xorriso \
     grub-pc-bin grub-efi-amd64-bin shim-signed ovmf \
     mtools wget curl gnupg isolinux syslinux-common \
     dosfstools

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

# --- 5. chroot-Skript erzeugen ---
log "Erzeuge chroot-script.sh..."
sudo tee "$BUILD_DIR/chroot/chroot-script.sh" >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 LC_ALL=C.UTF-8 HOME=/root

info_chroot() { echo -e "\033[0;32m[CHROOT-INFO]\033[0m | $*"; }

# --- Hilfsfunktion für sichere Paketinstallation ---
safe_install() {
    local packages="$*"
    info_chroot "Versuche Installation: $packages"
    if apt-get install -y $packages 2>/dev/null; then
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
    apt-get update || {
        info_chroot "WARNUNG: Repository-Update fehlgeschlagen - fahre trotzdem fort"
    }
    
    info_chroot "Repositories erfolgreich konfiguriert"
    
    # Installiere essentielle Pakete
    apt-get install -y apt-utils locales
    
    # Versuche dialog zu installieren (optional)
    if ! apt-get install -y dialog 2>/dev/null; then
        info_chroot "WARNUNG: dialog Paket nicht verfügbar - überspringe"
    fi
    
    echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
    echo "de_DE.UTF-8 UTF-8" >> /etc/locale.gen
    locale-gen
    dpkg --configure -a
}

# --- Chroot Phase 2: Repositories einrichten ---
setup_repositories() {
    info_chroot "Phase 2: Richte Repositories ein..."
    
    # Stelle sicher, dass curl verfügbar ist
    apt-get install -y curl gnupg software-properties-common

    local KEYRING_DIR="/etc/apt/keyrings"
    mkdir -p "${KEYRING_DIR}"
    
    # Standard Ubuntu Repositories
    rm -f /etc/apt/sources.list /etc/apt/sources.list.d/*.list
    tee /etc/apt/sources.list.d/main.sources >/dev/null <<SRC
Types: deb
URIs: http://archive.ubuntu.com/ubuntu
Suites: noble noble-updates noble-security
Components: main restricted universe multiverse
SRC

    # AILinux Repository mit offiziellem Script hinzufügen
    if curl -fssSL https://ailinux.me/mirror/add-ailinux-repo.sh | bash; then
        info_chroot "✓ AILinux Repository erfolgreich hinzugefügt"
    else
        info_chroot "WARNUNG: AILinux Repository konnte nicht hinzugefügt werden"
    fi

    # Optionale externe Repositories (mit Fehlerbehandlung)
    # Google Chrome
    if wget -qO "/tmp/chrome.gpg" "https://dl.google.com/linux/linux_signing_key.pub" 2>/dev/null; then
        gpg --dearmor -o "${KEYRING_DIR}/google-chrome.gpg" "/tmp/chrome.gpg"
        rm -f "/tmp/chrome.gpg"
        tee /etc/apt/sources.list.d/chrome.sources >/dev/null <<SRC
Types: deb
URIs: https://dl.google.com/linux/chrome/deb/
Suites: stable
Components: main
Architectures: amd64
Signed-By: ${KEYRING_DIR}/google-chrome.gpg
SRC
        info_chroot "Google Chrome Repository hinzugefügt"
    else
        info_chroot "WARNUNG: Google Chrome Repository konnte nicht hinzugefügt werden"
    fi

    # WineHQ
    if wget -qO "/tmp/winehq.gpg" "https://dl.winehq.org/wine-builds/winehq.key" 2>/dev/null; then
        gpg --dearmor -o "${KEYRING_DIR}/winehq.gpg" "/tmp/winehq.gpg"
        rm -f "/tmp/winehq.gpg"
        tee -a /etc/apt/sources.list.d/winehq.sources >/dev/null <<SRC
Types: deb
URIs: https://dl.winehq.org/wine-builds/ubuntu/
Suites: noble
Components: main
Architectures: amd64 i386
Signed-By: ${KEYRING_DIR}/winehq.gpg
SRC
        dpkg --add-architecture i386
        info_chroot "WineHQ Repository hinzugefügt"
    else
        info_chroot "WARNUNG: WineHQ Repository konnte nicht hinzugefügt werden"
    fi

    apt-get update
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
    tee /etc/sddm.conf.d/autologin.conf >/dev/null <<SDDM
[Autologin]
User=ailinux
Session=plasmax11.desktop
SDDM

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
        tee /usr/local/bin/calamares-wrapper >/dev/null <<'WRAPPER'
#!/bin/bash
export DISPLAY="${DISPLAY:-:0}"
export HOME="${HOME:-/root}"
if [ -z "$XDG_RUNTIME_DIR" ]; then
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
fi
exec /usr/bin/calamares "$@"
WRAPPER
        chmod +x /usr/local/bin/calamares-wrapper

        tee "${DESKTOP_DIR}/install-ailinux.desktop" >/dev/null <<'DESKTOP'
[Desktop Entry]
Version=1.0
Type=Application
Name=Install AILinux 24.04 LTS
Exec=pkexec /usr/local/bin/calamares-wrapper
Icon=calamares
Terminal=false
Categories=System;
DESKTOP
    elif command -v ubiquity >/dev/null 2>&1; then
        # Ubiquity als Fallback
        tee "${DESKTOP_DIR}/install-ailinux.desktop" >/dev/null <<'DESKTOP'
[Desktop Entry]
Version=1.0
Type=Application
Name=Install AILinux 24.04 LTS
Exec=ubiquity
Icon=ubiquity
Terminal=false
Categories=System;
DESKTOP
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
    find /var/log -type f -exec truncate -s 0 {} \; 2>/dev/null || true
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

# --- 6. Chroot ausführen ---
log "Mount Pseudo-FS & Starte Chroot..."
sudo mount --bind /dev      "$BUILD_DIR/chroot/dev"
sudo mount --bind /dev/pts  "$BUILD_DIR/chroot/dev/pts"
sudo mount -t proc none     "$BUILD_DIR/chroot/proc"
sudo mount -t sysfs none    "$BUILD_DIR/chroot/sys"
sudo mount -t tmpfs none    "$BUILD_DIR/chroot/run"

# Chroot ausführen mit verbesserter Fehlerbehandlung
if ! sudo chroot "$BUILD_DIR/chroot" /chroot-script.sh 2>&1 | tee -a "$LOG_FILE"; then
    error_exit "Chroot-Ausführung fehlgeschlagen"
fi

# --- 7. ISO vorbereiten ---
log "Bereite ISO-Verzeichnis vor..."
cleanup_mounts

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
  | sudo tee "$BUILD_DIR/iso/casper/filesystem.manifest" > /dev/null
sudo du -sx --block-size=1 "$BUILD_DIR/chroot" | cut -f1 \
  | sudo tee "$BUILD_DIR/iso/casper/filesystem.size" > /dev/null
echo "AILinux 24.04 LTS – Release $(date +%Y%m%d)" \
  | sudo tee "$BUILD_DIR/iso/.disk/info" >/dev/null

# --- 8. Bootloader konfigurieren ---
log "Konfiguriere Bootloader (BIOS & UEFI)..."

# ISOLINUX für BIOS-Boot
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

# GRUB für UEFI-Boot
sudo tee "$BUILD_DIR/iso/boot/grub/grub.cfg" >/dev/null <<CFG
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
sudo dd if=/dev/zero of="$EFI_IMG" bs=1M count=10 2>/dev/null
sudo mkfs.fat -F 12 -n "EFIBOOT" "$EFI_IMG"

# EFI-Verzeichnis mounten und konfigurieren
EFI_MOUNT=$(mktemp -d)
sudo mount -o loop "$EFI_IMG" "$EFI_MOUNT"
sudo mkdir -p "$EFI_MOUNT/EFI/boot"

# UEFI-Binaries kopieren
if [ -f "$BUILD_DIR/chroot/usr/lib/shim/shimx64.efi.signed" ]; then
    sudo cp "$BUILD_DIR/chroot/usr/lib/shim/shimx64.efi.signed" "$EFI_MOUNT/EFI/boot/bootx64.efi"
    sudo cp "$BUILD_DIR/iso/EFI/boot/bootx64.efi" "$BUILD_DIR/iso/EFI/boot/" 2>/dev/null || true
fi

if [ -f "$BUILD_DIR/chroot/usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed" ]; then
    sudo cp "$BUILD_DIR/chroot/usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed" "$EFI_MOUNT/EFI/boot/grubx64.efi"
    sudo cp "$EFI_MOUNT/EFI/boot/grubx64.efi" "$BUILD_DIR/iso/EFI/boot/" 2>/dev/null || true
fi

# GRUB-Konfiguration ins EFI-Image
sudo cp "$BUILD_DIR/iso/boot/grub/grub.cfg" "$EFI_MOUNT/EFI/boot/"

sudo umount "$EFI_MOUNT"
rmdir "$EFI_MOUNT"

# --- 9. Finale ISO erstellen ---
log "Erstelle finale ISO: $ISO_NAME"
MBR_TEMPLATE="/usr/lib/ISOLINUX/isohdpfx.bin"
if [ ! -f "$MBR_TEMPLATE" ]; then 
    MBR_TEMPLATE="/usr/lib/syslinux/mbr/isohdpfx.bin"
fi
if [ ! -f "$MBR_TEMPLATE" ]; then 
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

# --- 10. Abschluss ---
log "✅ AILinux ISO $ISO_NAME erfolgreich erstellt!"
log "Dateigröße: $(du -h "$ISO_NAME" | cut -f1)"
log "SHA256: $(sha256sum "$ISO_NAME" | cut -d' ' -f1)"

trap - EXIT ERR
exit 0
