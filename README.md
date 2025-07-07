# Minecraft Docker Server Updater & Verwalter

Dieses Bash-Skript automatisiert die Verwaltung eines Minecraft-Servers im Docker-Container. Es bietet eine interaktive Oberfläche für Updates, Backups, Wiederherstellungen und Plugin-Verwaltung. Ideal für private und produktive Serverumgebungen.

## 🔧 Funktionen

- **Backup erstellen**: Komprimiert das aktuelle Serververzeichnis (`DATA_DIR`) und speichert es unter `backups/`. Fortschritt und Größe werden live angezeigt.
- **Backup wiederherstellen**: Listet vorhandene Backups sortiert nach Datum und ermöglicht gezielte Wiederherstellung.
- **Plugins aktualisieren**: Lädt Plugins anhand einer `plugins.txt`-Liste automatisch herunter (GitHub & Direkt-Links).
- **Alte Plugins sichern/löschen**: Bestehende `.jar`-Dateien werden nach `plugins/old_version` verschoben.
- **Docker-Container verwalten**: Stoppt, entfernt und startet den Server-Container mit angepasster Konfiguration.
- **Server neu initialisieren**: Löscht die Welten und Plugins vollständig und setzt das Serververzeichnis zurück.
- **Protokollierung**: Alle Aktionen werden mit Zeitstempel in `update_log.txt` dokumentiert.

## 📦 Voraussetzungen

- Betriebssystem: Linux
- Abhängigkeiten:
  - `docker`
  - `curl`
  - `jq`
  - `wget`
- Schreibrechte im angegebenen `DATA_DIR`

## ▶️ Verwendung

1. Skript starten:

   ```bash
   bash start_minecraft.sh
   ```

2. Interaktive Abfragen beantworten:

   - Soll ein **neuer Server initialisiert** werden? (löscht Welten und Plugins)
   - Pfad zum Minecraft-Datenverzeichnis (Standard: `/opt/minecraft_server`)
   - Minecraft-Version (z. B. `1.20.1`)
   - RAM-Zuweisung (z. B. `6G`)
   - Server-Typ (`PAPER`, `FABRIC`, etc.)
   - Backup erstellen? (`ja` / `nein`)
   - Backup wiederherstellen? (`ja` / `nein`)
   - Plugins aktualisieren? (`ja` / `nein`)
   - Plugins löschen und sichern? (`ja` / `nein`)
   - Docker-Container starten? (`ja` / `nein`)

3. Pluginliste vorbereiten:

   Lege im `DATA_DIR` eine Datei `plugins.txt` mit folgendem Format an:

   ```
   # Format: <Plugin-Name> <Download-URL>
   # Beispiel:
   ViaVersion https://github.com/ViaVersion/ViaVersion/releases/latest
   ```

   Bei GitHub-Links wird die API verwendet. Falls dies fehlschlägt, erfolgt ein Fallback auf Direkt-Download.

## 🔄 Wiederherstellung

Bei Auswahl der Wiederherstellung (`ja`) zeigt das Skript eine Liste vorhandener `.tar.gz`-Backups mit Alter in Tagen an. Nach Auswahl (1–N) wird das entsprechende Backup in das Datenverzeichnis entpackt und vorhandene Welten/Plugins bereinigt.

## 📁 Beispiel-Verzeichnisstruktur

```
/opt/minecraft_server/
├── backups/
│   ├── backup_20240601_1530.tar.gz
├── plugins/
│   ├── old_version/
│   ├── manuell/
│   ├── ...
├── plugins.txt
├── update_log.txt
├── world/
├── world_nether/
├── world_the_end/
```

## 🛑 Hinweise

- Das Skript benötigt root- oder docker-fähige Rechte (z. B. via `sudo`).
- Der Server wird während Backup, Restore und Updates gestoppt.
- Weltverzeichnisse und Plugins können bei Initialisierung gelöscht werden – Vorsicht!

---

MIT Lizenz – frei zur Nutzung, Erweiterung und Weitergabe.
