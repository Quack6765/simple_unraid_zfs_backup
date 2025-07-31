#!/bin/bash
# Small script to backup an Unraid ZFS cache pool using ZFS snapshots and rsync
# https://github.com/Quack6765/simple_unraid_zfs_backup

# Change the following variables accordingly
## Run in test mode. 'true' or 'false'
dry_run=false
## Output more logs. 'true' or 'false'
debug=false
## Source ZFS pool to sync from.
source_pool="cache"
## Source parent ZFS dataset to sync from.
source_dataset="appdata"
## List of containers that should be stopped before doing a ZFS snapshot. This is recommended for database containers like MySQL or Postgresql.
## Example: ("mysql" "postgresql" "anyothercontainer")
containers_to_stop=("")
## List of folders to exclude. In the format 'dataset name/relative path to dataset'. Path can have whitespace.
## Example: ("Plex-Media-Server/config" "jellyfin/cache" "anyotherdataset/folder")
excluded_folders=("")
## Target folder to sync the backups to.
target_folder=""
## When to send a notification to Unraid. "all" for both success & failure, "error" for only failure or "none" for never at all.
notification_type="all" 

# ----------------------------------------------------------
# DO NOT CHANGE ANYTHING PAST THIS POINT ! -----------------
# ----------------------------------------------------------

# Strict mode for better error handling
set -euo pipefail

source_path="$source_pool"/"$source_dataset"
script_name="simple_unraid_zfs_backup"
timestamp=$(date +%Y%m%d%H%M%S)
snapshot_name="${script_name}_${timestamp}"
error_count=0
SECONDS=0
github_url="https://raw.githubusercontent.com/Quack6765/${script_name}/main/${script_name}.sh"
current_version="1.3"
update_available=false

# Enhanced logging function
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[${timestamp}] [${level}] ${message}" >&2
}

# Dry-run logging function
dry_run_log() {
    if [ "$dry_run" = true ]; then
        log "DRY-RUN" "$1"
    fi
}

function trapping_error() {
    ((error_count+=1))
    log "ERROR" "Command failed: $BASH_COMMAND"
}

trap 'trapping_error $?' ERR

# Validate required commands
validate_dependencies() {
    local required_commands=("zfs" "rsync" "docker")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log "ERROR" "Required command '$cmd' not found"
            exit 1
        fi
    done
}

check_version() {
    latest_script="/tmp/${script_name}.sh-latest"
    wget $github_url -qO $latest_script

    latest_version=$(grep "^current_version=\"[0-9]\.[0-9]\"$" "$latest_script" | grep -o "[0-9]\.[0-9]")
    if [[ ! -z $latest_version ]] && [[ $current_version < $latest_version ]]; then
        update_available=true
    fi

    rm $latest_script
}

notify() {
    if [ $error_count -gt 0 ]; then
        log "ERROR" "$error_count error(s) during run !"
        message="$error_count error(s) during latest run ! Please check the logs for more info."
        message_severity="alert"
    else
        log "INFO" "Completed without issue !"
        message="OK: Completed without issue !"
        message_severity="normal"
    fi

    if [ $update_available = true ]; then
        log "INFO" "Newer version of the script available on Github !"
        message+="\nINFO: Newer version of the script available on Github !"
    fi

    duration=$SECONDS
    runtime="Total Runtime: $((duration / 60)) minutes and $((duration % 60)) seconds."
    echo $runtime

    if [ "$notification_type" == "all" ] || ([ "$notification_type" == "error" ] && [ $error_count -gt 0 ]); then
        /usr/local/emhttp/webGui/scripts/notify -s "Backup Notification" -d "$message\n$runtime" -i "$message_severity"
    fi
}

stop_container(){
    container=$1

    # Dry-run logging
    if [ "$dry_run" = true ]; then
        if [ -z "$container" ]; then return; fi
        dry_run_log "Stopping container: '$container'..."
        return
    fi

    if [ -z "$container" ]; then return; fi
    if [ $(docker ps -f name="^${container}$" | tail +2 | head -n1 | wc -l) -gt 0 ]; then
        log "INFO" "Stopping container: '$container'..."
        docker stop $container > /dev/null
        if [ $? -ne 0 ]; then
            log "ERROR" "Failed to stop container: '$container'"
        fi
    else
        log "INFO" "Container already stopped: '$container'..."
    fi
}

start_container(){
    container=$1

    # Dry-run logging
    if [ "$dry_run" = true ]; then
        if [ -z "$container" ]; then return; fi
        dry_run_log "Starting container: '$container'..."
        return
    fi

    if [ -z "$container" ]; then return; fi
    log "INFO" "Starting container: '$container'..."
    docker start "$container" > /dev/null
    if [ $? -ne 0 ]; then
        log "ERROR" "Failed to start container: '$container'"
    fi
}

