#!/bin/bash

# This script requires SSHFS and Borg.
# Back up data from a remote location to a local repository.

# =============
# CONFIGURATION
# =============

DATA_HOST="example-hostname"
DATA_PATHS=( "/example_location_1" \
    "/example_location_2" )

SSHFS_MOUNTPOINT="/where-the-remote-system-will-be-mounted"
SSHFS_USER="your-username"
SSHFS_PORT="22"

BACKUP_ROOT="/where-you-will-keep-your-backups"
BACKUP_DATE=`date +"%Y-%m-%d_%H:%M"`

COMPACT_REPOS="false"
DAILIES_TO_RETAIN="7"
WEEKLIES_TO_RETAIN="4"

LINGER_ON_EXIT="true"

# =============
# Mise en place
# =============

ERRORLEVEL=0
SUCCESSES="false"
FAILURES="false"
declare -A STATA

_backup() {
    DATA_PATH=$1
    FULL_REPO_PATH="$BACKUP_ROOT"/"$DATA_HOST""$DATA_PATH"
    printf "Backing up $DATA_HOST$DATA_PATH to $BACKUP_ROOT$DATA_PATH\n"
    borg create --stats --list "$FULL_REPO_PATH"::"$BACKUP_DATE" "$SSHFS_MOUNTPOINT""$DATA_PATH"
    if [[ $? -eq 0 ]]
        then printf "Success.\n\n"
        STATA["${DATA_PATH}"]="SUCCESS"
        SUCCESSES="true"
        if [[ $COMPACT_REPOS == "true" ]]
            then borg --progress compact "$FULL_REPO_PATH"
        fi
        printf "Pruning $FULL_REPO_PATH...\n"
        borg prune --list --keep-daily="$DAILIES_TO_RETAIN" --keep-weekly="$WEEKLIES_TO_RETAIN" "$FULL_REPO_PATH"
        if [[ ! $? -eq 0 ]]
            then ERRORLEVEL=1
            FAILURES="true"
        fi
        printf "\n"
        else STATA["${DATA_PATH}"]="$?"
        ERRORLEVEL=1
        FAILURES="true"
        printf "\n"
    fi
}

_delete_mountpoint() {
    if [[ ! "$(ls -A $SSHFS_MOUNTPOINT)" ]]
        then printf "Deleting mountpoint $SSHFS_MOUNTPOINT...\n"
        rmdir "$SSHFS_MOUNTPOINT"
        if [[ $? -eq 0 ]]
            then printf "Deleted.\n\n"
            else printf "Failed to delete the mountpoint.\n\n"
            ERRORLEVEL=1
        fi
        else printf "Not deleting the mountpoint at $SSHFS_MOUNTPOINT\nbecause it looks like there’s still something in it. Weird.\n\n"
        ERRORLEVEL=1
    fi
}

_exit() {
    if [[ $ERRORLEVEL -eq 0 ]]
        then if [[ $LINGER_ON_EXIT -eq "true" ]]
            then printf "This message will self-destruct.\n\n"
            sleep 5
        fi
        exit 0
        else if [[ $LINGER_ON_EXIT == "true" ]]
            then read -n1 -r -p "Press any key to dismiss."
        fi
        exit 1
    fi
}

# ====
# Prep
# ====

printf "\nWe’re about to back up the following remote directories from $DATA_HOST:\n"
for i in "${DATA_PATHS[@]}"
do
    printf "• $i\n"
done
printf "\n"

if [[ ! -d "$SSHFS_MOUNTPOINT" ]]
    then printf "Creating mountpoint $SSHFS_MOUNTPOINT...\n"
    mkdir "$SSHFS_MOUNTPOINT"
    if [[ ! $? -eq 0 ]]
        then printf "We seem to be having trouble creating the SSHFS mountpoint. Aborting!\n\n"
        ERRORLEVEL=1
        _exit
        else printf "Success.\n\n"
    fi
fi

printf "Mounting $DATA_HOST at $SSHFS_MOUNTPOINT...\n"
sshfs -o ro,port="$SSHFS_PORT" "$SSHFS_USER"@"$DATA_HOST":/ "$SSHFS_MOUNTPOINT"
if [[ $? -eq 0 ]]
    then printf "Success.\n\n"
    else printf "We seem to be having trouble mounting the remote remote file system.\n\n"
    ERRORLEVEL=1
    _delete_mountpoint
    _exit
fi

# =================
# Backup operations
# =================

for i in "${DATA_PATHS[@]}"
do
    _backup $i
done

# ==========
# Denouement
# ==========

printf "Unmounting $DATA_HOST from $SSHFS_MOUNTPOINT...\n"
fusermount -u "$SSHFS_MOUNTPOINT"
if [[ $? -eq 0 ]]
    then printf "Success.\n\n"
    _delete_mountpoint
    else printf "We’re having trouble unmounting the remote file system at $SSHFS_MOUNTPOINT.\n"
    printf "You’ll probably want to take a look at it.\n\n"
    ERRORLEVEL=1
fi

printf "==========\nCONCLUSION\n==========\n\n"
if [[ $SUCCESSES == "true" ]]
    then printf "The following locations backed up successfully:\n"
    for i in "${DATA_PATHS[@]}"
    do
        if [[ ${STATA[${i}]} -eq "SUCCESS" ]]
            then printf "• $i\n"
        fi
    done
    printf "\n"
fi
if [[ $FAILURES == "true" ]]
    then printf "The following locations experienced errors:\n"
    for i in "${DATA_PATHS[@]}"
    do
        if [[ ! ${STATA[${i}]} -eq "SUCCESS" ]]
            then printf "\e[31m• $i\n"
        fi
    done
    printf "\n"
fi

_exit