# Simple Unraid ZFS backup

Simple and reliable script for Unraid that will create a ZFS snapshot for all the child dataset (read docker containers dataset) and will sync said snapshots to another path (for example on the array) in a mirror sync type using rsync. It also sends Unraid alerts regarding it's status. This is usefull to allow a simple no-downtime backup of Docker containers using a ZFS cache share. We can then use another backup software like [Kopia](https://kopia.io/), [Duplicacy](https://duplicacy.com/), [Borg](https://www.borgbackup.org/), [Restic](https://restic.net/), ... to manage the versioning and incremental backups to the cloud or other share.

Based on SpaceInvaderOne [Unraid_ZFS_Dataset_Snapshot_and_Replications](https://github.com/SpaceinvaderOne/Unraid_ZFS_Dataset_Snapshot_and_Replications) script but mainly a simplified and faster version using rsync only without the Sanoid dependency and with a couple more options/fixes added.

## Key Points
* Simple: It's reliable and simple. Exactly what we want for our backups
* Fast: Since we are using rsync, only the modified or added files will be sent to your target folder resulting in fast backups.
* Unraid alerts: Used built-in unraid alerts to keep us in the loop on what is happening with the backup runs.
* No container downtime: Allow backuping docker containers without downtime.
* Perfect when paired with specialized backup tools like Kopia, Duplicacy, Borg or Restic. Sync to a target folder then add said folder in your backup software for versioning and/or cloud upload.
* Single dependency: Only need the 'User Scripts' Unraid plugin.

## Differences with other Unraid backup strategies

### Unraid_ZFS_Dataset_Snapshot_and_Replications - SpaceinvaderOne
[Unraid_ZFS_Dataset_Snapshot_and_Replications](https://github.com/SpaceinvaderOne/Unraid_ZFS_Dataset_Snapshot_and_Replications) is the inspiration for this script. The initial plan was to create a PR with some fix for the script but the script seems mostly abandonned since a lot of PR have been waiting to be merged for multiple months. After starting work on said script, I ended up starting another script altogether since most of the features (and complexity that come along with them) were of no interest to me. There was also a couple of issues that meant a big rewrite of the code. Notably the rsync mode sync the parent dataset using the `--delete` switch which delete all the child dataset folders from the previous run and once the parent sync is done the child sync is done all over again. This resulted in the rsync being a full sync on every run instead of a true incremental of new or modified files only. This mean that the backup takes exponentially more time versus a true incremental like this script does.

### Appdata Backup
While this is an awesome plugin, it doesn't leverage the capability of ZFS snapshots which mean it needs to shutdown the docker containers to back them up which results in downtime. It's also slower since an archive is created for each container on every run.

## Installation
1. In the Unraid community app store, install the "**User Scripts**" plugin by author Squid.
2. Copy the whole script from this Github page.
3. In Unraid, go to "**Settings**" -> "**User Scripts**"
4. Click on "**ADD NEW SCRIPT**" at the botton of the page.
5. Give the script a name.
6. Click on the little cogwheel next to the script you just added and select "**EDIT SCRIPT**"
7. Paste the whole script that you copied from Github. (Make sure to remove the placeholder line `#!/bin/bash` in the window !)
8. Edit the variables in the beginning of the script according to your needs.
9. Click "**SAVE CHANGES**" at the top of the script window.
10. Optional: To run the script on a schedule, select a predefined schedule in the drop down or select "**Custom**" and use a tool like [Crontab Guru](https://crontab.guru/) to create the custom cron expression.