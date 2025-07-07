#!/bin/bash

# === Minecraft Docker Update-, Backup- und Restore-Skript ===

# === Pfad abfragen ===
read -p "Pfad zum Minecraft-Datenverzeichnis (Standard: /opt/minecraft_server): " DATA_DIR
DATA_DIR="${DATA_DIR:-/opt/minecraft_server}"
SERVER_NAME="mc"
BACKUP_DIR="${DATA_DIR}/backups"
PLUGIN_DIR="${DATA_DIR}/plugins"
PLUGIN_CONFIG="${DATA_DIR}/plugins.txt"
DOCKER_IMAGE="itzg/minecraft-server"
LOG_FILE="${DATA_DIR}/update_log.txt"

log() {
    printf "%s - %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" | tee -a "$LOG_FILE"
}

cleanup() {
    log "Script wurde abgebrochen."
    exit 1
}
trap cleanup SIGINT SIGTERM

check_dependencies() {
    local deps=("docker" "jq" "curl" "wget")
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
    local start_time=$(date +%s)
    tar --exclude="./backups" -czf "$backup_file" -C "$DATA_DIR" . &
    local pid=$!
    while kill -0 $pid 2> /dev/null; do
        sleep 5
        local current_size=$(du -sh "$backup_file" 2>/dev/null | awk '{print $1}')
        local elapsed_time=$(( $(date +%s) - start_time ))
        local elapsed_minutes=$((elapsed_time / 60))
        local elapsed_seconds=$((elapsed_time % 60))
        log "Backup läuft: Größe=$current_size, verstrichene Zeit=${elapsed_minutes}m ${elapsed_seconds}s"
    done
    if wait $pid; then
        local final_size=$(du -sh "$backup_file" | awk '{print $1}')
        local total_time=$(( $(date +%s) - start_time ))
        local total_minutes=$((total_time / 60))
        local total_seconds=$((total_time % 60))
        log "Backup erstellt: $backup_file (Größe: $final_size, Dauer: ${total_minutes}m ${total_seconds}s)"
    else
        log "Fehler beim Erstellen des Backups." >&2
        return 1
    fi
    [[ "$DO_START_DOCKER" =~ ^[nN](ein)?$ ]] && start_server || true
}

delete_and_backup_plugins() {
    log "Sichere bestehende Plugins nach ${PLUGIN_DIR}/old_version"
    mkdir -p "${PLUGIN_DIR}/old_version"
    timestamp=$(date +%Y%m%d_%H%M%S)
    find "$PLUGIN_DIR" -maxdepth 1 -name "*.jar" -exec mv -v {} "${PLUGIN_DIR}/old_version/" \; | tee -a "$LOG_FILE"
    [[ -f "$PLUGIN_CONFIG" ]] && cp -v "$PLUGIN_CONFIG" "${PLUGIN_DIR}/old_version/plugins_$timestamp.txt" | tee -a "$LOG_FILE"
    log "Alte Plugins wurden gesichert."
}

