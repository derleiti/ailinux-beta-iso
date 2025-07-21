# AILinux Beta ISO 🐧

**AILinux Beta ISO** ist ein Open‑Source‑Projekt, das eine minimalistische, leichtgewichtige ISO‑Distribution auf Debian/Ubuntu‑Basis bereitstellt – optimiert für Experimentierzwecke und schnelle Testinstallationen.

---

## 🚀 Features

- **Clean, minimal core**: Nur essentielle Pakete, ohne unnötige Bloatware.
- **Automatisierte Builds**: ISO wird über Skripte (`build.sh`, `clean.sh`) erstellt.
- **Branding‑Support**: Optionen für eigenes Logo und Texte, leicht anpassbar via `branding/`.
- **Git‑LFS Vorbereitung**: Keine großen Binärdateien im Repo, unterstützt sauberen Source‑Control‑Workflow.

---

## 🧪 Quick Start

### Repository klonen

```bash
git clone https://github.com/derleiti/ailinux-beta-iso.git
cd ailinux-beta-iso
ISO generieren
bash
Kopieren
Bearbeiten
./clean.sh    # bereitet die Build‑Umgebung vor
./build.sh    # baut die ISO
Am Ende findest du die erzeugte .iso im Build‑Verzeichnis.

📁 Verzeichnisstruktur
text
Kopieren
Bearbeiten
.
├── branding/              # Branding‑Assets (Bilder, Texte)
├── build.sh               # Erzeugt die ISO
├── clean.sh               # Bereinigt temporäre Dateien
├── prompt.txt             # Beispiel‑Prompt für Installer
├── README.md              # Dieses Dokument
├── SECURITY.md            # Sicherheitsrichtlinien für das Projekt
└── .gitignore             # Filtert große Binärdateien aus
🛠️ Entwicklung & Beiträge
Branding ändern: Assets in branding/ anpassen (Logo, Hintergrund, etc.).

Build‑Anpassungen: build.sh enthält die Hauptlogik zum ISO‑Erstellen.

Code‑Contributions: Fork → Feature‑Branch → Pull‑Request (mit Beschreibung).

💾 Deployment – ohne Git-LFS
Große ISO-Dateien bleiben aus dem Git‑Repo ausgeschlossen.
Optionen zum Bereitstellen:

GitHub Releases:
gh release create vX.Y.Z path/to/ailinux.iso --title "AILinux Beta X.Y.Z" --notes "Changelog..."

Eigener Server:
Beispiel: https://ailinux.me/downloads/ailinux.iso

📄 Lizenz & Sicherheit
Lizenz: Siehe LICENSE (üblicherweise MIT/BSD).

Sicherheitsrichtlinie: Siehe SECURITY.md.

📞 Support & Kontakt
Für Ideen, Bugs oder Support:

📩 Issues: Im GitHub‑Issue‑Tracker.

💬 Discussions: Für allgemeine Fragen oder Anwendungsfälle.

🛠️ Pull‑Requests willkommen!

✅ Status & To‑Do
✅ ISO‑Build funktioniert sauber

✅ README, SECURITY, Build‑Skripte vorhanden

🔲 Automatisierte Test‑Pipeline (z. B. CI/CD) auf To‑Do‑Liste

🔲 ISO‑Download bereitstellen via Releases oder Server

⚠️ Hinweis
AILinux Beta ISO ist ein Tool für schnelle Test‑Setups – nicht für produktive Nutzung.
build.sh erzeugt Standard‑ISO, sollte vor der Verteilung kontrolliert werden.

Viel Spaß beim Ausprobieren, Anpassen und Mitgestalten! 😊
— Markus (alias zombie, Entwickler & Build‑Master)
