AILinux 24.04 - Build System v10.7: Production Ready 🚀
Wir freuen uns, die Veröffentlichung von Version 10.7 unseres ISO-Build-Systems bekannt zu geben! Nach einer intensiven Phase der Entwicklung, des Debuggings und der Optimierung haben wir einen stabilen, robusten und hochautomatisierten Prozess erreicht, der es uns ermöglicht, qualitativ hochwertige AILinux-ISOs zu erstellen.

Dieses Release markiert den Übergang von einem experimentellen Skript zu einem produktionsreifen Werkzeug, das auf den besten Praktiken der Community und den offiziellen Methoden großer Distributionen wie Fedora und Ubuntu basiert.

✨ Highlights dieser Version
Das Build-Skript v10.7 ist das Ergebnis zahlreicher Verbesserungen und Korrekturen. Die wichtigsten Merkmale sind:

Maximale Boot-Kompatibilität: Durch eine sorgfältig konfigurierte xorriso-Befehlskette und manuell erstellte Boot-Images wird sowohl Legacy BIOS als auch modernes UEFI (inklusive GPT-Partitionierung) vollständig unterstützt. Die ISO ist damit Hybrid und direkt auf USB-Sticks schreibbar.

Stabilität nach Community-Vorbild: Wir haben die Konfigurationen an anerkannte Methoden (z.B. die "Fedora-Methode" für isohybrid) angepasst, um eine breite Kompatibilität mit verschiedenster Hardware und Bootloadern wie Ventoy zu gewährleisten.

Automatisierte Fehlervermeidung: Das Skript führt zahlreiche Selbstprüfungen durch, darunter:

Verifizierung der MBR- und EFI-Boot-Dateien.

Eine Größenwarnung für das filesystem.squashfs, um Probleme mit FAT32-formatierten USB-Sticks zu vermeiden.

Eine finale Integritätsprüfung des erstellten ISO-Abbilds.

Optimierte Performance: Durch den Einsatz der zstd-Kompression und die explizite Nutzung aller verfügbaren CPU-Kerne (-processors $(nproc)) wird der zeitaufwändigste Schritt – die Erstellung des SquashFS-Images – erheblich beschleunigt.

Produktionsreife Dokumentation: Das Skript ist nun ausführlich kommentiert und enthält am Ende eine Zusammenfassung mit SHA256-Prüfsumme, Testbefehlen für QEMU/KVM und wichtigen Hinweisen für Endanwender.

📜 Changelog (Der Weg zu v10.7)
v10.7: Finale Stabilitäts- und Verifizierungs-Checks hinzugefügt.

v10.6: isohdpfx.bin MBR-Template-Suche robust gemacht und filesystem.size für Casper ergänzt.

v10.2 - v10.5: Kritische xorriso-Fehler behoben, die durch fehlende Boot-Dateien und inkompatible Flags verursacht wurden.

v9.8 - v10.1: Das 4-GiB-Dateigrößenlimit von ISO9660 durch einen manuellen xorriso-Aufruf mit automatischer UDF-Unterstützung umgangen.

v9.5 - v9.7: Paketabhängigkeiten korrigiert (lupin-casper entfernt, libkpmcore11 auf libkpmcore13 aktualisiert).

v9.4: Korrekte Konfiguration des AILinux-Spiegelservers für alle Ubuntu- und AILinux-Pakete wiederhergestellt.

v9.0 - v9.3: Anfängliche Fehler im Calamares-Installer (unpackfs-Pfad) und Netzwerkprobleme im Chroot behoben.

v8.x: Basis-Skripte zusammengeführt und grundlegende Funktionalität hergestellt.

🚀 Erste Schritte
Klone das Repository oder lade die build.sh-Datei herunter.

Stelle sicher, dass alle Voraussetzungen (siehe Skript-Header) erfüllt sind.

(Optional) Platziere deine eigenen Bilder im branding-Verzeichnis.

Führe das Skript aus:

chmod +x build.sh
./build.sh

Nach Abschluss des Builds findest du die fertige ailinux-24.04-amd64.iso und eine SHA256-Prüfsumme in der finalen Ausgabe.

Ein riesiges Dankeschön an alle, die durch Tests und Feedback geholfen haben, diesen Meilenstein zu erreichen!
