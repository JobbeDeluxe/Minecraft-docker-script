#!/bin/bash

# === Minecraft Docker Update-, Backup- und Restore-Skript ===

# === Konfigurationsdatei für History ===
HISTORY_FILE="${HOME}/.minecraft_script_history"

# Funktion zum Speichern der History
save_history() {
    local key="$1"
    local value="$2"
    touch "$HISTORY_FILE"
    grep -v "^${key}=" "$HISTORY_FILE" > "${HISTORY_FILE}.tmp" 2>/dev/null || true
    echo "${key}=${value}" >> "${HISTORY_FILE}.tmp"
    mv "${HISTORY_FILE}.tmp" "$HISTORY_FILE"
}

# Funktion zum Laden der History
load_history() {
    local key="$1"
    if [[ -f "$HISTORY_FILE" ]]; then
        grep "^${key}=" "$HISTORY_FILE" | cut -d'=' -f2- | tail -1
    fi
}

# Erweiterte read-Funktion mit History-Unterstützung
read_with_history() {
    local prompt="$1"
    local default="$2"
    local history_key="$3"
    local user_input
    local last_value
    last_value=$(load_history "$history_key")
    if [[ -n "$last_value" && "$last_value" != "$default" ]]; then
        printf "%s [Letzte Eingabe: %s] (Standard: %s): " "$prompt" "$last_value" "$default" >&2
        read user_input
        [[ -z "$user_input" ]] && user_input="$last_value"
    else
        printf "%s (Standard: %s): " "$prompt" "$default" >&2
        read user_input
    fi
    [[ -z "$user_input" ]] && user_input="$default"
    if [[ "$user_input" != "$default" ]]; then
        save_history "$history_key" "$user_input"
    fi
    echo "$user_input"
}

# Erweiterte read-Funktion für Ja/Nein-Fragen mit History
read_yesno_with_history() {
    local prompt="$1"
    local history_key="$2"
    local user_input
    local last_value
    last_value=$(load_history "$history_key")
    if [[ -n "$last_value" ]]; then
        printf "%s [Letzte Eingabe: %s] (ja/nein): " "$prompt" "$last_value" >&2
        read user_input
        [[ -z "$user_input" ]] && user_input="$last_value"
    else
        printf "%s (ja/nein): " "$prompt" >&2
        read user_input
    fi
    case "$user_input" in
        [jJyY]|[jJ][aA]|[yY][eE][sS]) user_input="ja" ;;
        [nN]|[nN][eE][iI][nN]|[nN][oO]) user_input="nein" ;;
        *) user_input="nein" ;;
    esac
    save_history "$history_key" "$user_input"
    echo "$user_input"
}

# === Pfad abfragen (vor log-Initialisierung) ===
echo "=== Minecraft Server Management Script ===" >&2
DATA_DIR=$(read_with_history "Pfad zum Minecraft-Datenverzeichnis" "/opt/minecraft_server" "DATA_DIR")

# === Initialisierung nach DATA_DIR ===
SERVER_NAME="mc"
BACKUP_DIR="${DATA_DIR}/backups"
PLUGIN_DIR="${DATA_DIR}/plugins"
PLUGIN_CONFIG="${DATA_DIR}/plugins.txt"
DOCKER_IMAGE="itzg/minecraft-server"
LOG_FILE="${DATA_DIR}/update_log.txt"

mkdir -p "$DATA_DIR"

log() {
    printf "%s - %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" | tee -a "$LOG_FILE"
}

cleanup() {
    log "Script wurde abgebrochen."
    exit 1
}
trap cleanup SIGINT SIGTERM

check_dependencies() {
    local deps=("docker" "jq" "curl" "wget" "unzip" "sed" "awk")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log "Fehler: $dep ist nicht installiert."
            exit 1
        fi
    done
}

stop_server() {
    log "Stoppe Server..."
    docker stop "$SERVER_NAME" || {
        log "Fehler: Konnte den Server nicht stoppen." >&2
        return 1
    }
}

start_server() {
    log "Starte Server..."
    docker start "$SERVER_NAME" || {
        log "Fehler: Konnte den Server nicht starten." >&2
        return 1
    }
}

