# 🐧 AILinux Beta ISO – Build Environment

Dies ist das **offizielle Build-Repository** für die **AILinux ISO**, basierend auf **Ubuntu 24.04 (Noble Numbat)** mit:

- 🖥️ **KDE Plasma 6.3 Desktop**
- 🔐 **Secure Boot & GRUB**
- 🧠 **AI-Terminal-Assistent `aihelp` (Mixtral API)**
- 🛠️ **Calamares Installer mit Branding & Fixes**
- 🌐 **Lokalem APT-Mirror (`archive.ailinux.me`)**
- 🚀 **Vollständig offline installierbar**

---

## 🎯 Ziel

Dieses Repository enthält das Skript `build.sh`, das automatisch eine vollständige, **bootfähige Live-ISO von AILinux** erzeugt – inklusive:

- Eigener **APT-Mirror**: `http://ailinux.me:8443/mirror/`
- **GPG-signierte Paketquellen** (trennung `ubuntu-keyring` + `ailinux.gpg`)
- **AI-Funktionen** (lokal oder API-basiert über `.env`)
- **UEFI + BIOS Bootloader-Support**
- **Komplette Offline-Installierbarkeit**
- **Automatische Build-Metadaten-Erzeugung**

---

## 🚀 Features der ISO

| Feature | Beschreibung |
|--------|--------------|
| ✅ KDE Plasma Desktop | KDE 6.3, modern, minimal |
| ✅ Calamares Installer | mit Branding & Bootloader-Fixes |
| ✅ AI-Terminal `aihelp` | über Mixtral API steuerbar (`.env`) |
| ✅ Secure Boot Support | mit `shimx64.efi.signed` & `GRUB` |
| ✅ Vollständige Offline-Installation | kein Netzwerk nötig |
| ✅ Lokaler Mirror | `http://ailinux.me:8443/mirror/` |
| ✅ GPG-Management | Ubuntu-Keyring + AILinux-Key getrennt |
| ✅ Fallback-Tools | `ai_debugger` bei Buildfehlern |
| ✅ Build-Info | `ailinux-build-info.txt` wird automatisch erzeugt |

---

## 🧠 AI-gesteuerter Buildprozess (Claude Flow)

AILinux nutzt **Claude Flow Swarm Execution**, um `build.sh` automatisiert zu generieren, testen und verbessern.

### Vorteile:
- Parallele Task-Ausführung (via `BatchTool`)
- Rollenbasierte Agenten: `coder`, `tester`, `coordinator`, `reviewer`
- Automatisiertes Debugging bei Fehlern
- Claude verwendet die Dateien `prompt.txt`, `CLAUDE.md`, `qa-recommendations.md`, etc. als Entscheidungsgrundlage

---

## ⚙️ Verwendung

### 1. Voraussetzungen installieren

```bash
sudo apt install debootstrap squashfs-tools grub-pc-bin grub-efi-amd64-bin xorriso \
  syslinux-utils isolinux dosfstools mtools ubuntu-keyring gnupg2 python3 rsync
Optional: .env mit MISTRALAPIKEY=... für AI-Funktionen (aihelp, ai_debugger)

2. ISO erstellen
bash
Kopieren
Bearbeiten
chmod +x build.sh
sudo ./build.sh
Die fertige ISO liegt anschließend im Ordner output/.

🛠 Bekannte Probleme & Lösungen
❗ GRUB-Installation schlägt fehl (Calamares-Modul)
Mögliche Ursachen:

shimx64.efi.signed fehlt

/boot/efi nicht korrekt eingebunden

Secure Boot aktiviert aber nicht unterstützt

UEFI vs BIOS-Mismatch

Lösungen im build.sh:

Automatisches grub-install --no-nvram

Optionales efibootmgr & systemd-boot-Fallback

Modul ai_debugger zur Build-Fehlersuche

📁 Wichtige Dateien
Datei	Zweck
build.sh	Hauptskript zum ISO-Build
prompt.txt	Claude Flow Prompt für Swarm
CLAUDE.md	Kontextausgaben von Claude-Flow
ailinux-build-info.txt	Build-Zeitpunkt, Versionen, Checksummen
branding/	Alle Logos, Installer-Grafiken, Slideshow
99-force-overwrite	APT-Workaround bei Dateikonflikten
install.sh	Minimales Repo-Setup im Live-System (für Chroot)

📦 Veröffentlichte ISO
🔗 AILinux Alpha ISO (Download)

🧑‍💻 Lizenz
MIT License
© 2024–2025 Markus Leitermann

☁ Hinweis
Die ISO ist vollständig offline nutzbar.
Alle Paketquellen befinden sich im eingebauten APT-Mirror (archive.ailinux.me) und sind GPG-signiert.

🐾 Brumo sagt:
„☕ Kaffee rein, Build starten, ISO genießen.
Und wenn’s kracht: einfach Nova fragen!“ 🐻

bash
Kopieren
Bearbeiten

Wenn du willst, erstelle ich dir direkt ein `write_readme.sh`, das diesen Text in die Datei `README.md` schreibt. Sag einfach:

**„Mach mir ein Auto-Write für README.md“**  
Dann generiere ich dir das vollständige Bash-Skript dazu.

Bereit? 😄