create_snapshot_dataset(){
    dataset=$1

    # Dry-run logging
    if [ "$dry_run" = true ]; then
        dry_run_log "Creating snapshot for $dataset"
        return
    fi

    log "INFO" "Creating snapshot for $dataset"
    zfs snapshot "${dataset}@${snapshot_name}"
}

rsync_dataset(){
    dataset=$1
    dataset_name=$2

    # In dry-run mode, provide detailed preview without running rsync
    if [ "$dry_run" = true ]; then
        dry_run_log "Source Dataset: $dataset"
        dry_run_log "Destination: ${target_folder}/${dataset_name}"

        # Excluded folders preview
        if (( ${#excluded_folders[@]} )); then
            dry_run_log "Excluded Folders:"
            for folder in "${excluded_folders[@]}"; do
                if [ ! -z "$folder" ] && [ $(echo "$folder" | cut -f1 -d/) == "$dataset_name" ]; then
                    dry_run_log "  - ${folder#*/}"
                fi
            done
        else
            dry_run_log "No folders excluded"
        fi

        dry_run_log "Syncing: '${dataset}' -> '${target_folder}/${dataset_name}'"
        return
    fi

    # Actual rsync execution
    rsync_args=()
    rsync_args+=( -aph )
    rsync_args+=( --delete )
    rsync_args+=( --numeric-ids )

    if (( ${#excluded_folders[@]} )); then
        for folder in "${excluded_folders[@]}"; do
            if [ ! -z "$folder" ] && [ $(echo "$folder" | cut -f1 -d/) == "$dataset_name" ]; then
                log "INFO" "Excluded folder: \"${folder#*/}\""
                rsync_args+=( --exclude "${folder#*/}" )
            fi
        done
    fi

    if [ $debug == true ]; then
        rsync_args+=( -v )
        log "DEBUG" "rsync ${rsync_args[@]} \"/mnt/${dataset}/.zfs/snapshot/${snapshot_name}/\" \"${target_folder}/${dataset_name}\""
    fi

    mkdir -p $target_folder

    log "INFO" "Syncing: '${dataset}' -> '${target_folder}/${dataset_name}'"
    rsync "${rsync_args[@]}" "/mnt/${dataset}/.zfs/snapshot/${snapshot_name}/" "${target_folder}/${dataset_name}"
}

destroy_snapshot_dataset(){
    dataset=$1

    # Dry-run logging
    if [ "$dry_run" = true ]; then
        dry_run_log "Removing snapshot for $dataset"
        return
    fi

    log "INFO" "Removing snapshot for $dataset"
    zfs destroy "${dataset}@${snapshot_name}"
}

# Initial dry-run logging
if [ "$dry_run" = true ]; then
    log "DRY-RUN" "DRY-RUN MODE IS ACTIVE - NO ACTUAL CHANGES WILL BE MADE"
fi

# Check if an update is available
check_version

# Launch jobs
if [ ! -z "$source_pool" ] && [ ! -z "$source_dataset" ] && [ ! -z "$target_folder" ]; then
    zfs_match=$(zfs list -r -H -o name | grep -c "$source_path")
    if [ $zfs_match -eq 0 ]; then
        log "ERROR" "Couldn't find dataset '$source_path'"
    elif [ $zfs_match -eq 1 ]; then
        dataset_name=$(basename $source_path)
        container=""
        for c in "${containers_to_stop[@]}"; do
            if [[ "$dataset_name" == "$c" ]]; then
                container="$c"
                break
            fi
        done
        stop_container "$container"
        log "INFO" "Starting parent dataset sync job..."
        log "INFO" "-------------------------"
        log "INFO" "Dataset: '$source_path'"
        create_snapshot_dataset $source_path
        start_container "$container"
        rsync_dataset "$dataset_name" "$dataset_name"
        destroy_snapshot_dataset $source_path
        log "INFO" "Status: Done !"
        log "INFO" "-------------------------"
    elif [ $zfs_match -gt 1 ]; then
        log "INFO" "Starting children dataset sync job..."
        for dataset in $(zfs list -r -H -o name "${source_path}" | tail -n +2); do
            log "INFO" "-------------------------"
            log "INFO" "Dataset: '$dataset'"
            dataset_name=$(basename $dataset)
            container=""
            for c in "${containers_to_stop[@]}"; do
                if [[ "$dataset_name" == "$c" ]]; then
                    container="$c"
                    break
                fi
            done
            stop_container "$container"
            create_snapshot_dataset $dataset
            start_container "$container"
            rsync_dataset $dataset $dataset_name
            destroy_snapshot_dataset $dataset
            log "INFO" "Status: Done !"
        done
        log "INFO" "-------------------------"
    fi
else
    log "ERROR" "Empty or missing parameter in script."
fi
notify