# AILinux 24.04 Premium – AI-powered Linux Distro 🚀  
**Eine moderne, lokal KI-integrierte Live-Distribution auf Ubuntu 24.04 Basis**

[![Version](https://img.shields.io/badge/AILinux-24.04%20Premium-blue.svg)](https://ailinux.me)
[![Build](https://img.shields.io/badge/build-passing-brightgreen)]()
[![Status](https://img.shields.io/badge/status-beta-orange.svg)]()
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](./LICENSE)

---

## 📄 Über das Projekt

**AILinux** kombiniert die Stabilität von Ubuntu 24.04 mit einem **lokal nutzbaren KI-Systemassistenten**, der bei der Fehleranalyse, Systemdiagnose und Bedienung hilft – **vollständig offline-fähig**.

- 🧠 KI-Terminaltool `aihelp` (powered by Mixtral / Mistral API)
- 🖥️ KDE Plasma 6.x Desktop mit `kde-full` und SDDM Autologin
- 📦 Integrierte Apps: Firefox, Chrome, VLC, GIMP, VS Code, Wine, LibreOffice, Thunderbird, FileZilla, AILinux App
- 🛠 **FIXED** Calamares-Installer mit korrigierter Bootloader-Konfiguration
- 🔐 Secure Boot (shimx64.efi.signed), BIOS + UEFI Support
- 🧰 Entwickler-Tools: Python, Node.js, JDK, Git, Docker-ready
- 🎮 Gaming: WineHQ (Staging), Winetricks, Steam-kompatibel
- ⚡ **Schneller AILinux Mirror** für optimierte Package-Downloads

> **Zielgruppe:** Power-User, Admins, Entwickler, Forscher, KI-Fans & Bastler.

---

## 🔗 ISO Download

- 📥 [ailinux-24.04-premium-amd64.iso (5.1 GB)](https://ailinux.me/iso/ailinux-24.04-premium-amd64.iso)
- 🔐 [SHA256 Prüfsumme](https://ailinux.me/iso/ailinux-24.04-premium-amd64.iso.sha256)

---

## 🧠 KI-Integration: `aihelp`

```bash
aihelp "apt update schlägt fehl mit 'lock-frontend' – was tun?"
aihelp --log /var/log/syslog
aihelp --sysinfo
```

Konfiguriere deinen KI-Zugang in `.env`:
```env
MISTRALAPIKEY=dein_api_key
```

Nutzt Mixtral/Mistral-API, keine Cloudbindung – Datenschutz bleibt lokal steuerbar.

---

## 🛠 ISO selbst bauen

### Systemanforderungen:
- Ubuntu/Debian Hostsystem
- 15–50 GB freier Speicher  
- Root-Rechte (via sudo)
- Internet für Paket- & KI-Abhängigkeiten
- **Mixtral API Key** für KI-Integration

### 🔧 Build-Schritte:

```bash
# 1. Klone das Projekt
git clone https://github.com/derleiti/ailinux-beta-iso.git
cd ailinux-beta-iso

# 2. Abhängigkeiten installieren
sudo apt install -y debootstrap squashfs-tools xorriso grub-pc-bin grub-efi-amd64-bin \
    isolinux syslinux-common shim-signed mtools dosfstools gnupg git curl jq \
    python3 python3-pip python3-venv

# 3. .env für KI vorbereiten
cp .env.example .env
nano .env    # Trage MISTRALAPIKEY ein

# 4. Build starten
chmod +x build.sh
sudo ./build.sh
```

Die fertige ISO + SHA256 + ailinux-build-info.txt liegen im Projektverzeichnis.

---

## 🔧 Neue Features v21.0

### ✅ **Bootloader-Problem behoben**
- **Komplette Neukonfiguration** der Calamares Bootloader-Module
- Alle GRUB/EFI Abhängigkeiten werden vor Calamares installiert
- Enhanced Python Dependencies für Calamares Kompatibilität
- **Installation funktioniert jetzt fehlerfrei**

### ⚡ **AILinux Mirror Integration**
- **Automatische Mirror-Umstellung** nach Repository-Setup
- Schnellere Package-Downloads über `https://ailinux.me:8443/mirror/`
- Security Updates weiterhin über offiziellen Ubuntu Mirror
- **Robuste Fehlerbehandlung** bei Repository-Problemen

### 📦 **Explizite Paket-Installation**
Alle wichtigen Pakete werden jetzt explizit über `apt install` installiert:
- `vlc`, `gimp`, `libreoffice`
- `firefox`, `thunderbird`
- `ailinux-app` (falls im Repository verfügbar)
- `winehq-staging`, `winetricks`
- `google-chrome-stable`
- `code` (VS Code)

### 🍷 **Verbesserte Wine-Integration**
- Moderne GPG-Keyring Behandlung
- Wine Repository mit korrekter Signatur-Verifikation
- Fallback auf reguläres Wine bei Staging-Problemen

---

## 🧪 ISO testen

```bash
# QEMU/KVM Test
qemu-system-x86_64 -cdrom ailinux-24.04-premium-amd64.iso -m 4096 -enable-kvm

# Oder USB-Stick mit balenaEtcher beschreiben
```

---

## 📁 Projektstruktur

```
.
├── build.sh            # ISO-Erstellung (v21.0 - Bootloader FIXED)
├── clean.sh            # Cleanup nach Build-Fehlern
├── branding/           # Logos, Icons, Welcome-Grafiken
├── AILINUX_BUILD/      # temporäres Build-Verzeichnis
├── .env / .env.example # KI-Konfiguration (API-Key)
├── prompt.txt          # KI-Systemrolle für aihelp
├── push.sh             # Git Push mit PAT
└── README.md           # Dieses Dokument
```

---

## 📦 Enthaltene Software

| Kategorie | Anwendungen |
|-----------|-------------|
| **Desktop** | kde-full, SDDM, Konsole, Neofetch |
| **Web & Kommunikation** | Firefox, Google Chrome, Thunderbird |
| **Office** | LibreOffice Suite |
| **Multimedia** | VLC Media Player, GIMP |
| **Entwicklung** | VS Code, Git, Python 3, Node.js, JDK, Build-Essentials, FileZilla |
| **KI/Tools** | aihelp, ailinux-app (GUI optional) |
| **Windows Support** | winehq-staging, Winetricks |
| **Systemwerkzeuge** | GParted, Htop, Druckertreiber, Bluetooth |

---

## 🔧 Technische Verbesserungen

### **Robuste Repository-Konfiguration:**
- AILinux Repository Script Integration: `https://ailinux.me:8443/mirror/add-ailinux-repo.sh`
- Automatische Mirror-Umstellung für bessere Performance
- Intelligente Fallback-Mechanismen bei Repository-Fehlern

### **Enhanced Calamares Installation:**
- Vollständige Bootloader-Dependencies vor Installation
- Python-Pakete für Ubuntu 24.04 Kompatibilität
- Korrekte EFI/UEFI und BIOS Unterstützung
- Secure Boot mit shimx64.efi.signed

### **Verbesserte Paket-Installation:**
- Repository-Installation hat Priorität vor manuellen Downloads
- Intelligente Fallbacks für nicht verfügbare Pakete
- Robuste Dependency-Auflösung

---

## 💡 Claude Prompt zur Replikation

```text
Erstelle ein vollständiges ISO-Buildsystem in Bash zur Erstellung einer Live-ISO basierend auf Ubuntu 24.04. Die Distribution heißt AILinux und enthält:

- KDE Plasma Desktop (kde-full) mit SDDM Autologin
- FIXED Calamares Installer mit korrigierter Bootloader-Konfiguration
- Einen Live-Benutzer mit Desktop-Shortcuts
- CLI-Integration namens `aihelp` (Mixtral API via .env)
- AILinux Mirror Integration für schnellere Downloads
- Fähigkeit zur Log-Analyse, Systemdiagnose mit Markdown-Antwortstruktur
- zstd-komprimiertes SquashFS für kleinere ISO-Größe
- BIOS- & UEFI-Boot mit Secure Boot Support (shimx64.efi.signed)
- Eine ISO-Datei mit SHA256-Checksum und detaillierter Build-Info
- Robuste Fehlerbehandlung und Repository-Management

Das Script muss Ubuntu 24.04 Paket-Namen korrekt verwenden, .env validieren, und bei kritischen Fehlern mit AI-Debugging unterstützen.
```

---

## 🔐 Lizenz

**MIT License**  
© 2024–2025 @derleiti / AILinux Project

---

## 🤝 Mitwirken

Pull Requests, Bug-Reports & Fragen willkommen!

- 🌐 **Website:** https://ailinux.me
- 🐙 **GitHub:** github.com/derleiti/ailinux-beta-iso
- 💬 **Issues:** Für Bootloader-Probleme, Repository-Fehler oder Build-Fragen

---

**AILinux – The Intelligent Linux Environment. Powered by you. Enhanced by AI.**

✅ **v21.0 Ready** – Bootloader Issues Resolved | Mirror Optimization | Enhanced Stability
