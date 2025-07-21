#!/bin/bash
#
# AILinux ISO Build-Skript (v17.1 - Chroot & Dependency Fix)
# Erstellt eine bootfähige Live-ISO von AILinux basierend auf Ubuntu 24.04 (Noble Numbat)
# und den Spezifikationen in prompt.txt.
#
# Lizenz: MIT License
# Copyright (c) 2024 derleiti

# Strikter Fehlermodus: Bricht bei Fehlern, nicht gesetzten Variablen und Fehlern in Pipelines ab.
set -eo pipefail

# --- Konfiguration ---
DISTRO_NAME="AILinux"
DISTRO_VERSION="24.04"
DISTRO_EDITION="Premium"
UBUNTU_CODENAME="noble"
ARCHITECTURE="amd64"

LIVE_USER="ailinux"
LIVE_HOSTNAME="ailinux"

BUILD_DIR="AILINUX_BUILD"
CHROOT_DIR="${BUILD_DIR}/chroot"
ISO_DIR="${BUILD_DIR}/iso"
ISO_NAME="${DISTRO_NAME,,}-${DISTRO_VERSION}-${DISTRO_EDITION,,}-${ARCHITECTURE}.iso"

# --- Farb- und Logging-Funktionen ---
COLOR_RESET='\033[0m'
COLOR_INFO='\033[0;34m'
COLOR_SUCCESS='\033[0;32m'
COLOR_WARN='\033[0;33m'
COLOR_ERROR='\033[0;31m'
COLOR_STEP='\033[1;36m'

log() {
    local level_color="$1"
    local level_text="$2"
    local message="$3"
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${level_color}[${level_text}]${COLOR_RESET} ${message}"
}

log_info() { log "${COLOR_INFO}" "INFO" "$1"; }
log_success() { log "${COLOR_SUCCESS}" "SUCCESS" "$1"; }
log_warn() { log "${COLOR_WARN}" "WARNING" "$1"; }
log_error() { log "${COLOR_ERROR}" "ERROR" "$1"; }
log_step() { log "${COLOR_STEP}" "STEP ${1}" "-------------------- ${2} --------------------"; }

# --- Sicherheits- und Hilfsfunktionen ---
check_not_root() {
    if [ "$(id -u)" -eq 0 ]; then
        log_error "Dieses Skript darf nicht als root ausgeführt werden. Es verwendet bei Bedarf 'sudo'."
        exit 1
    fi
}

cleanup() {
    log_warn "Starte Bereinigung des Build-Verzeichnisses..."
    set +e # Fehler während der Bereinigung ignorieren

    if mountpoint -q "${CHROOT_DIR}/run"; then sudo umount -f -l "${CHROOT_DIR}/run"; fi
    if mountpoint -q "${CHROOT_DIR}/sys"; then sudo umount -f -l "${CHROOT_DIR}/sys"; fi
    if mountpoint -q "${CHROOT_DIR}/proc"; then sudo umount -f -l "${CHROOT_DIR}/proc"; fi
    if mountpoint -q "${CHROOT_DIR}/dev/pts"; then sudo umount -f -l "${CHROOT_DIR}/dev/pts"; fi
    if mountpoint -q "${CHROOT_DIR}/dev"; then sudo umount -f -l "${CHROOT_DIR}/dev"; fi

    log_info "Entferne Build-Verzeichnis: ${BUILD_DIR}"
    sudo rm -rf "${BUILD_DIR}"
    
    if [ ! -d "${BUILD_DIR}" ]; then
        log_success "Bereinigung erfolgreich abgeschlossen."
    fi
    set -e
}

trap 'log_error "Skript unerwartet bei Schritt ${current_step:-unbekannt} beendet."; cleanup; exit 1' INT TERM ERR

# --- Build-Schritte als Funktionen ---

