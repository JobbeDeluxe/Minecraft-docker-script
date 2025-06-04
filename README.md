# Minecraft Docker Server Updater

Dieses Bash-Skript automatisiert den Update-Prozess eines Minecraft-Servers im Docker-Container. Es bietet Funktionen für Backup, Plugin-Verwaltung und das Neustarten des Containers mit neuer Version.

## 🔧 Funktionen

- **Backup erstellen**: Komprimiert den aktuellen Serverstand und speichert ihn im Backup-Verzeichnis.
- **Plugins aktualisieren**: Lädt Plugins anhand einer `plugins.txt`-Liste automatisch herunter.
- **Alte Plugins sichern/löschen**: Verschiebt bestehende `.jar`-Dateien in ein Archiv (`plugins/old_version`).
- **Docker-Container verwalten**: Stoppt, entfernt und startet den Server-Container mit neuer Konfiguration.
- **Protokollierung**: Alle Aktionen werden in `update_log.txt` gespeichert.

## 📦 Voraussetzungen

- Betriebssystem: Linux
- Abhängigkeiten:
  - `docker`
  - `curl`
  - `jq`
  - `wget`
- Schreibrechte im angegebenen `DATA_DIR`

## ▶️ Verwendung

1. Skript ausführen:

   ```bash
   bash update_server_neu3.bash
   ```

2. Interaktive Abfragen beantworten:

   - Pfad zum Minecraft-Datenverzeichnis (Standard: `/opt/minecraft_server`)
   - Minecraft-Version (z. B. `1.20.1`)
   - RAM-Zuweisung (z. B. `6G`)
   - Server-Typ (`PAPER`, `FABRIC`, etc.)
   - Backup erstellen? (`ja` / `nein`)
   - Plugins aktualisieren? (`ja` / `nein`)
   - Plugins löschen und sichern? (`ja` / `nein`)
   - Docker starten? (`ja` / `nein`)

3. Pluginliste vorbereiten:

   Erstelle eine Datei `plugins.txt` im Datenverzeichnis mit folgendem Format:

   ```
   # Format: <Plugin-Name> <Download-URL>
   # Beispiel:
   ViaVersion https://github.com/ViaVersion/ViaVersion/releases/latest
   ```

   Plugins werden bei GitHub automatisch über die API oder alternativ direkt heruntergeladen.

## 📁 Verzeichnisstruktur (Beispiel)

```
/opt/minecraft_server/
├── backups/
├── plugins/
│   ├── old_version/
│   ├── manuell/
├── plugins.txt
├── update_log.txt
```

## 🛑 Hinweise

- Führe das Skript mit ausreichenden Berechtigungen aus (z. B. per `sudo`), damit `docker`-Befehle funktionieren.
- Das Skript stoppt den Server automatisch, um Plugins zu sichern und Backups zu erstellen.
- Das `DATA_DIR` muss beschreibbar sein.

---

MIT Lizenz – frei zur Anpassung und Nutzung.
