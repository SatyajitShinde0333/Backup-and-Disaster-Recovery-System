# BackupToS3

This is a highly configurable Bash script to backup MySQL databases, folders, zip them, and then upload them to AWS S3. Simply download the code, copy the example config file to a ```.settings.conf``` file, edit your settings and then run the backup script.

To download the code use:

```git clone https://github.com/RepositoriumCodice/BackupToS3```

This tool can also: 
- run pre/post scripts before backing a MySQL database or folder
- convert MyISAM tables to InnoDB
- clean up after itself

## Dependencies

You will need to install MySQL for the script to: dump databases, execute SQL commands and check if connectivity is OK. Additionally, it will require the AWS CLI tools to be installed. 

Both MySQL and the AWS CLI required that you provide credentials for authentication.

For MySQL use the following command:
- ````mysql_config_editor set --login-path=BACKUP_OPERATOR --user=backup_user --password````
- The login path for this script is set to "BACKUP_OPERATOR". You can change it in the configuration.
- You can create any user and change ```backup_user``` to your own.

Below is example SQL to create a backup user:

````
CREATE USER 'backup_user'@'%' IDENTIFIED BY 'verySecurePassword123!';
GRANT ALTER, SELECT, SHOW VIEW, PROCESS, LOCK TABLES ON *.* TO 'backup_user'@'%';
FLUSH privileges;
````

For the AWS CLI use the following command:
- ````aws configure````
- The login profile for this script is set to "default". You can change it in the configuration.

## File Structure

