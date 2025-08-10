# Minecraft Docker Server Updater & Verwalter

Dieses Bash-Skript automatisiert die Verwaltung eines Minecraft-Servers im Docker-Container. Es bietet eine interaktive Oberfläche für Updates, Backups, Wiederherstellungen und Plugin-Verwaltung – ideal für private und produktive Serverumgebungen.

## 🔧 Funktionen

- **Eingabe-History**: Merkt sich alle bisherigen Eingaben (z. B. RAM, Version, Server-Typ etc.) und schlägt sie beim nächsten Mal automatisch vor.
- **Backup erstellen**: Komprimiert das aktuelle Serververzeichnis (`DATA_DIR`) und speichert es unter `backups/`. Fortschritt und Größe werden live angezeigt.
- **Backup wiederherstellen**: Listet vorhandene Backups sortiert nach Datum und ermöglicht gezielte Wiederherstellung.
- **Plugins aktualisieren**: 
  - Erkennt **nackte GitHub-Repo-Links** (z. B. `https://github.com/ViaVersion/ViaVersion`) automatisch und lädt die **neueste Release-JAR** per GitHub API.
  - Unterstützt **Direkt-Links von Fremdseiten** (z. B. Geyser/Floodgate-Downloads).
  - **CoreProtect Build** aus dem **Branch `master`** inklusive automatischer **`plugin.yml`-Korrektur** (`branch: developement`), damit das Plugin startet.
  - **Auswahlmenü bei Fehlschlägen**: Abbrechen / ohne fehlende Plugins starten / alte Plugins behalten und nur neue drüberkopieren.
  - **Manuelle Plugins** (Ordner `plugins/manuell`) werden zusätzlich übernommen.
- **Alte Plugins sichern/löschen**: Bestehende `.jar`-Dateien werden nach `plugins/old_version` verschoben.
- **Docker-Container verwalten**: Stoppt, entfernt und startet den Server-Container mit angepasster Konfiguration.
- **Server neu initialisieren**: Löscht die Welten und Plugins vollständig und setzt das Serververzeichnis zurück.
- **Protokollierung**: Alle Aktionen werden mit Zeitstempel in `update_log.txt` dokumentiert.
- **History-Verwaltung**: Mit `--history` können alte Eingaben eingesehen oder gelöscht werden.
- **Hilfefunktion**: Mit `--help` oder `-h` wird eine kurze Übersicht angezeigt.

## 📦 Voraussetzungen

- **Betriebssystem:** Linux
- **Abhängigkeiten (Host):**
  - `docker`
  - `curl`, `wget`, `jq`
  - `unzip`, `sed`, `awk`
  - *(optional)* `mvn` (Maven) – **nicht erforderlich**, wenn Docker verfügbar ist; das Skript nutzt sonst automatisch einen Maven-Docker-Container (`maven:3.9-eclipse-temurin-21`).
- **Rechte:** Schreibrechte im angegebenen `DATA_DIR` und Docker-Rechte (z. B. via `sudo`).
- *(optional)* **GitHub-Token**: `export GITHUB_TOKEN=...` reduziert API-Rate-Limits bei vielen GitHub-Plugins.

## ▶️ Verwendung

### 1) Skript starten

```bash
sudo bash start_minecraft.sh
```

> **Hinweis:** Der Pfad zum Minecraft-Datenverzeichnis (`DATA_DIR`) wird **als Erstes** abgefragt. **Selbst wenn** du `--help` oder `--history` übergibst, erfolgt die Abfrage zuerst.

### 2) Interaktive Abfragen beantworten

- Pfad zum Minecraft-Datenverzeichnis (Standard: `/opt/minecraft_server`)
- Soll ein neuer Server initialisiert werden?
- Minecraft-Version (z. B. `LATEST`, `1.21.1`)
- RAM-Zuweisung (z. B. `6G`)
- Server-Typ (z. B. `PAPER`, `SPIGOT`, `VANILLA`)
- Backup erstellen? (`ja`/`nein`)
- Backup wiederherstellen? (`ja`/`nein`)
- Plugins aktualisieren? (`ja`/`nein`)
- Plugins löschen und sichern? (`ja`/`nein`)
- Docker-Container starten? (`ja`/`nein`)

