# Unraid ZFS rsync backup

Simple script for Unraid that will create a ZFS snapshot for all the child dataset (read docker containers dataset) and will sync said snapshots to another path (for example on the array). It also sends Unraid alerts regarding the status of it's latest run.