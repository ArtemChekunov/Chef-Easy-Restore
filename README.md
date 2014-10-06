cehf-useful-scripts
===================

Useful scripts for administrator of chef-server

Usage
=====

    ./chef_backup.sh --backup                  # for backup
    ./chef_backup.sh --restore </from>.tar.bz2 # for restore
    ./chef_backup.sh --pushtos3               # push backup to S3"


Dependencies
============

* bzip2
* s3cmd (only if pushing backups to S3)