> Deine Antworten werden automatisch gespeichert und bei der nächsten Ausführung vorgeschlagen.

## 🔌 `plugins.txt` – Format & Beispiele

Lege im `DATA_DIR` eine Datei `plugins.txt` an. **Eine Zeile entspricht einem Plugin**:

```text
<Plugin-Name> <Download-Quelle>
```

Unterstützte Quellen:

- **GitHub-Repo-Link** (nackt):  
  Das Skript ermittelt automatisch die neueste Release-JAR per GitHub API.  
  Beispiel:
  ```text
  ViaVersion https://github.com/ViaVersion/ViaVersion
  ViaBackwards https://github.com/ViaVersion/ViaBackwards
  ```

- **Direkt-Download von Fremdseiten** (z. B. Geyser/Floodgate):  
  ```text
  Geyser-Spigot https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest/downloads/spigot
  floodgate-spigot https://download.geysermc.org/v2/projects/floodgate/versions/latest/builds/latest/downloads/spigot
  ```

- **CoreProtect aus Source bauen** (Branch `master` + automatischer `plugin.yml`-Patch):  
  ```text
  CoreProtect build:master
  ```

> **Tipp:** Kommentiere Beispielzeilen, die du nicht verwenden willst, mit `#` aus.  
> Beim ersten Lauf erzeugt das Skript eine Vorlage mit **aktivem** CoreProtect-Build und kommentierten Beispiel-Plugins.

## 🧱 CoreProtect-Build – Details

- Source wird aus `https://github.com/PlayPro/CoreProtect` (Branch `master`) geladen.
- Vor dem Build wird `Desktop/CoreProtect/src/main/resources/plugin.yml` automatisch angepasst:  
  `branch: ${project.branch}` → **`branch: developement`** (notwendig, damit das Plugin startet).
- Build erfolgt mit Maven:
  - Wenn `mvn` lokal vorhanden ist: lokaler Build.
  - Andernfalls: Build in Docker (`maven:3.9-eclipse-temurin-21`).  
    *(Optional schneller)*: Maven-Cache mounten  
    ```bash
    docker run ... -v "$HOME/.m2":/root/.m2 maven:3.9-eclipse-temurin-21 mvn -q -DskipTests package
    ```

## 🧩 Verhalten bei Download-/Build-Fehlern

Wenn ein oder mehrere Plugins **nicht** geladen/gebaut werden konnten, erscheint ein Auswahlmenü:

1. **Abbrechen** – keine Änderungen an den vorhandenen Plugins.
2. **Weiter ohne fehlgeschlagene Plugins** – alte Plugins werden ersetzt, aber die fehlgeschlagenen weggelassen.
3. **Alte behalten, neue drüberkopieren** – vorhandene Plugins bleiben erhalten; nur erfolgreiche Downloads/Builds werden zusätzlich kopiert/überschrieben.

## 🔁 Eingabe-History verwalten

```bash
bash start_minecraft.sh --history
```

## ❓ Hilfe anzeigen

```bash
bash start_minecraft.sh --help
```

## 🔄 Wiederherstellung

Bei Auswahl der Wiederherstellung (`ja`) zeigt das Skript eine Liste vorhandener `.tar.gz`-Backups mit Alter in Tagen an. Nach Auswahl wird das Backup in `DATA_DIR` entpackt.

## 📁 Beispiel-Verzeichnisstruktur

```text
/opt/minecraft_server/
├── backups/
│   ├── backup_20240601_1530.tar.gz
├── plugins/
│   ├── old_version/
│   ├── manuell/
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
- Eingaben werden in `~/.minecraft_script_history` gespeichert.
- GitHub-API ist ohne Token auf ~60 Requests/Stunde begrenzt. Bei vielen Plugins optional `GITHUB_TOKEN` setzen.

---

MIT Lizenz – frei zur Nutzung, Erweiterung und Weitergabe.