initialize_new_server() {
    log "Initialisiere neuen Server..."
    rm -rf "$DATA_DIR/world" "$DATA_DIR/world_nether" "$DATA_DIR/world_the_end"
    rm -f "$PLUGIN_CONFIG"
    mkdir -p "$PLUGIN_DIR"
    find "$PLUGIN_DIR" -maxdepth 1 -name "*.jar" -delete
    log "Datenverzeichnis geleert für neuen Server."
}

create_backup() {
    stop_server || return 1
    log "Erstelle Backup..."
    mkdir -p "$BACKUP_DIR"
    local backup_name="backup_$(date +%Y%m%d%H%M)"
    local backup_file="$BACKUP_DIR/$backup_name.tar.gz"
    log "Starte Backup nach $backup_file..."
    local start_time
    start_time=$(date +%s)
    tar --exclude="./backups" -czf "$backup_file" -C "$DATA_DIR" . &
    local pid=$!
    while kill -0 $pid 2> /dev/null; do
        sleep 5
        local current_size
        current_size=$(du -sh "$backup_file" 2>/dev/null | awk '{print $1}')
        local elapsed_time=$(( $(date +%s) - start_time ))
        local elapsed_minutes=$((elapsed_time / 60))
        local elapsed_seconds=$((elapsed_time % 60))
        log "Backup läuft: Größe=$current_size, verstrichene Zeit=${elapsed_minutes}m ${elapsed_seconds}s"
    done
    if wait $pid; then
        local final_size
        final_size=$(du -sh "$backup_file" | awk '{print $1}')
        local total_time=$(( $(date +%s) - start_time ))
        local total_minutes=$((total_time / 60))
        local total_seconds=$((total_time % 60))
        log "Backup erstellt: $backup_file (Größe: $final_size, Dauer: ${total_minutes}m ${total_seconds}s)"
    else
        log "Fehler beim Erstellen des Backups." >&2
        return 1
    fi
    [[ "$DO_START_DOCKER" == "ja" ]] && start_server || true
}

delete_and_backup_plugins() {
    log "Sichere bestehende Plugins nach ${PLUGIN_DIR}/old_version"
    mkdir -p "${PLUGIN_DIR}/old_version"
    timestamp=$(date +%Y%m%d_%H%M%S)
    find "$PLUGIN_DIR" -maxdepth 1 -name "*.jar" -exec mv -v {} "${PLUGIN_DIR}/old_version/" \; | tee -a "$LOG_FILE"
    [[ -f "$PLUGIN_CONFIG" ]] && cp -v "$PLUGIN_CONFIG" "${PLUGIN_DIR}/old_version/plugins_$timestamp.txt" | tee -a "$LOG_FILE"
    log "Alte Plugins wurden gesichert."
}

# ============ Downloader-Helfer (GitHub + Fremdseiten) ============

normalize_github_owner_repo() {
    local url="$1"
    if [[ "$url" =~ github\.com/([^/]+)/([^/]+) ]]; then
        local owner="${BASHREMATCH[1]}"
        local repo="${BASHREMATCH[2]}"
        repo="${repo%.git}"
        echo "${owner}/${repo}"
        return 0
    fi
    return 1
}

github_latest_jar_url() {
    local owner_repo="$1"
    local api_url="https://api.github.com/repos/${owner_repo}/releases/latest"
    local auth_args=()
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        auth_args=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    fi
    local resp
    resp=$(curl -sfL -H "Accept: application/vnd.github+json" "${auth_args[@]}" "$api_url") || return 1
    local url
    url=$(echo "$resp" | jq -r '.assets[] | select(.name|test("(?i)(spigot|paper).+\\.jar$")) | .browser_download_url' | head -1)
    if [[ -z "$url" || "$url" == "null" ]]; then
        url=$(echo "$resp" | jq -r '.assets[] | select(.name|test("\\.jar$")) | .browser_download_url' | head -1)
    fi
    [[ -n "$url" && "$url" != "null" ]] && echo "$url"
}

download_file() {
    local url="$1"
    local out="$2"
    curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 -A "Mozilla/5.0" -o "$out" "$url"
}

# ============ CoreProtect: Source-Build aus master inkl. plugin.yml-Patch ============