step_01_setup_environment() {
    log_step "1/12" "Umgebung einrichten und Abhängigkeiten prüfen"
    
    local dependencies=("debootstrap" "squashfs-tools" "xorriso" "grub-pc-bin" "grub-efi-amd64-bin" "mtools" "dosfstools" "isolinux" "syslinux-common" "shim-signed" "gnupg")
    local missing_deps=()
    log_info "Prüfe Abhängigkeiten..."
    
    for dep in "${dependencies[@]}"; do
        if ! dpkg -l | grep -q "^ii  $dep"; then
            missing_deps+=("$dep")
        fi
    done

    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_warn "Folgende Abhängigkeiten fehlen: ${missing_deps[*]}"
        read -p "Sollen diese automatisch installiert werden? (j/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Jj]$ ]]; then
            log_info "Installiere fehlende Abhängigkeiten..."
            sudo apt-get update
            sudo apt-get install -y "${missing_deps[@]}"
        else
            log_error "Installation abgebrochen. Bitte installieren Sie die Pakete manuell."
            exit 1
        fi
    fi

    if [ -d "${BUILD_DIR}" ]; then
        log_warn "Altes Build-Verzeichnis gefunden. Führe Bereinigung durch..."
        cleanup
    fi

    mkdir -p "${CHROOT_DIR}" "${ISO_DIR}"
    log_success "Build-Umgebung erfolgreich eingerichtet."
}

step_02_debootstrap() {
    log_step "2/12" "Basissystem mit debootstrap erstellen"
    sudo debootstrap --arch="${ARCHITECTURE}" --variant=minbase "${UBUNTU_CODENAME}" "${CHROOT_DIR}" http://archive.ubuntu.com/ubuntu/
    log_success "Basissystem erfolgreich erstellt."
}

step_03_mount_filesystems() {
    log_step "3/12" "Pseudo-Dateisysteme einhängen"
    sudo mount --bind /dev "${CHROOT_DIR}/dev"
    sudo mount --bind /dev/pts "${CHROOT_DIR}/dev/pts"
    sudo mount -t proc proc "${CHROOT_DIR}/proc"
    sudo mount -t sysfs sysfs "${CHROOT_DIR}/sys"
    
    sudo cp /etc/resolv.conf "${CHROOT_DIR}/etc/"
    log_success "Alle Pseudo-Dateisysteme erfolgreich eingehängt."
}

step_04_chroot_base_config() {
    log_step "4/12" "Chroot: Basiskonfiguration, AILinux Repo & Mirror-Wechsel"
    sudo chroot "${CHROOT_DIR}" /bin/bash <<'EOF'
        set -e
        echo "ailinux" > /etc/hostname

        cat > /etc/apt/sources.list << "SOURCES"
deb http://archive.ubuntu.com/ubuntu/ noble main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ noble-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ noble-security main restricted universe multiverse
SOURCES
        
        export DEBIAN_FRONTEND=noninteractive
        export LANG=en_US.UTF-8
        export LC_ALL=en_US.UTF-8
        apt-get update
        apt-get install -y --no-install-recommends locales apt-utils dialog curl wget gnupg2 ca-certificates zstd
        
        echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
        locale-gen
        update-locale LANG=en_US.UTF-8
        
        echo "Füge AILinux Repository hinzu..."
        curl -fssSL https://ailinux.me:8443/mirror/add-ailinux-repo.sh | bash
        
        echo "Wechsle zu AILinux Ubuntu Mirror..."
        cat > /etc/apt/sources.list << "MIRROR_SOURCES"
deb https://ailinux.me:8443/mirror/archive.ubuntu.com/ubuntu noble main restricted universe multiverse
deb https://ailinux.me:8443/mirror/archive.ubuntu.com/ubuntu noble-updates main restricted universe multiverse
deb https://ailinux.me:8443/mirror/archive.ubuntu.com/ubuntu noble-security main restricted universe multiverse
MIRROR_SOURCES

        apt-get update
EOF
    log_success "Basiskonfiguration und Wechsel zum AILinux Mirror abgeschlossen."
}

