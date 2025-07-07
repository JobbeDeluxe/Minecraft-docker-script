#!/bin/bash

# === Minecraft Docker Update- und Restore-Skript ===

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
    docker stop "$SERVER_NAME" || log "Server war nicht aktiv."
}

start_server() {
    log "Starte Server..."
    docker start "$SERVER_NAME" || log "Fehler: Konnte Server nicht starten."
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
    stop_server
    log "Erstelle Backup..."
    mkdir -p "$BACKUP_DIR"
    local backup_name="backup_$(date +%Y%m%d%H%M)"
    local backup_file="$BACKUP_DIR/$backup_name.tar.gz"
    log "Starte Backup nach $backup_file..."
    tar --exclude="./backups" -czf "$backup_file" -C "$DATA_DIR" . || {
        log "Fehler beim Backup."
        return 1
    }
    log "Backup erstellt: $backup_file"
    [[ "$DO_START_DOCKER" =~ ^[nN](ein)?$ ]] || start_server
}

restore_backup() {
    log "Verfügbare Backups:"
    mapfile -t backups < <(ls -1t "$BACKUP_DIR"/backup_*.tar.gz 2>/dev/null)
    if [[ ${#backups[@]} -eq 0 ]]; then
        log "Keine Backups gefunden."
        return
    fi

    for i in "${!backups[@]}"; do
        file="${backups[$i]}"
        mod_time=$(date -r "$file" +%s)
        age_days=$(( ( $(date +%s) - mod_time ) / 86400 ))
        echo "$((i+1)). $(basename "$file") (${age_days} Tage alt)"
    done
    echo "0. Abbrechen"
    read -p "Welche Backup-Nummer soll wiederhergestellt werden? " sel
    [[ "$sel" =~ ^[0-9]+$ ]] || return
    (( sel == 0 )) && return
    (( sel > ${#backups[@]} )) && return
    selected_backup="${backups[$((sel-1))]}"
    log "Backup wird wiederhergestellt: $selected_backup"
    stop_server
    find "$PLUGIN_DIR" -maxdepth 1 -name "*.jar" -delete
    tar -xzf "$selected_backup" -C "$DATA_DIR"
    log "Wiederherstellung abgeschlossen."
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
        log "plugins.txt fehlt. Vorlage wird erstellt."
        cat <<EOL > "$PLUGIN_CONFIG"
# Format: <Plugin-Name> <Download-URL>
# Beispiel:
# ViaVersion https://github.com/ViaVersion/ViaVersion/releases/latest
EOL
        return 1
    fi

    local temp_dir="${PLUGIN_DIR}_temp"
    rm -rf "$temp_dir" && mkdir -p "$temp_dir"

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
        plugin_name=$(echo "$line" | awk '{$NF=""; sub(/[ \t]+$/, ""); print}')
        plugin_url=$(echo "$line" | awk '{print $NF}')
        log "Lade $plugin_name..."

        if [[ "$plugin_url" == *"github.com"* ]]; then
            owner_repo=$(echo "$plugin_url" | awk -F'/' '{for(i=1;i<=NF;i++) if ($i=="releases") {print $(i-2)"/"$(i-1); break}}')
            asset_url=$(curl -sfL "https://api.github.com/repos/$owner_repo/releases/latest" | jq -r '.assets[] | select(.name | endswith(".jar")) | .browser_download_url' | head -n1)
        else
            asset_url="$plugin_url"
        fi

        wget -q -O "${temp_dir}/${plugin_name}.jar" "$asset_url" || log "Fehler bei $plugin_name"
    done < "$PLUGIN_CONFIG"

    [[ -d "${PLUGIN_DIR}/manuell" ]] && find "${PLUGIN_DIR}/manuell" -maxdepth 1 -name "*.jar" -exec cp -vn {} "$temp_dir/" \;
    find "$PLUGIN_DIR" -maxdepth 1 -name "*.jar" -delete
    cp -v "$temp_dir"/*.jar "$PLUGIN_DIR/"
    rm -rf "$temp_dir"
    log "Plugin-Update abgeschlossen."
}

update_docker() {
    stop_server
    log "Entferne alten Docker-Container..."
    docker rm "$SERVER_NAME" || true
    log "Starte neuen Docker-Container..."
    docker run -d \
        -p 25565:25565 -p 19132:19132/udp \
        -v "${DATA_DIR}:/data" \
        --name "$SERVER_NAME" \
        -e TZ=Europe/Berlin \
        -e EULA=TRUE \
        -e MEMORY="$MEMORY" \
        -e TYPE="$TYPE" \
        ${VERSION:+-e VERSION="$VERSION"} \
        --restart always \
        "$DOCKER_IMAGE" || log "Fehler: Docker-Start fehlgeschlagen."
}

main() {
    log "Starte Update-Prozess..."
    shopt -s nocasematch
    check_dependencies

    read -p "Soll ein neuer Server initialisiert werden? (ja/nein): " DO_INIT
    [[ "$DO_INIT" =~ ^(ja|j|yes|y)$ ]] && initialize_new_server

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
    [[ "$DO_UPDATE_PLUGINS" =~ ^(ja|j|yes|y)$ ]] && update_plugins
    [[ "$DO_DELETE_PLUGINS" =~ ^(ja|j|yes|y)$ ]] && delete_and_backup_plugins
    [[ "$DO_START_DOCKER" =~ ^(ja|j|yes|y)$ ]] && update_docker

    log "Update-Prozess abgeschlossen."
}

main