# usage: build_coreprotect_from_source <branch> <out_jar_path>
build_coreprotect_from_source() {
    local branch="${1:-master}"
    local out_path="$2"

    local workdir
    workdir="$(mktemp -d)"
    local zip="${workdir}/src.zip"

    log "CoreProtect: Lade Source (Branch: ${branch})..."
    if ! curl -fL -A "Mozilla/5.0" -o "$zip" "https://github.com/PlayPro/CoreProtect/archive/refs/heads/${branch}.zip"; then
        log "FEHLER: Konnte Source-Archiv für Branch '${branch}' nicht laden."
        rm -rf "$workdir"
        return 1
    fi

    unzip -q "$zip" -d "$workdir" || { log "FEHLER: Entpacken fehlgeschlagen."; rm -rf "$workdir"; return 1; }

    # plugin.yml finden und anpassen
    local plugin_yml
    plugin_yml="$(find "$workdir" -type f -path "*/src/main/resources/plugin.yml" | head -1)"
    if [[ -z "$plugin_yml" ]]; then
        log "FEHLER: plugin.yml nicht gefunden."
        rm -rf "$workdir"
        return 1
    fi

    # Ersetze exakt ${project.branch} -> developement, oder notfalls jede Branch-Zeile
    if grep -q 'branch:[[:space:]]*\${project\.branch}' "$plugin_yml"; then
        sed -i 's/branch:[[:space:]]*\${project\.branch}/branch: developement/' "$plugin_yml"
        log "CoreProtect: plugin.yml angepasst (branch -> developement)."
    else
        # Fallback: Branch-Zeile überschreiben
        sed -i 's/^branch:[[:space:]].*/branch: developement/' "$plugin_yml" || true
        if ! grep -q '^branch:[[:space:]]*developement$' "$plugin_yml"; then
            # Falls keine Branch-Zeile existierte, füge sie oben ein
            sed -i '1i branch: developement' "$plugin_yml"
        fi
        log "CoreProtect: plugin.yml (Fallback) – branch: developement gesetzt."
    fi

    # Build (lokal mvn oder via Docker)
    local srcdir
    srcdir="$(dirname "$(dirname "$plugin_yml")")"   # -> .../src/main
    srcdir="$(dirname "$srcdir")"                    # -> .../src
    srcdir="$(dirname "$srcdir")"                    # -> Projektwurzel

    log "CoreProtect: Baue Plugin (Maven, Tests übersprungen)..."
    if command -v mvn >/dev/null 2>&1; then
        ( cd "$srcdir" && mvn -q -DskipTests package ) || { log "FEHLER: Maven-Build fehlgeschlagen."; rm -rf "$workdir"; return 1; }
    else
        docker run --rm -v "$srcdir":/src -w /src maven:3.9-eclipse-temurin-21 mvn -q -DskipTests package \
            || { log "FEHLER: Docker/Maven-Build fehlgeschlagen."; rm -rf "$workdir"; return 1; }
    fi

    local built
    built="$(find "$srcdir/target" -maxdepth 1 -type f -name 'CoreProtect-*.jar' | head -1)"
    if [[ -z "$built" ]]; then
        log "FEHLER: CoreProtect-JAR nicht gefunden."
        rm -rf "$workdir"
        return 1
    fi

    cp -f "$built" "$out_path" || { log "FEHLER: Konnte gebautes JAR nicht kopieren."; rm -rf "$workdir"; return 1; }
    log "ERFOLG: CoreProtect gebaut -> $(basename "$out_path")"
    rm -rf "$workdir"
    return 0
}

# akzeptiert: "build", "build:master", "build:<andererBranch>" – default master
parse_build_directive() {
    local url="$1"
    local branch="master"
    if [[ "$url" =~ ^build(:([a-zA-Z0-9._/-]+))?$ ]]; then
        [[ -n "${BASH_REMATCH[2]:-}" ]] && branch="${BASH_REMATCH[2]}"
        echo "$branch"
        return 0
    fi
    return 1
}

# ============ Update-Logik (mit Auswahl bei Fehlschlägen) ============

