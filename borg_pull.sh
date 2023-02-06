#!/bin/bash

# This script requires SSHFS and Borg.
# It backs up data from a remote location to a local repository.

# =============
# CONFIGURATION
# =============

# Hostname, domain name, or IP address of the machine where the data to be backed up resides.
DATA_HOST=""
# White-space-delimited list of absolute paths of directories on the remote machine to be backed up.
DATA_PATHS=( "" )

# Absolute local path where the remote system will be temporarily mounted locally.
# The directory will be created. Pick someplace to which you have write access.
SSHFS_MOUNTPOINT=""
# The username for the account on the remote machine as which we’ll be loggin in via SSH.
SSHFS_USER=""
SSHFS_PORT="8022"

# The absolute local path for the directory where the backups will be stored.
BACKUP_ROOT="/mnt/butter/backups"
# A command to generate the date stamp that will appear in a backup’s title.
BACKUP_DATE=$(date +"%Y-%m-%d_%H:%M")

# Whether or not to compacts repositories after backing up. I haven’t tested this
# because I have an older version of Borg that doesn’t support compacting.
COMPACT_REPOS="false"

DAILIES_TO_RETAIN="7"
WEEKLIES_TO_RETAIN="4"

# This script is intended to be run unattended. If this option is set to “true”,
# the script will pause for a few seconds before exiting if everything is successful,
# and wait for user input before exiting if anything goes wrong.
LINGER_ON_EXIT="true"

EMPHASIS_COLOR="\e[36m"
ERROR_COLOR="\e[91m"
SUCCESS_COLOR="\e[32m"
PROMPT_COLOR="\e[30;106m"

# =============
# Mise en place
# =============

NO_COLOR="\e[0m"
ERRORLEVEL=0
SUCCESSES="false"
PROBLEMS="false"
declare -A STATA

_backup() {
    DATA_PATH=$1
    FULL_REPO_PATH="${BACKUP_ROOT}/${DATA_HOST}${DATA_PATH}"
    printf "Backing up ${EMPHASIS_COLOR}%s%s${NO_COLOR}\nto %s%s...\n" "$DATA_HOST" "$DATA_PATH" "$BACKUP_ROOT" "$DATA_PATH"
    if borg create --stats --progress --exclude /*/lost+found "$FULL_REPO_PATH"::"$BACKUP_DATE" "$SSHFS_MOUNTPOINT""$DATA_PATH"
        then printf "%bSuccess.%b\n\n" "$SUCCESS_COLOR" "$NO_COLOR"
        STATA["${DATA_PATH}"]="SUCCESS"
        SUCCESSES="true"
        if [[ $COMPACT_REPOS == "true" ]]
            then borg --progress compact "$FULL_REPO_PATH"
        fi
        printf "Pruning %s...\n" "$FULL_REPO_PATH"
        if ! borg prune --keep-daily="$DAILIES_TO_RETAIN" --keep-weekly="$WEEKLIES_TO_RETAIN" "$FULL_REPO_PATH"
            then ERRORLEVEL=1
            PROBLEMS="true"
        fi
        printf "\n"

        else STATA["${DATA_PATH}"]="$?"
        ERRORLEVEL=1
        PROBLEMS="true"
        printf "\n"
    fi
}

_delete_mountpoint() {
    if [[ ! "$(ls -A $SSHFS_MOUNTPOINT)" ]]
        then printf "Deleting mountpoint %s...\n" "$SSHFS_MOUNTPOINT"
        if rmdir "$SSHFS_MOUNTPOINT"
            then printf "Deleted.\n\n"
            else printf "%bFailed to delete the mountpoint.%b\n\n" "$ERROR_COLOR" "$NO_COLOR"
            ERRORLEVEL=1
        fi
        else printf "%bNot deleting the mountpoint at %s\nbecause it looks like there’s still something in it. Weird.%b\n\n" "$ERROR_COLOR" "$SSHFS_MOUNTPOINT" "$NO_COLOR"
        ERRORLEVEL=1
    fi
}

_exit() {
    if [[ $ERRORLEVEL -eq 0 ]]
        then if [[ $LINGER_ON_EXIT == "true" ]]
            then printf "%bThis message will self-destruct.%b\n\n" "$PROMPT_COLOR" "$NO_COLOR"
            sleep 5
        exit 0
        fi
        elif [[ $LINGER_ON_EXIT == "true" ]]
            then printf "%b" "$PROMPT_COLOR"
            read -n1 -r -p "Press Enter to dismiss." input
            printf "%b\n" "$NO_COLOR"
            if [[ $input = "" ]]
            then exit 1
            else _exit
        fi
        exit 1
    fi
}

# ====
# Prep
# ====

printf "\nWe’re about to back up the following remote directories from %b%s%b:\n" "$EMPHASIS_COLOR" "${DATA_HOST}" "$NO_COLOR"
for i in "${DATA_PATHS[@]}"
do
    printf "• %b%s%b\n" "$EMPHASIS_COLOR" "${i}" "$NO_COLOR"
done
printf "\n"

if [[ ! -d "$SSHFS_MOUNTPOINT" ]]
    then printf "Creating mountpoint %s...\n" "$SSHFS_MOUNTPOINT"
    if mkdir "$SSHFS_MOUNTPOINT"
        then printf "Success.\n\n"
        else printf "%bWe seem to be having trouble creating the SSHFS mountpoint. Aborting!%b\n\n" "$ERROR_COLOR" "$NO_COLOR"
        ERRORLEVEL=1
        _exit
    fi
fi

printf "Mounting %s at %s...\n" "$DATA_HOST" "$SSHFS_MOUNTPOINT"
if sshfs -o ro,port="$SSHFS_PORT" "$SSHFS_USER"@"$DATA_HOST":/ "$SSHFS_MOUNTPOINT"
    then printf "Success.\n\n"
    else printf "%bWe seem to be having trouble mounting the remote remote file system.%b\n\n" "$ERROR_COLOR" "$NO_COLOR"
    ERRORLEVEL=1
    _delete_mountpoint
    _exit
fi

# =================
# Backup operations
# =================

for i in "${DATA_PATHS[@]}"
do
    _backup "$i"
done

# ==========
# Denouement
# ==========

printf "Unmounting %s from %s...\n" "$DATA_HOST" "$SSHFS_MOUNTPOINT"
if fusermount -u "$SSHFS_MOUNTPOINT"
    then printf "Success.\n\n"
    _delete_mountpoint
    else printf "%bWe’re having trouble unmounting the remote file system at %s.\n" "$ERROR_COLOR" "$SSHFS_MOUNTPOINT"
    printf "You’ll probably want to have a look at it.%b\n\n" "$NO_COLOR"
    ERRORLEVEL=1
fi

printf "%b==========\nCONCLUSION\n==========%b\n\n" "${EMPHASIS_COLOR}" "$NO_COLOR"
if [[ $SUCCESSES == "true" ]]
    then printf "The following locations backed up successfully:\n"
    for i in "${DATA_PATHS[@]}"
    do
        if [[ ${STATA[${i}]} == "SUCCESS" ]]
            then printf "• %b%s%b\n" "$EMPHASIS_COLOR" "$i" "$NO_COLOR"
        fi
    done
    printf "\n"
fi
if [[ $PROBLEMS == "true" ]]
    then printf "The following locations experienced issues:\n"
    for i in "${DATA_PATHS[@]}"
    do
        if [[ ! ${STATA[${i}]} == "SUCCESS" ]]
            then printf "• %b%s%b\n" "$ERROR_COLOR" "$i" "$NO_COLOR"
        fi
    done
    printf "\n"
fi

_exit