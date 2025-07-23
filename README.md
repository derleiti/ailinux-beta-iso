🚀 AILinux ISO-Builder
📆 Projekt-Update: 23. Juli 2025
🔧 Version: v25.08
🎯 Ziel: Erstelle deine eigene KI-integrierte Live-Distribution basierend auf Ubuntu 24.04 – vollständig offlinefähig und mit intelligenter Systemunterstützung.

🔍 Projektüberblick
AILinux kombiniert die Stabilität von Ubuntu 24.04 mit einem lokal nutzbaren KI-Assistenten zur Systemdiagnose, Fehleranalyse und Bedienungshilfe – ganz ohne Cloud-Zwang.
Dank Calamares-Installer, KDE Plasma Desktop, Offline-Tools und lokaler KI bietet AILinux ein starkes Fundament für Power-User, Entwickler, Admins und Forscher.

🧠 KI-Funktionen
aihelp: Dein Terminal-KI-Helfer – powered by Mixtral API (lokal steuerbar via .env)

Analyse von Logs, Diagnose von Systemfehlern, Hilfe zu Terminal-Befehlen – direkt per CLI

Beispiele:

bash
Kopieren
Bearbeiten
aihelp "apt update schlägt fehl mit 'lock-frontend' – was tun?"
aihelp --log /var/log/syslog
aihelp --sysinfo
🖥️ Desktop-Umgebung
KDE Plasma 6.x, vollständige kde-full-Installation

Autologin via SDDM

Vorkonfigurierte Shortcuts und Themes

📦 Enthaltene Software
Kategorie	Anwendungen
Web	Firefox, Google Chrome, Thunderbird
Office	LibreOffice, GIMP, PDF Tools
Multimedia	VLC, GIMP
Entwicklung	VS Code, Git, Python 3, Node.js, JDK, FileZilla
KI/Tools	aihelp, AILinux App (GUI)
Windows Support	WineHQ (Staging), Winetricks
System	GParted, Htop, Bluetooth, Drucker-Support

🔐 Sicherheit & Boot
UEFI + BIOS-Support mit Secure Boot (shimx64.efi.signed)

Vollständige GRUB-Konfiguration für Calamares

Fallback-fähige Repository- und Key-Verwaltung

🌍 Repositories & Mirror
Eigener schneller Mirror: https://ailinux.me:8443/mirror/

Automatischer Fallback bei Netzwerkproblemen

Integration per Skript: add-ailinux-repo.sh

🛠 Projektstruktur (Auszug)
bash
Kopieren
Bearbeiten
.
├── build.sh            # Haupt-Buildskript
├── clean.sh            # Aufräumen bei Build-Fehlern
├── branding/           # Installer-Grafiken & Hintergrundbilder
├── .env / .env.example # API-Key-Konfiguration für KI
├── prompt.txt          # Prompt für aihelp
├── push.sh             # Git Push mit PAT-Eingabe
├── AILINUX_BUILD/      # Temporäre Build-Daten
└── README.md           # Diese Datei
🏗️ ISO selbst bauen
🔧 Voraussetzungen
Ubuntu/Debian-Hostsystem

15–50 GB freier Speicherplatz

Root-Rechte (sudo)

Internetverbindung

Mixtral API Key (für aihelp)

🧪 Schritte
bash
Kopieren
Bearbeiten
# 1. Repository klonen
git clone https://github.com/derleiti/ailinux-beta-iso.git
cd ailinux-beta-iso

# 2. Abhängigkeiten installieren
sudo apt install -y debootstrap squashfs-tools xorriso grub-pc-bin grub-efi-amd64-bin \
  isolinux syslinux-common shim-signed mtools dosfstools gnupg git curl jq \
  python3 python3-pip python3-venv

# 3. KI konfigurieren
cp .env.example .env
nano .env   # MISTRALAPIKEY eintragen

# 4. Build starten
chmod +x build.sh
sudo ./build.sh
👉 Die ISO, die Prüfsumme und die Build-Info-Datei findest du danach im Projektverzeichnis.

🔬 Build Highlights (v25.08)
✅ Calamares Bootloader Fix (GRUB vorinstalliert)

✅ AILinux Mirror Integration mit intelligenter Fallback-Logik

✅ Zstd-komprimiertes SquashFS für kleinere ISO-Größe

✅ aihelp + Mixtral KI (CLI-basiert, lokal steuerbar)

✅ Push-Skript mit PAT-Eingabe für einfaches Git-Handling

✅ ISO-Validierung per SHA256

💡 Claude Prompt zur Replikation
txt
Kopieren
Bearbeiten
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
📥 Download & Test
ISO: ailinux-24.04-premium-amd64.iso (5.1 GB)

SHA256: siehe ailinux-build-info.txt

🔄 ISO testen
bash
Kopieren
Bearbeiten
# QEMU
qemu-system-x86_64 -cdrom ailinux-24.04-premium-amd64.iso -m 4096 -enable-kvm

# Alternativ: Balena Etcher für USB-Stick
🔐 Lizenz
MIT License
© 2024–2025 @derleiti / AILinux Project

💬 Feedback & Mitwirkung
Pull Requests, Bug Reports und Feature-Wünsche sind willkommen!
🌐 ailinux.me
🐙 GitHub