This following file structure is used:
- /backup.sh - The main script doing all the magic!
- /example.settings.conf - An example configuration file. This file is required.
- /.settings.conf - Create manually or on first run. Change this file as is required.
- /actions/mysql/* - The custom before and after scripts for each database. This folder is optional and is manually created.
- /actions/folders/* - The custom before and after scripts for each folder archive. This folder is optional and is manually created.
- /backups/* - This is where all backups are stored, until cleanup. This folder is auto-created when the script runs.
- /logs/* - This is log summary folder. This folder is auto-created when the script runs. 

## Features ##

### Before/After Action Scripts ###

Some applications like NextCloud (a brilliant open-source file storage hub), requires you to take the application into maintenance mode. You can use the same concept here for folder archives. You need to make sure that these action script have the correct permissions like ````chmod +x````.

Using a before script for a database called "NextCloud", you can turn maintenance mode to on:

./action/mysql/$DATABASE/before.sh

````
/usr/bin/docker exec --user www-data NextCloud php occ maintenance:mode --on
````
Using a after script for a database called "NextCloud", you can turn maintenance mode to off:

./action/mysql/$DATABASE/before.sh

````
/usr/bin/docker exec --user www-data NextCloud php occ maintenance:mode --off
````

### Convert MyISAM to InnoDB ###

Here are some reasons to use InnoDB vs MyISAM:
- InnoDB has row-level locking. MyISAM locks a full table.
- InnoDB has referential integrity which support foreign keys and relationship constraints. MyISAM does not.
- InnoDB supports transactions, commits and roll back. MyISAM does not.
- InnoDB is more reliable as it uses transactional logs for auto recovery. MyISAM does not.

Sometimes WordPress plugins create MyISAM tables, this backup script will ensure these are converted before backup.

## Settings

The following major settings can be applied in the settings.conf file:

### MySQL Backups ###

The following settings can be found in settings.conf under: MYSQL BACKUP SETTINGS.

````
# Host address for the MySQL database
MYSQL_HOST=mysql.server.com

# Port for the MySQL database
MYSQL_PORT=3306

# Create your credentials using: 
# -> mysql_config_editor set --login-path=BACKUP_OPERATOR --user=localuser --password

MYSQL_LOGIN_PATH="BACKUP_OPERATOR"

# Convert MyISAM tables to InnoDB tables. Values: 0=disable, 1=enable
# This will require the MySQL user to have "alter" grants. Unless you are using MyISAM 
# for a specific reason, you should be using the InnoDB storage engine.

MYSQL_CONVERT_TO_INNODB=1

# Dump options to improve MySQL backup performance.
#
# Assuming you are using:
#   - InnoDB tables, set: MYSQL_DUMP_OPTIONS="--single-transaction --skip-lock-tables"
#   - MyISAM and InnoDB, set: MYSQL_DUMP_OPTIONS=""
#   - A mix of both, set: MYSQL_DUMP_OPTIONS=""
#   NOTE: The wrong setting can leave your data in an inconsistent state!!!!
#         --> If in doubt then use: MYSQL_DUMP_OPTIONS=""

MYSQL_DUMP_OPTIONS="--single-transaction --skip-lock-tables"

# Database names to backup. Values: "", "ALL" or for example: "wordpress-db invoiceninja otherdb"
DB_NAMES="ALL"

````

### Folder Backups ###

The following settings can be found in settings.conf under: FOLDER BACKUP SETTINGS.

````
# Number of archive folders to process. Values: 0, and up.
TOTAL_ARCHIVE_FOLDERS=2

# Each folder is handled in a recursive manner.
# Do not use ~ in the path.
# Add or remove below to match $TOTAL_ARCHIVE_FOLDERS.
FOLDER_1_ARCHIVE_PATHS="/home/anthony/Some Folder"
FOLDER_1_ARCHIVE_NAME="SomeFolder"

FOLDER_2_ARCHIVE_PATHS="/home/anthony/Some-Other-Folder"
FOLDER_2_ARCHIVE_NAME="SomeOtherFolder"
````

### AWS S3 Backups ###

The following settings can be found in settings.conf under: AWS S3 BACKUP SETTINGS.

````
# Enable AWS S3. Values: 0=disable, 1=enable 
S3_ENABLE=1

# Create your credentials using: aws configure

# S3 Bucket name
S3_BUCKET_NAME="backups"

# S3 Bucket Location. Values: Path without start and end slash
S3_UPLOAD_LOCATION="backups"

# S3 Region
S3_REGION="ap-southeast-2"

# S3 Profile
S3_PROFILE="default"
````

## Sample Output ##

````
root@server:~/$ ./backup.sh 
Starting backup script as: root

# Convert tables to InnoDB (If any)

  ------

# Dumping Databases  (If any) [--single-transaction --set-gtid-purged=OFF --skip-lock-tables]

- Backup database: 1009383938_wordpress
- Uploading backup file to S3 Bucket
upload: backups/1009383938_wordpress.2021-03-13-15-43.sql.gz to s3://backups/backups/1009383938_wordpress.2021-03-13-15-43.sql.gz

- Backup database: innodb
- Uploading backup file to S3 Bucket
upload: backups/innodb.2021-03-13-15-43.sql.gz to s3://backups/backups/innodb.2021-03-13-15-43.sql.gz

  ------

# Backing up folders (If any)

Backup Folder: /home/root/Some Folder... 
- Uploading backup file to S3 Bucket
upload: backups/SomeFolder.2021-03-13-15-43.tar.gz to s3://backups/backups/SomeFolder.2021-03-13-15-43.tar.gz

Backup Folder: /home/root/Some-Other-Folder... 
- Uploading backup file to S3 Bucket
upload: backups/SomeOtherFolder.2021-03-13-15-43.tar.gz to s3://backups/backups/SomeOtherFolder.2021-03-13-15-43.tar.gz

  ------

# Removing old backups

  ------
````  

# Want to connect?

Feel free to contact me on [Twitter](https://twitter.com/OnlineAnto), [DEV Community](https://dev.to/antoonline/) or [LinkedIn](https://www.linkedin.com/in/anto-online) if you have any questions or suggestions.

Or just visit my [website](https://anto.online) to see what I do.
