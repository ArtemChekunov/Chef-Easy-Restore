#!/usr/bin/env bash
# Author: Arem Chekunov
# Author email: scorp.dev.null@gmail.com
# repo: https://github.com/sc0rp1us/cehf-useful-scripts
# env and func's
_BACKUP_NAME="chef-backup_$(date +%Y-%m-%d)"
_BACKUP_USER="backup"
_BACKUP_GROUP="backup"
_BACKUP_DIR="/var/backups"
_CHEF_DATA_DIR="/var/opt/chef-server"
_SYS_TMP="/tmp"
_PUSHTOS3="false"
_S3_SUCCESS_STAMP="${_BACKUP_DIR}/chef-backup/s3_push_timestamp"

cd "$(dirname $0)"

if [ -f ../etc/chef-backup.conf ]; then
    . ../etc/chef-backup.conf
fi

_TMP="${_SYS_TMP}/${_BACKUP_NAME}"

_pg_dump(){
    su - opscode-pgsql -c "/opt/chef-server/embedded/bin/pg_dump -c opscode_chef"
}

syntax(){
    echo ""
    echo -e "\t$0 --backup                  # for backup"
    echo -e "\t$0 --restore </from>.tar.bz2 # for restore"
    echo -e "\t$0 --pushtos3                # push backup to S3"
    echo ""
}

_chefBackup(){
    echo "Backup function"

    id ${_BACKUP_USER} &> /dev/null
    _BACKUP_USER_EXIST=$?
    if [[ ${_BACKUP_USER_EXIST} -ne 0 ]]; then
        echo "You should to have backup user"
    fi

    set -e
    set -x

    # Create folders
    mkdir -p ${_TMP}
    mkdir -p ${_TMP}/nginx
    mkdir -p ${_TMP}/cookbooks
    mkdir -p ${_TMP}/postgresql
    mkdir -p ${_BACKUP_DIR}/chef-backup

    # Backp of files
    cp -a ${_CHEF_DATA_DIR}/nginx/{ca,etc} ${_TMP}/nginx
    cp -a ${_CHEF_DATA_DIR}/bookshelf/data/bookshelf/ ${_TMP}/cookbooks

    # Backup of database
    _pg_dump > ${_TMP}/postgresql/pg_opscode_chef.sql

    cd ${_SYS_TMP}
    if [[ -e ${_BACKUP_DIR}/chef-backup/chef-backup.tar.bz2 ]]; then
        mv ${_BACKUP_DIR}/chef-backup/chef-backup.tar.bz2{,.previous}
    fi
    tar cjfP ${_BACKUP_DIR}/chef-backup/chef-backup.tar.bz2 ${_SYS_TMP}/${_BACKUP_NAME}
    chown -R ${_BACKUP_USER}:${_BACKUP_GROUP} ${_BACKUP_DIR}/chef-backup/
    chmod -R o-rwx ${_BACKUP_DIR}/chef-backup/

    rm -Rf ${_TMP}
}


_chefRestore(){
    echo "Restore function"
    _TMP_RESTORE=${_SYS_TMP}/chef-restore/ ; mkdir -p ${_TMP_RESTORE}
    if [[ ! -f ${source} ]]; then
        echo "ERROR: Restore source file ${source} do not exist.  The source must be a fully qualified path"
        exit 1
    fi

    set -e
    set -x

    tar xjfp "${source}" -C ${_TMP_RESTORE}
    mv ${_CHEF_DATA_DIR}/nginx/ca{,.$(date +%Y-%m-%d_%H:%M:%S).bak}
    mv ${_CHEF_DATA_DIR}/nginx/etc{,.$(date +%Y-%m-%d_%H:%M:%S).bak}
    if [[ -d ${_CHEF_DATA_DIR}/bookshelf/data/bookshelf ]]; then
        mv ${_CHEF_DATA_DIR}/bookshelf/data/bookshelf{,.$(date +%Y-%m-%d_%H:%M:%S).bak}
    fi
    _pg_dump > ${_CHEF_DATA_DIR}/pg_opscode_chef.sql.$(date +%Y-%m-%d_%H:%M:%S).bak

    cd ${_TMP_RESTORE}/tmp/*
    _TMP_RESTORE_D=$(pwd)

    chef-server-ctl reconfigure
    su - opscode-pgsql -c "/opt/chef-server/embedded/bin/psql -U opscode-pgsql opscode_chef" < ${_TMP_RESTORE_D}/postgresql/pg_opscode_chef.sql
    chef-server-ctl stop

    cp -a ${_TMP_RESTORE_D}/nginx/ca/              ${_CHEF_DATA_DIR}/nginx/
    cp -a ${_TMP_RESTORE_D}/nginx/etc/             ${_CHEF_DATA_DIR}/nginx/
    cp -a ${_TMP_RESTORE_D}/cookbooks/bookshelf/   ${_CHEF_DATA_DIR}/bookshelf/data/


    chef-server-ctl start
    sleep 30
    chef-server-ctl reindex

    cd ~
    rm -Rf ${_TMP_RESTORE}
}

_pushToS3(){
    if [[ ! -x /usr/bin/s3cmd ]]; then
        echo "Pushing backups to S3 requires the s3cmd command."
        exit 1
    fi

    if [[ -z ${_S3_URI} ]]; then
        echo "To push backups to S3 you must set the _S3_URI variable within chef-backup.conf"
        exit 1
    fi

    s3cmd put ${_BACKUP_DIR}/chef-backup/chef-backup.tar.bz2 ${_S3_URI}/chef-backup-$(date +%m_%d_%Y-%H_%M_%S).tar.gz
    touch ${_S3_SUCCESS_STAMP}

}

# make sure chef 11 is installed
if [[ ! -x /opt/chef-server/embedded/bin/pg_dump ]]; then
    echo "This script can only run on Chef server version 11."
    exit 1
fi

# make sure the script is run as root
if [[ $(id -u) -ne 0 ]]; then
    echo "You must be root to run this script."
    exit 1
fi

# parse the args passed in via cli
while [ "$#" -gt 0 ] ; do
    case "$1" in
        -h|--help)
            syntax
            exit 0
            ;;
        --backup)
            action="backup"
            shift 1
            ;;
        --restore)
            action="restore"
            source="${2}"
            break
            ;;
        --pushtos3)
            _PUSHTOS3="true"
            shift 1
            ;;
        *)
            syntax
            exit 1
            ;;

    esac
done

# perform back or restore based on action passed in
if [[ ${action} == "backup" ]]; then
    _chefBackup

    # optionally push the backup to S3
    if [[ ${_PUSHTOS3} == 'true' ]]; then
        _pushToS3
    fi
elif [[ ${action} == "restore" ]]; then
    _chefRestore
else
    syntax
    exit 1
fi