update_plugins() {
    log "Aktualisiere Plugins..."
    mkdir -p "$PLUGIN_DIR"

    if [[ ! -f "$PLUGIN_CONFIG" ]]; then
        log "plugins.txt nicht gefunden – erstelle Vorlage (CoreProtect aktiv, Rest kommentiert)."
        cat <<'EOL' > "$PLUGIN_CONFIG"
# Format: <Plugin-Name> <Download-URL oder build[:branch]>

# Aktive Zeile: CoreProtect aus master bauen (inkl. plugin.yml Patch auf `branch: developement`)
#CoreProtect build:master

# Beispiele (deaktiviert):
# ViaVersion https://github.com/ViaVersion/ViaVersion
# ViaBackwards https://github.com/ViaVersion/ViaBackwards
# Geyser-Spigot https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest/downloads/spigot
# floodgate-spigot https://download.geysermc.org/v2/projects/floodgate/versions/latest/builds/latest/downloads/spigot
EOL
        log "Vorlage erstellt: $PLUGIN_CONFIG"
        # kein return – wir laufen direkt weiter und verarbeiten CoreProtect
    fi

    local temp_dir="${PLUGIN_DIR}_temp"
    rm -rf "$temp_dir" && mkdir -p "$temp_dir"

    local -a ok_list=()
    local -a fail_list=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^#.*$ || -z "${line// }" ]] && continue

        local plugin_name plugin_url
        plugin_name=$(echo "$line" | awk '{$NF=""; sub(/[ \t]+$/, ""); print}')
        plugin_url=$(echo "$line" | awk '{print $NF}')
        [[ -z "$plugin_name" || -z "$plugin_url" ]] && continue

        log "Verarbeite: $plugin_name (${plugin_url})"
        local target="${temp_dir}/${plugin_name}.jar"

        # --- CoreProtect: Source-Build ---
        local build_branch
        if [[ "${plugin_name,,}" == "coreprotect" ]] && build_branch="$(parse_build_directive "$plugin_url")"; then
            if build_coreprotect_from_source "$build_branch" "$target"; then
                ok_list+=("$plugin_name")
            else
                fail_list+=("$plugin_name")
            fi
            continue
        fi

        # --- GitHub-Release oder Fremdseite ---
        if [[ "$plugin_url" == *"github.com"* ]]; then
            local owner_repo
            if owner_repo=$(normalize_github_owner_repo "$plugin_url"); then
                local asset_url
                asset_url=$(github_latest_jar_url "$owner_repo") || asset_url=""
                if [[ -n "$asset_url" ]]; then
                    if download_file "$asset_url" "$target"; then
                        log "ERFOLG: $plugin_name (GitHub API)"
                        ok_list+=("$plugin_name")
                    else
                        log "FEHLER: Download via GitHub API fehlgeschlagen für $plugin_name"
                        fail_list+=("$plugin_name")
                    fi
                else
                    log "FEHLER: Keine .jar in neuester Release gefunden für $plugin_name ($owner_repo)"
                    fail_list+=("$plugin_name")
                fi
            else
                if download_file "$plugin_url" "$target"; then
                    log "ERFOLG: $plugin_name (direkter GitHub-Link)"
                    ok_list+=("$plugin_name")
                else
                    log "FEHLER: Direkter GitHub-Download fehlgeschlagen für $plugin_name"
                    fail_list+=("$plugin_name")
                fi
            fi
        else
            if download_file "$plugin_url" "$target"; then
                log "ERFOLG: $plugin_name (Direktlink)"
                ok_list+=("$plugin_name")
            else
                log "FEHLER: Download fehlgeschlagen für $plugin_name"
                fail_list+=("$plugin_name")
            fi
        fi

    done < "$PLUGIN_CONFIG"

    # Manuelle Plugins übernehmen (falls vorhanden)
    if [[ -d "${PLUGIN_DIR}/manuell" ]]; then
        log "Kopiere manuelle Plugins..."
        find "${PLUGIN_DIR}/manuell" -maxdepth 1 -type f -name "*.jar" \
            -exec cp -v -n {} "$temp_dir/" \; | tee -a "$LOG_FILE"
    fi

    # Auswahl bei Fehlern
    if (( ${#fail_list[@]} > 0 )); then
        echo "---------------------------------------------"
        echo "Folgende Plugins konnten NICHT geladen/gebaut werden:"
        for p in "${fail_list[@]}"; do echo "  - $p"; done
        echo "---------------------------------------------"
        echo "Wählen Sie, wie fortgefahren werden soll:"
        echo "  1) Abbrechen (keine Änderungen an Plugins)"
        echo "  2) Weiter: Server OHNE die fehlgeschlagenen Plugins starten (alte Plugins werden ersetzt)"
        echo "  3) Weiter: ALTE Plugins behalten und NUR neue erfolgreiche drüberkopieren"
        read -p "Ihre Wahl [1/2/3]: " choice

        case "$choice" in
            2)
                log "Entferne alte Plugins und setze NUR erfolgreich geladene..."
                find "$PLUGIN_DIR" -maxdepth 1 -name "*.jar" -delete
                find "$temp_dir" -maxdepth 1 -type f -name "*.jar" -exec cp -v {} "$PLUGIN_DIR/" \; | tee -a "$LOG_FILE"
                log "Plugin-Update abgeschlossen (ohne fehlgeschlagene)."
                ;;
            3)
                log "Behalte alte Plugins und kopiere NUR erfolgreich geladene drüber..."
                find "$temp_dir" -maxdepth 1 -type f -name "*.jar" -exec cp -v {} "$PLUGIN_DIR/" \; | tee -a "$LOG_FILE"
                log "Plugin-Update abgeschlossen (Overlay)."
                ;;
            *)
                log "Abgebrochen: Es wurden KEINE Änderungen an den Plugins vorgenommen."
                rm -rf "$temp_dir"
                return 2
                ;;
        esac
    else
        log "Alle Plugins erfolgreich geladen/gebaut. Ersetze alte Plugins..."
        find "$PLUGIN_DIR" -maxdepth 1 -name "*.jar" -delete
        cp -v "$temp_dir"/*.jar "$PLUGIN_DIR/" | tee -a "$LOG_FILE"
        log "Plugin-Update komplett."
    fi

    rm -rf "$temp_dir"
    return 0
}

restore_backup() {
    log "Verfügbare Backups:"
    mapfile -t backups < <(find "$BACKUP_DIR" -type f -name "*.tar.gz" | sort -r)
    for i in "${!backups[@]}"; do
        bname=$(basename "${backups[$i]}")
        bdate=$(echo "$bname" | grep -o '[0-9]\{12\}')
        age_days=$(( ( $(date +%s) - $(date -d "${bdate:0:4}-${bdate:4:2}-${bdate:6:2} ${bdate:8:2}:${bdate:10:2}" +%s) ) / 86400 ))
        echo "$((i+1)). $bname (${age_days} Tage alt)"
    done
    echo "0. Abbrechen"
    read -p "Backup Nummer auswählen: " choice
    ((choice == 0)) && log "Wiederherstellung abgebrochen." && return
    index=$((choice - 1))
    [[ -z "${backups[$index]}" ]] && log "Ungültige Auswahl." && return
    stop_server
    log "Stelle Backup wieder her: ${backups[$index]}"
    rm -rf "$DATA_DIR/world"* "$PLUGIN_DIR"/*
    tar -xzf "${backups[$index]}" -C "$DATA_DIR"
    log "Wiederherstellung abgeschlossen."
}

update_docker() {
    stop_server || return 1
    log "Entferne alten Docker-Container..."
    docker rm "$SERVER_NAME" || {
        log "Fehler: Konnte Docker-Container nicht entfernen." >&2
        return 1
    }
    log "Starte neuen Docker-Container..."
    local docker_args=(
        -d -p 25565:25565 -p 19132:19132/udp
        -v "${DATA_DIR}:/data"
        --name "$SERVER_NAME"
        -e TZ=Europe/Berlin
        -e EULA=TRUE
        -e MEMORY="$MEMORY"
        -e TYPE="$TYPE"
        --restart always
    )
    [[ -n "$VERSION" ]] && docker_args+=(-e "VERSION=$VERSION")
    docker run "${docker_args[@]}" "$DOCKER_IMAGE" || {
        log "Fehler: Neuer Docker-Container konnte nicht gestartet werden." >&2
        return 1
    }
    log "Neuer Docker-Container gestartet."
}

manage_history() {
    echo "=== History Management ==="
    echo "1. History anzeigen"
    echo "2. History löschen"
    echo "3. Zurück zum Hauptmenü"
    read -p "Wählen Sie eine Option: " choice
    case "$choice" in
        1)
            if [[ -f "$HISTORY_FILE" ]]; then
                echo "Gespeicherte Einstellungen:"
                cat "$HISTORY_FILE"
            else
                echo "Keine History vorhanden."
            fi
            ;;
        2)
            if [[ -f "$HISTORY_FILE" ]]; then
                rm "$HISTORY_FILE"
                echo "History gelöscht."
            else
                echo "Keine History vorhanden."
            fi
            ;;
        3) return ;;
        *) echo "Ungültige Auswahl." ;;
    esac
    read -p "Drücken Sie Enter um fortzufahren..."
}

main() {
    shopt -s nocasematch
    log "Starte Update-Prozess..."
    check_dependencies

    if [[ "$1" == "--history" ]]; then manage_history; exit 0; fi

    DO_INIT=$(read_yesno_with_history "Soll ein neuer Server initialisiert werden?" "DO_INIT")
    if [[ "$DO_INIT" == "ja" ]]; then
        echo "ACHTUNG: Dies wird ALLE Daten löschen..." >&2
        read -p "Möchten Sie wirklich fortfahren? (ja/nein): " CONFIRM_INIT
        if [[ "$CONFIRM_INIT" =~ ^(ja|j|yes|y)$ ]]; then
            log "Erstelle vor der Initialisierung ein Backup..."
            create_backup || { log "Backup fehlgeschlagen. Abbruch."; exit 1; }
            initialize_new_server
            ASK_PLUGINS="nein"
        else
            log "Initialisierung abgebrochen."
            exit 0
        fi
    fi

    VERSION=$(read_with_history "Welche Minecraft-Version (z. B. LATEST, 1.21.1)?" "LATEST" "VERSION")
    MEMORY=$(read_with_history "Wieviel RAM (z. B. 6G, 8G)?" "6G" "MEMORY")
    TYPE=$(read_with_history "Welcher Server-Typ (PAPER, SPIGOT, VANILLA, ... )?" "PAPER" "TYPE")

    DO_BACKUP=$(read_yesno_with_history "Soll ein Backup erstellt werden?" "DO_BACKUP")
    DO_RESTORE=$(read_yesno_with_history "Soll ein Backup wiederhergestellt werden?" "DO_RESTORE")

    if [[ "$DO_INIT" == "ja" ]]; then
        DO_UPDATE_PLUGINS="nein"
        DO_DELETE_PLUGINS="nein"
    else
        DO_UPDATE_PLUGINS=$(read_yesno_with_history "Sollen die Plugins aktualisiert werden?" "DO_UPDATE_PLUGINS")
        DO_DELETE_PLUGINS=$(read_yesno_with_history "Sollen die aktuellen Plugins gelöscht und gesichert werden?" "DO_DELETE_PLUGINS")
    fi

    DO_START_DOCKER=$(read_yesno_with_history "Soll der Docker-Container gestartet werden?" "DO_START_DOCKER")

    [[ "$DO_BACKUP" == "ja" ]] && create_backup
    [[ "$DO_RESTORE" == "ja" ]] && restore_backup

    if [[ "$DO_UPDATE_PLUGINS" == "ja" ]]; then
        update_plugins
    else
        [[ "$DO_DELETE_PLUGINS" == "ja" ]] && delete_and_backup_plugins
    fi

    if [[ "$DO_START_DOCKER" == "ja" ]]; then
        update_docker
    else
        update_docker
        log "Stoppe den Docker-Container sofort wieder..."
        docker stop "$SERVER_NAME"
    fi

    log "Update-Prozess abgeschlossen."
}

if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Minecraft Server Management Script"
    echo "Verwendung: $0 [Option]"
    echo ""
    echo "Optionen:"
    echo "  --history    History-Management öffnen"
    echo "  --help, -h   Diese Hilfe anzeigen"
    echo ""
    echo "Das Script speichert Ihre letzten Eingaben automatisch und"
    echo "schlägt sie beim nächsten Start vor."
    exit 0
fi

main "$@"