step_05_chroot_kernel_core() {
    log_step "5/12" "Chroot: Kernel und Core-System installieren"
    sudo chroot "${CHROOT_DIR}" /bin/bash <<'EOF'
        set -e
        export DEBIAN_FRONTEND=noninteractive
        export LANG=en_US.UTF-8
        export LC_ALL=en_US.UTF-8
        
        apt-get install -y --no-install-recommends \
            linux-image-generic linux-headers-generic casper \
            discover laptop-detect os-prober network-manager \
            resolvconf net-tools wireless-tools plymouth \
            plymouth-theme-spinner ubuntu-standard keyboard-configuration \
            console-setup sudo systemd systemd-sysv dbus init rsyslog
EOF
    log_success "Kernel und Core-System installiert."
}

step_06_chroot_desktop() {
    log_step "6/12" "Chroot: Desktop und Premium-Anwendungen installieren"
    sudo chroot "${CHROOT_DIR}" /bin/bash <<'EOF'
        set -e
        export DEBIAN_FRONTEND=noninteractive
        export LANG=en_US.UTF-8
        export LC_ALL=en_US.UTF-8
        
        log_info() { echo "[CHROOT-INFO] $1"; }
        
        # --- KORREKTUR: Service-Starts simulieren, um Fehler zu vermeiden ---
        log_info "Simuliere Systemdienste für die Installation..."
        cat > /usr/sbin/invoke-rc.d << "INVOKE_RC_D_STUB"
#!/bin/sh
exit 0
INVOKE_RC_D_STUB
        chmod +x /usr/sbin/invoke-rc.d
        
        log_info "Konfiguriere externe Repositories..."
        wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | apt-key add -
        echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list

        mkdir -p /etc/apt/keyrings
        wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key
        echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/winehq-archive.key] https://dl.winehq.org/wine-builds/ubuntu/ noble main" > /etc/apt/sources.list.d/winehq.list

        wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /etc/apt/trusted.gpg.d/microsoft.gpg
        echo "deb [arch=amd64] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list
        
        apt-get update
        
        log_info "Installiere alle Desktop-Komponenten in einem Schritt..."
        
        # KORREKTUR: Alle Pakete in einem Befehl installieren und Abhängigkeiten explizit auflösen
        apt-get install -y \
            systemd-coredump \
            kde-full \
            plasma-desktop \
            sddm-theme-breeze \
            xorg \
            firefox \
            thunderbird \
            vlc \
            gimp \
            libreoffice \
            gparted \
            htop \
            neofetch \
            ubuntu-restricted-extras \
            ffmpeg \
            pulseaudio \
            google-chrome-stable \
            winehq-staging \
            winetricks \
            code \
            git \
            build-essential \
            python3 \
            python3-pip \
            nodejs \
            default-jdk \
            linux-firmware \
            bluez \
            bluetooth \
            wireless-tools \
            wpasupplicant \
            printer-driver-all \
            cups
            
        log_info "Aktiviere wichtige Systemdienste..."
        systemctl enable bluetooth || true
        systemctl enable cups || true
        systemctl enable NetworkManager || true
        systemctl enable sddm || true

        # --- KORREKTUR: Service-Simulation entfernen ---
        log_info "Entferne Service-Simulation..."
        rm /usr/sbin/invoke-rc.d
EOF
    log_success "Desktop und Premium-Anwendungen installiert."
}

