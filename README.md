Chef Easy Restore
===================

Useful scripts for backup and restore of chef-server

How to easy backup and restore chef-opscode server 11.x and 12.x
=====

    ./chef_backup.sh --backup                  # for backup
    ./chef_backup.sh --restore </from>.tar.bz2 # for restore
    ./chef_backup.sh --pushtos3                # push backup to S3"


Dependencies
============

* bzip2
* s3cmd (only if pushing backups to S3)

