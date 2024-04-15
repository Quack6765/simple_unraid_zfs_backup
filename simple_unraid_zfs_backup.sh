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
excluded_folders=("Plex-Media-Server/config/Library/Application Support/Plex Media Server/Cache" "jellyfin/cache" "unmanic/cache")
## Target folder to sync the backups to.
target_folder="/mnt/user/backups/appdata"
## When to send a notification to Unraid. "all" for both success & failure, "error" for only failure or "none" for never at all.
notification_type="all" 

# ----------------------------------------------------------
# DO NOT CHANGE ANYTHING PAST THIS POINT ! -----------------
# ----------------------------------------------------------

source_path="$source_pool"/"$source_dataset"
script_name="simple_unraid_zfs_backup"
snapshot_name=$script_name
error_count=0
SECONDS=0
github_url="https://raw.githubusercontent.com/Quack6765/${script_name}/main/${script_name}.sh"
current_version="1.1"
update_available=false
container_stopped=""

function trapping_error() {
    ((error_count+=1))
    echo "ERROR: $BASH_COMMAND"
}

trap 'trapping_error $?' ERR

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
        echo "ERROR: $error_count error(s) during run !"
        message="$error_count error(s) during latest run ! Please check the logs for more info."
        message_severity="alert"
    else
        echo "OK: Completed without issue !"
        message="OK: Completed without issue !"
        message_severity="normal"
    fi

    if [ $update_available = true ]; then
        echo "INFO: Newer version of the script available on Github !"
        message+="\nINFO: Newer version of the script available on Github !"
    fi

    duration=$SECONDS
    runtime="Total Runtime: $((duration / 60)) minutes and $((duration % 60)) seconds."
    echo $runtime

    if [ "$notification_type" == "all" ] || ([ "$notification_type" == "error" ] && [ $error_count -gt 0 ]); then
        /usr/local/emhttp/webGui/scripts/notify -s "Backup Notification" -d "$message\n$runtime" -i "$message_severity"
    fi
}

create_snapshot_dataset(){
    dataset=$1
    dataset_name=$2

    for container in ${containers_to_stop[@]}; do
        if [[ "$container" == "$dataset_name" ]]; then
            if [ $(docker ps -f name="^${container}$" | tail +2 | head -n1 | wc -l) -gt 0 ]; then
                echo "Stopping container..."
                docker stop $container > /dev/null
                container_stopped=$container
                sleep 5
            else
                echo "Container already stopped..."
            fi
        fi
    done

    echo "Creating snapshot..."
    zfs snapshot "${dataset}@${snapshot_name}"
}

rsync_dataset(){
    dataset=$1
    dataset_name=$2

    rsync_args=()
    rsync_args+=( -aph )
    rsync_args+=( --delete )

    if [ $dry_run == true ]; then
        rsync_args+=( --dry-run )
    fi

    if (( ${#excluded_folders[@]} )); then
      for folder in "${excluded_folders[@]}"; do
        if [ ! -z "$folder" ] && [ $(echo "$folder" | cut -f1 -d/) == "$dataset_name" ]; then
            echo "Excluded folder: \"${folder#*/}\""
            rsync_args+=( --exclude "${folder#*/}" )
        fi
      done
    fi

    if [ $debug == true ]; then
        rsync_args+=( -v )
        echo "[DEBUG]: rsync ${rsync_args[@]} \"/mnt/${dataset}/.zfs/snapshot/${snapshot_name}/\" \"${target_folder}/${dataset_name}\""
    fi

    mkdir -p $target_folder

    echo "Syncing: '${dataset}' -> '${target_folder}/${dataset_name}'"
    rsync "${rsync_args[@]}" "/mnt/${dataset}/.zfs/snapshot/${snapshot_name}/" "${target_folder}/${dataset_name}"
}

destroy_snapshot_dataset(){

    if [ ! -z $container_stopped ]; then
        echo "Starting container..."
        docker start $container_stopped > /dev/null
    fi

    echo "Removing snapshot..."
    zfs destroy "${dataset}@${snapshot_name}"
}

check_version
if [ ! -z $source_pool ] && [ ! -z $source_dataset ] && [ ! -z $target_folder ]; then
    zfs_match=$(zfs list -r -H -o name | grep -c "$source_path")
    if [ $zfs_match -eq 0 ]; then
        echo "ERROR: Couldn't find dataset '$source_path'" >&2
    elif [ $zfs_match -eq 1 ]; then
        echo "Starting parent dataset sync job..."
        echo "-------------------------"
        echo "Dataset: '$source_path'"
        create_snapshot_dataset $source_path
        rsync_dataset $source_path
        destroy_snapshot_dataset $source_path
        echo "Status: Done !"
        echo "-------------------------"
    elif [ $zfs_match -gt 1 ]; then
        echo "Starting children dataset sync job..."
        for dataset in $(zfs list -r -H -o name "${source_path}" | tail -n +2); do
            echo "-------------------------"
            echo "Dataset: '$dataset'"
            dataset_name=$(basename $dataset)
            create_snapshot_dataset $dataset $dataset_name
            rsync_dataset $dataset $dataset_name
            destroy_snapshot_dataset $dataset
            echo "Status: Done !"
        done
        echo "-------------------------"
    fi
else
    echo "ERROR: Empty or missing parameter in script." >&2
fi
notify