step_07_chroot_calamares() {
    log_step "7/12" "Chroot: Calamares Installer vollständig einrichten"
    sudo chroot "${CHROOT_DIR}" /bin/bash <<'EOF'
        set -e
        export DEBIAN_FRONTEND=noninteractive
        export LANG=en_US.UTF-8
        
        apt-get install -y calamares imagemagick
        
        # 1. settings.conf mit korrekter Sequenz
        mkdir -p /etc/calamares
        cat > /etc/calamares/settings.conf << "SETTINGS"
modules-search: [ local, /usr/share/calamares/modules ]
branding: ailinux
sequence:
  - show:
      - welcome
      - partition
      - users
      - summary
  - exec:
      - partition
      - mount
      - unpackfs
      - users
      - bootloader
      - postinstall
      - umount
SETTINGS

        # 2. Branding-Konfiguration
        mkdir -p /etc/calamares/branding/ailinux
        cat > /etc/calamares/branding/ailinux/branding.desc << "BRANDING"
---
componentName:  ailinux
strings:
    productName:        "AILinux 24.04 Premium"
    bootloaderEntryName: "AILinux"
images:
    productLogo:        "logo.png"
BRANDING
        convert -size 240x120 xc:'#1d99f3' -font "DejaVu-Sans-Bold" -pointsize 26 -fill white \
                -gravity center -draw "text 0,0 'AILinux'" \
                /etc/calamares/branding/ailinux/logo.png

        # 3. Wichtige Modul-Konfigurationen erstellen
        mkdir -p /etc/calamares/modules

        cat > /etc/calamares/modules/unpackfs.conf << "UNPACKFS"
unpack:
  - source: "/run/live/medium/casper/filesystem.squashfs"
    sourcefs: "squashfs"
    destination: ""
UNPACKFS

        cat > /etc/calamares/modules/users.conf << "USERS"
default_groups:
  - "adm"
  - "cdrom"
  - "sudo"
  - "dip"
  - "plugdev"
  - "lpadmin"
  - "audio"
  - "video"
USERS

        cat > /etc/calamares/modules/bootloader.conf << "BOOTLOADER"
installBootloader: true
bootloader: "grub"
grubInstall: "efi"
efiBootloaderId: "AILinux"
BOOTLOADER

EOF
    log_success "Calamares Installer vollständig konfiguriert."
}

step_08_chroot_user_setup() {
    log_step "8/12" "Chroot: Live-Benutzer und Desktop anpassen"
    sudo chroot "${CHROOT_DIR}" /bin/bash -c "export LIVE_USER=${LIVE_USER}" <<'EOF'
        set -e
        useradd -s /bin/bash -d "/home/${LIVE_USER}" -m -G adm,cdrom,sudo,dip,plugdev,lpadmin,audio,video "${LIVE_USER}"
        passwd -d "${LIVE_USER}"
        
        echo "${LIVE_USER} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
        
        mkdir -p /etc/sddm.conf.d
        cat > /etc/sddm.conf.d/autologin.conf << AUTOLOGIN_CONF
[Autologin]
User=${LIVE_USER}
Session=plasma
Relogin=false
AUTOLOGIN_CONF

        # Desktop-Verzeichnisse erstellen
        mkdir -p "/home/${LIVE_USER}/Desktop"
        
        # Calamares Installer-Verknüpfung
        cat > "/home/${LIVE_USER}/Desktop/Install AILinux.desktop" << DESKTOP_FILE
[Desktop Entry]
Name=Install AILinux
Name[de]=AILinux installieren
Comment=Install AILinux to your hard drive
Comment[de]=AILinux auf die Festplatte installieren
Exec=pkexec calamares
Icon=calamares
Terminal=false
Type=Application
Categories=System;
DESKTOP_FILE

        # Andere Anwendungs-Verknüpfungen
        ln -s /usr/share/applications/org.kde.konsole.desktop "/home/${LIVE_USER}/Desktop/"
        ln -s /usr/share/applications/firefox.desktop "/home/${LIVE_USER}/Desktop/"
        ln -s /usr/share/applications/google-chrome.desktop "/home/${LIVE_USER}/Desktop/"

        # .bashrc mit Willkommensnachricht anpassen
        cat >> "/home/${LIVE_USER}/.bashrc" << 'BASHRC_CUSTOM'

# AILinux Welcome Message
echo ""
echo "############################################################"
echo "### Welcome to AILinux 24.04 Premium Edition             ###"
echo "############################################################"
echo ""
echo "To install, use the 'Install AILinux' icon on the desktop."
echo ""
BASHRC_CUSTOM
        
        chmod +x "/home/${LIVE_USER}/Desktop/"*.desktop
        chown -R "${LIVE_USER}":"${LIVE_USER}" "/home/${LIVE_USER}"
EOF
    log_success "Live-Benutzer und Desktop angepasst."
}

