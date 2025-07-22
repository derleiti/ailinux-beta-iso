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
- 🛠 Calamares-Installer & Live-Boot
- 🔐 Secure Boot (shimx64.efi.signed), BIOS + UEFI
- 🧰 Entwickler-Tools: Python, Node.js, JDK, Git, Docker-ready
- 🎮 Gaming: WineHQ (Staging), Winetricks, Steam-kompatibel

> **Zielgruppe:** Power-User, Admins, Entwickler, Forscher, KI-Fans & Bastler.

---

## 🔗 ISO Download

- 📥 [ailinux-24.04-premium-amd64.iso (5.1 GB)](https://ailinux.me/iso/ailinux-24.04-premium-amd64.iso)
- 🔐 [SHA256 Prüfsumme](https://ailinux.me/iso/ailinux-24.04-premium-amd64.iso.sha256)

---

## 🧠 KI-Integration: `aihelp`

```bash
aihelp "apt update schlägt fehl mit 'lock-frontend' – was tun?"
aihelp --log /var/log/syslog
aihelp --sysinfo
Konfiguriere deinen KI-Zugang in .env:

env
Kopieren
Bearbeiten
MISTRALAPIKEY=dein_api_key
Nutzt Mixtral/Mistral-API, keine Cloudbindung – Datenschutz bleibt lokal steuerbar.

🛠 ISO selbst bauen
Systemanforderungen:

Ubuntu/Debian Hostsystem

15–50 GB freier Speicher

Root-Rechte (via sudo)

Internet für Paket- & KI-Abhängigkeiten

🔧 Schritte:
bash
Kopieren
Bearbeiten
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
Die fertige ISO + SHA256 + ailinux-build-info.txt liegen im Projektverzeichnis.

🧪 ISO testen
bash
Kopieren
Bearbeiten
qemu-system-x86_64 -cdrom ailinux-24.04-premium-amd64.iso -m 4096 -enable-kvm
Oder mit balenaEtcher auf USB-Stick schreiben.

📁 Projektstruktur
bash
Kopieren
Bearbeiten
.
├── build.sh            # ISO-Erstellung (automatisiert)
├── clean.sh            # Cleanup nach Build-Fehlern
├── branding/           # Logos, Icons, Welcome-Grafiken
├── AILINUX_BUILD/      # temporäres Build-Verzeichnis
├── .env / .env.example # KI-Konfiguration (API-Key)
├── prompt.txt          # KI-Systemrolle
├── push.sh             # Git Push mit PAT
└── README.md           # Dieses Dokument
📦 Enthaltene Software
Kategorie	Anwendungen
Desktop	kde-full, SDDM, Konsole, Neofetch
Web & Kommunikation	Firefox, google-chrome-stable, Thunderbird
Office	LibreOffice
Multimedia	VLC Media Player, GIMP
Entwicklung	VS Code, Git, Python 3, Node.js, JDK, Build-Essentials, FileZilla
KI/Tools	aihelp, ailinux-app
Windows Support	winehq-staging, Winetricks
Systemwerkzeuge	GParted, Htop, Druckertreiber, Bluetooth

💡 Claude Prompt zur Replikation
text
Kopieren
Bearbeiten
Erstelle ein ISO-Buildsystem basierend auf Ubuntu 24.04, das KDE Plasma (`kde-full`), Calamares mit Branding, Autologin-Live-User, ein CLI-Tool namens `aihelp` (Mixtral API via .env), systemweite Diagnosefunktionen und zstd-komprimiertes SquashFS integriert. ISO muss BIOS + UEFI + Secure Boot (shimx64.efi.signed) unterstützen und am Ende ISO + SHA256 + Build-Info erzeugen.
🔐 Lizenz
MIT License
© 2024–2025 @derleiti / AILinux Project

🤝 Mitwirken
Pull Requests, Bug-Reports & Fragen willkommen!
🌐 Website: https://ailinux.me
🐙 GitHub: github.com/derleiti/ailinux-beta-iso

AILinux – The Intelligent Linux Environment. Powered by you. Enhanced by AI.

yaml
Kopieren
Bearbeiten

---

✅ Bereit für `git add README.md && git commit -m "Update README mit App-Liste"`  
Sag Bescheid, wenn du:

- eine **englische Version**
- eine **`index.html`** mit gleichem Inhalt
- oder eine automatisch generierte **Release-Notiz für GitHub Releases** willst!