update_plugins() {
    log "Aktualisiere Plugins..."
    mkdir -p "$PLUGIN_DIR"

    if [[ ! -f "$PLUGIN_CONFIG" ]]; then
        log "Fehler: plugins.txt nicht gefunden! Erstelle Vorlage."
        cat <<EOL > "$PLUGIN_CONFIG"
# Format: <Plugin-Name> <Download-URL>
# Beispiel:
# ViaVersion https://github.com/ViaVersion/ViaVersion/releases/latest
EOL
        return 1
    fi

    local temp_dir="${PLUGIN_DIR}_temp"
    rm -rf "$temp_dir" && mkdir -p "$temp_dir"

    handle_download_error() {
        log "FEHLER: $1"
        log "URL: $2"
        log "Versuchter Speicherort: $3"
        log "Versuche direkten Download ohne GitHub API..."
        wget --tries=3 --timeout=30 -q -O "$3" "$2" || {
            log "SCHWERER FEHLER: Download gescheitert für $1"
            return 1
        }
    }

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^#.*$ || -z "${line// }" ]] && continue
        plugin_name=$(echo "$line" | awk '{$NF=""; sub(/[ \t]+$/, ""); print}')
        plugin_url=$(echo "$line" | awk '{print $NF}')
        log "Verarbeite: $plugin_name (${plugin_url})"

        if [[ "$plugin_url" == *"github.com"* ]]; then
            owner_repo=$(echo "$plugin_url" | awk -F'/' '{i=NF; while($i != "releases" && i>0) i--; print $(i-2)"/"$(i-1)}')
            [[ -z "$owner_repo" ]] && continue
            api_response=$(curl -sfL "https://api.github.com/repos/$owner_repo/releases/latest") || {
                log "GitHub API Fehler für $owner_repo"
                handle_download_error "$plugin_name" "$plugin_url" "${temp_dir}/${plugin_name}.jar"
                continue
            }
            asset_url=$(echo "$api_response" | jq -r '.assets[] | select(.name | test(".*.jar$")) | .browser_download_url' | head -1)
            if [[ -z "$asset_url" ]]; then
                log "Keine .jar-Datei im GitHub-Release gefunden."
                handle_download_error "$plugin_name" "$plugin_url" "${temp_dir}/${plugin_name}.jar"
                continue
            fi
            wget --tries=3 --timeout=30 -q -O "${temp_dir}/${plugin_name}.jar" "$asset_url" || {
                handle_download_error "$plugin_name" "$plugin_url" "${temp_dir}/${plugin_name}.jar"
                continue
            }
        else
            wget --tries=3 --timeout=30 -q -O "${temp_dir}/${plugin_name}.jar" "$plugin_url" || {
                handle_download_error "$plugin_name" "$plugin_url" "${temp_dir}/${plugin_name}.jar"
                continue
            }
        fi
        log "ERFOLG: $plugin_name heruntergeladen"
    done < "$PLUGIN_CONFIG"

    [[ -d "${PLUGIN_DIR}/manuell" ]] && {
        log "Kopiere manuelle Plugins..."
        find "${PLUGIN_DIR}/manuell" -maxdepth 1 -name "*.jar" -exec cp -v -n {} "$temp_dir/" \; | tee -a "$LOG_FILE"
    }

    log "Entferne alte Plugins..."
    find "$PLUGIN_DIR" -maxdepth 1 -name "*.jar" -delete
    log "Kopiere neue Plugins..."
    cp -v "$temp_dir"/*.jar "$PLUGIN_DIR/" | tee -a "$LOG_FILE"
    rm -rf "$temp_dir"
    log "Plugin-Update komplett"
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

main() {
    log "Starte Update-Prozess..."
    shopt -s nocasematch
    check_dependencies

       read -p "Soll ein neuer Server initialisiert werden? (ja/nein): " DO_INIT
    if [[ "$DO_INIT" =~ ^(ja|j|yes|y)$ ]]; then
        echo "ACHTUNG: Dies wird ALLE Daten löschen, inklusive Plugins, Welten und Konfigurationen!"
        read -p "Möchten Sie wirklich fortfahren? (ja/nein): " CONFIRM_INIT
        if [[ "$CONFIRM_INIT" =~ ^(ja|j|yes|y)$ ]]; then
            log "Erstelle vor der Initialisierung ein Backup..."
            create_backup || {
                log "Backup fehlgeschlagen. Abbruch der Initialisierung."
                exit 1
            }
            initialize_new_server
        else
            log "Initialisierung abgebrochen."
            exit 0
        fi
    fi


    read -p "Welche Minecraft-Version soll gestartet werden (Standard: LATEST)? " VERSION
    VERSION=${VERSION:-LATEST}
    read -p "Wieviel RAM soll der Server verwenden? (Standard: 6G): " MEMORY
    MEMORY=${MEMORY:-6G}
    read -p "Welcher Server-Typ soll verwendet werden? (Standard: PAPER): " TYPE
    TYPE=${TYPE:-PAPER}
    read -p "Soll ein Backup erstellt werden? (ja/nein): " DO_BACKUP
    read -p "Soll ein Backup wiederhergestellt werden? (ja/nein): " DO_RESTORE
    read -p "Sollen die Plugins aktualisiert werden? (ja/nein): " DO_UPDATE_PLUGINS
    read -p "Sollen die aktuellen Plugins gelöscht und gesichert werden? (ja/nein): " DO_DELETE_PLUGINS
    read -p "Soll der Docker-Container gestartet werden? (ja/nein): " DO_START_DOCKER

    [[ "$DO_BACKUP" =~ ^(ja|j|yes|y)$ ]] && create_backup
    [[ "$DO_RESTORE" =~ ^(ja|j|yes|y)$ ]] && restore_backup
    [[ "$DO_UPDATE_PLUGINS" =~ ^(ja|j|yes|y)$ ]] && update_plugins || [[ "$DO_DELETE_PLUGINS" =~ ^(ja|j|yes|y)$ ]] && delete_and_backup_plugins
    [[ "$DO_START_DOCKER" =~ ^(ja|j|yes|y)$ ]] && update_docker

    log "Update-Prozess abgeschlossen."
}

main