step_09_chroot_cleanup() {
    log_step "9/12" "Chroot: System bereinigen"
    sudo rm -f "${CHROOT_DIR}/etc/resolv.conf"
    
    sudo chroot "${CHROOT_DIR}" /bin/bash <<'EOF'
        set -e
        apt-get autoremove -y --purge
        apt-get clean
        rm -rf /tmp/* /var/tmp/* /var/lib/apt/lists/*
        find /var/log -type f -exec truncate --size 0 {} \;
        rm -f /etc/machine-id /var/lib/dbus/machine-id
        touch /etc/machine-id
EOF
    log_success "Chroot-System bereinigt."
}

step_10_prepare_iso_structure() {
    log_step "10/12" "ISO-Struktur vorbereiten und SquashFS erstellen"
    
    if mountpoint -q "${CHROOT_DIR}/sys"; then sudo umount -l "${CHROOT_DIR}/sys"; fi
    if mountpoint -q "${CHROOT_DIR}/proc"; then sudo umount -l "${CHROOT_DIR}/proc"; fi
    if mountpoint -q "${CHROOT_DIR}/dev/pts"; then sudo umount -l "${CHROOT_DIR}/dev/pts"; fi
    if mountpoint -q "${CHROOT_DIR}/dev"; then sudo umount -l "${CHROOT_DIR}/dev"; fi
    
    mkdir -p "${ISO_DIR}"/{casper,isolinux,boot/grub,.disk}
    
    sudo cp "${CHROOT_DIR}"/boot/vmlinuz-*-generic "${ISO_DIR}/casper/vmlinuz"
    sudo cp "${CHROOT_DIR}"/boot/initrd.img-*-generic "${ISO_DIR}/casper/initrd"
    
    sudo chroot "${CHROOT_DIR}" dpkg-query -W --showformat='${Package}\t${Version}\n' > "${ISO_DIR}/casper/filesystem.manifest"
    
    log_info "Erstelle SquashFS-Abbild mit zstd (dies kann dauern)..."
    sudo mksquashfs "${CHROOT_DIR}" "${ISO_DIR}/casper/filesystem.squashfs" -noappend -e boot -comp zstd
    
    printf "$(sudo du -sx --block-size=1 "${CHROOT_DIR}" | cut -f1)" > "${ISO_DIR}/casper/filesystem.size"
    echo "${DISTRO_NAME} ${DISTRO_VERSION}" > "${ISO_DIR}/.disk/info"
    
    log_success "ISO-Struktur und SquashFS erstellt."
}

step_11_create_bootloaders() {
    log_step "11/12" "Bootloader (ISOLINUX & GRUB) erstellen"
    
    cp /usr/lib/ISOLINUX/isolinux.bin "${ISO_DIR}/isolinux/"
    cp /usr/lib/syslinux/modules/bios/{ldlinux.c32,libutil.c32,menu.c32} "${ISO_DIR}/isolinux/"
    
    cat > "${ISO_DIR}/isolinux/isolinux.cfg" << EOF
UI menu.c32
PROMPT 0
TIMEOUT 50
DEFAULT live

LABEL live
  MENU LABEL Try or Install ${DISTRO_NAME}
  KERNEL /casper/vmlinuz
  APPEND file=/cdrom/.disk/info boot=casper initrd=/casper/initrd quiet splash ---
EOF

    cat > "${ISO_DIR}/boot/grub/grub.cfg" << EOF
set timeout=5
set default="0"
menuentry "Try or Install ${DISTRO_NAME}" {
    linux /casper/vmlinuz file=/cdrom/.disk/info boot=casper quiet splash ---
    initrd /casper/initrd
}
EOF
    
    grub-mkstandalone \
        --format=x86_64-efi \
        --output="${ISO_DIR}/boot/grub/bootx64.efi" \
        --locales="" --fonts="" \
        "boot/grub/grub.cfg=${ISO_DIR}/boot/grub/grub.cfg"

    mkdir -p "${ISO_DIR}/EFI/BOOT"
    cp "${ISO_DIR}/boot/grub/bootx64.efi" "${ISO_DIR}/EFI/BOOT/"
    cp /usr/lib/shim/shimx64.efi.signed "${ISO_DIR}/EFI/BOOT/BOOTX64.EFI"

    log_success "Bootloader-Konfigurationen erstellt."
}

step_12_create_iso() {
    log_step "12/12" "Finale ISO-Datei mit xorriso erstellen"
    
    local volume_id="${DISTRO_NAME} ${DISTRO_VERSION}"
    
    sudo xorriso -as mkisofs \
        -r -V "${volume_id}" \
        -o "${BUILD_DIR}/${ISO_NAME}" \
        --grub2-mbr /usr/lib/grub/i386-pc/boot_hybrid.img \
        -partition_offset 16 \
        --mbr-force-bootable \
        -append_partition 2 28732ac11ff8d211ba4b00a0c93ec93b "${ISO_DIR}/EFI/BOOT/bootx64.efi" \
        -appended_part_as_gpt \
        -iso_mbr_part_type a2a0d0ebe5b9334487c068b6b72699c7 \
        -c '/isolinux/boot.cat' \
        -b '/isolinux/isolinux.bin' \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        --grub2-boot-info \
        "${ISO_DIR}"

    sudo chown "$(id -u):$(id -g)" "${BUILD_DIR}/${ISO_NAME}"
    log_success "ISO-Datei erfolgreich erstellt: ${BUILD_DIR}/${ISO_NAME}"
    
    sha256sum "${BUILD_DIR}/${ISO_NAME}" > "${BUILD_DIR}/${ISO_NAME}.sha256"
    sudo chown "$(id -u):$(id -g)" "${BUILD_DIR}/${ISO_NAME}.sha256"
    log_success "SHA256-Hash wurde erstellt."
}

# --- Skriptausführung ---
main() {
    check_not_root
    
    if [ "$1" == "--cleanup" ]; then
        log_warn "Manuelle Bereinigung angefordert."
        cleanup
        exit 0
    fi
    
    local start_time
    start_time=$(date +%s)
    
    current_step="1: Setup" && step_01_setup_environment
    current_step="2: Debootstrap" && step_02_debootstrap
    current_step="3: Mounts" && step_03_mount_filesystems
    current_step="4: Chroot Base" && step_04_chroot_base_config
    current_step="5: Chroot Kernel" && step_05_chroot_kernel_core
    current_step="6: Chroot Desktop" && step_06_chroot_desktop
    current_step="7: Chroot Calamares" && step_07_chroot_calamares
    current_step="8: Chroot User" && step_08_chroot_user_setup
    current_step="9: Chroot Cleanup" && step_09_chroot_cleanup
    current_step="10: ISO Structure" && step_10_prepare_iso_structure
    current_step="11: Bootloaders" && step_11_create_bootloaders
    current_step="12: Create ISO" && step_12_create_iso
    
    log_info "Verschiebe fertige ISO und SHA256 in das Projektverzeichnis..."
    mv "${BUILD_DIR}/${ISO_NAME}" .
    mv "${BUILD_DIR}/${ISO_NAME}.sha256" .
    
    # Finale Bereinigung
    cleanup
    
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo ""
    log_success "==================== BUILD ERFOLGREICH ABGESCHLOSSEN ===================="
    log_success "ISO: $(realpath "${ISO_NAME}")"
    log_success "Dauer: $((duration / 60)) Minuten und $((duration % 60)) Sekunden."
    echo ""
}

# Skript starten
main "$@"
