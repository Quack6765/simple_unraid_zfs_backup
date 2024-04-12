#!/bin/bash
# Small script to backup an Unraid ZFS cache pool using ZFS snapshots and rsync
# https://github.com/Quack6765/simple_unraid_zfs_backup

# Change the following variables accordingly
## Run in test mode.
dry_run=false
## Output more logs
debug=false
## Source ZFS pool to sync from.
source_pool="cache"
## Source parent ZFS dataset to sync from.
source_dataset="appdata"
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

source_path="$source_pool"/"$source_dataset"
snapshot_name="simple_unraid_zfs_backup"
error_count=0
SECONDS=0

trap '((error_count+=1))' ERR

notify() {
    if [ $error_count -gt 0 ]; then
        echo "ERROR: $error_count error(s) during run !"
        message="$error_count error(s) during latest run ! Please check the logs for more info."
        message_severity="alert"
    else
        echo "OK: Completed without issue !"
        message="Completed without issue !"
        message_severity="normal"
    fi

    if [ "$notification_type" == "all" ] || ([ "$notification_type" == "error" ] && [ $error_count -gt 0 ]); then
        /usr/local/emhttp/webGui/scripts/notify -s "Backup Notification" -d "$message" -i "$message_severity"
    fi

    duration=$SECONDS
    echo "Total Runtime: $((duration / 60)) minutes and $((duration % 60)) seconds."
}

create_snapshot_dataset(){
    dataset=$1
    echo "Creating snapshot..."
    zfs snapshot "${dataset}@${snapshot_name}"
}

rsync_dataset(){

    dataset=$1
    dataset_name=$(basename $dataset)

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
    echo "Removing snapshot..."
    zfs destroy "${dataset}@${snapshot_name}"
}

if [ ! -z $source_pool ] && [ ! -z $source_dataset ] && [ ! -z $target_folder ]; then
    zfs_match=$(zfs list -r -H -o name | grep -c "$source_path" )
    if [ $zfs_match -eq 0 ]; then
        echo "ERROR: Couldn't find dataset '$source_path'" >&2
        ((error_count+=1))
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
            create_snapshot_dataset $dataset
            rsync_dataset $dataset
            destroy_snapshot_dataset $dataset
            echo "Status: Done !"
        done
        echo "-------------------------"
    fi
else
    echo "ERROR: Empty or missing parameter in script." >&2
    ((error_count+=1))
fi
notify