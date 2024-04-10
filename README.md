# Unraid ZFS rsync backup

Simple script for Unraid that will create a ZFS snapshot for all the child dataset (read docker containers dataset) and will sync said snapshots to another path (for example on the array). Once all done, it will do a Push to an [Uptime Kuma](https://github.com/louislam/uptime-kuma) monitor to let us know everything worked correctly.