#!/bin/bash

# Current script path
SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

# Name of config settings file
CONFIGFILE="$SCRIPTPATH/.settings.conf"

# Folder where the MySQL dumps and archive files are stored. 
BACKUP_PATH="$SCRIPTPATH/backups"

# Folder where logs are stored
LOG_PATH="$SCRIPTPATH/logs"

# The folder where custom before and after bash scripts are stored. These scripts 
# will execute before and after a backup occurs for a folder and database. Make 
# sure these files are executable, and the parent folder is correct. This allows 
# you to pause a system momentarily while the backup occurs.
#
# To set a "before" action script for a database called "myDatabase":
#   - Create: $ACTIONS/mysql/myDatabase/before.sh 
#   - This script will be executed before the database: "myDatabase", is backed up.
#
# To set a "after" action script for a database called "myDatabase":
#   - Create: $ACTIONS/mysql/myDatabase/after.sh 
#   - This script will be executed after the database: "myDatabase", is backed up.
#
# To set a "before" action script for a folder called "myFolder":
#   - Create: $ACTIONS/folders/myFolder/before.sh 
#   - This script will be executed before the folder: "myFolder", is backed up.
#
# To set a "after" action script for a folder called "myFolder":
#   - Create: $ACTIONS/folders/myFolder/after.sh 
#   - This script will be executed after the folder: "myFolder", is backed up.
ACTIONS_PATH="$SCRIPTPATH/actions"

# Make sure bins exists
check_bin_apps(){
    [ ! -x "$BASH" ] && missing_bin_app "$BASH"
    [ ! -x "$FIND" ] && missing_bin_app "$FIND"    
    [ ! -x "$GREP" ] && missing_bin_app "$GREP"
    [ ! -x "$GZIP" ] && missing_bin_app "$GZIP"
    [ ! -x "$MKDIR" ] && missing_bin_app "$MKDIR"
    [ ! -x "$MYSQL" ] && missing_bin_app "$MYSQL"
    [ ! -x "$MYSQLDUMP" ] && missing_bin_app "$MYSQLDUMP"
    [ ! -x "$MYSQLADMIN" ] && missing_bin_app "$MYSQLADMIN"
    [ ! -x "$RM" ] && missing_bin_app "$RM"
    [ ! -x "$TAR" ] && missing_bin_app "$TAR"
    [ ! -x "$TOUCH" ] && missing_bin_app "$TOUCH"
    if [ $S3_ENABLE -eq 1 ]; then
        [ ! -x "$AWSCLI" ] && missing_bin_app "$AWSCLI"
    fi
}

# Create folder if it does not exists
create_folder_if_not_exists(){
    if [ ! -d "$1" ]; then
        "$MKDIR" -p "$1"
        [ $VERBOSE -eq 1 ] && echo "Created folder $1"  
    fi
}

# Error if file does not exist
error_if_file_not_exists(){
    [ ! -f "$1" ] && exit_script "The following file does not exist: $1."
}

# Create file if it does not exists
create_file_if_not_exists(){
    [ ! -f "$1" ] && "$TOUCH" "$1"
}

# Exit with message
exit_script(){
    echo "$@"
    exit 1
}

# Exit due to missing app
missing_bin_app(){
    echo "Could not find bin app: $1. Check if its installed and fix the path in: $CONFIGFILE."
    exit 1
}

# Check if database connectin is working...
check_mysql_connection(){
    "$MYSQLADMIN" $CREDENTIALS -h $MYSQL_HOST -P $MYSQL_PORT ping | "$GREP" 'alive'>/dev/null
    [ $? -eq 0 ] || exit_script "Error: Cannot connect to MySQL Server. Make sure username and password setup correctly using mysql_config_editor. See $CONFIGFILE."
}

# Started a function output
echo_started() {
    [ $VERBOSE -eq 1 ] && echo "# $1"
    [ $VERBOSE -eq 1 ] && echo ""  
}

# Started a function output
echo_in_progress() {
    [ $VERBOSE -eq 1 ] && echo "- $1"
}

# Completed a function output
echo_completed() {
    [ $VERBOSE -eq 1 ] && echo "  ------"
    [ $VERBOSE -eq 1 ] && echo "" 
}

# Blank line output
echo_blank() {
    [ $VERBOSE -eq 1 ] && echo "" 
}

# Execute custom before and after actions
execute_action() {
    if [ -f "$ACTIONS_PATH/$1" ]; then
        "$BASH" "$ACTIONS_PATH/$1"
    fi
}

# Convert tables to innodb if required in settings
db_convert_to_innodb() {
    if [ $MYSQL_CONVERT_TO_INNODB -eq 1 ]; then
        echo_started "Convert tables to InnoDB (If any)"

        # Get the database names
        if [ "$DB_NAMES" == "ALL" ]; then
            DATABASES=`$MYSQL $CREDENTIALS -h $MYSQL_HOST -P $MYSQL_PORT -Bse 'show databases' | grep -Ev "^(Database|mysql|performance_schema|information_schema)"$`
        else
            DATABASES=$DB_NAMES
        fi
        
        for DATABASE in $DATABASES ; do
            # Check if the table is MyISAM
            TABLES=$(echo "SELECT TABLE_NAME FROM information_schema.TABLES where TABLE_SCHEMA = '$DATABASE' and ENGINE = 'MyISAM'" | $MYSQL $CREDENTIALS -h $MYSQL_HOST -P $MYSQL_PORT)
            
            for TABLE in $TABLES ; do
                if [ ! "$TABLE" == "TABLE_NAME" ]; then
                    echo_in_progress "Converting MyISAM $DATABASE $TABLE to InnoDB"
                    echo "ALTER TABLE $TABLE ENGINE = INNODB" | "$MYSQL" $CREDENTIALS -h $MYSQL_HOST -P $MYSQL_PORT $DATABASE
                fi
            done
        done

        echo_completed
    fi
}

# Backup the databases
db_backup(){
    echo_started "Dumping Databases  (If any) [$MYSQL_DUMP_OPTIONS]"
    echo "Databases Backed-up [$MYSQL_DUMP_OPTIONS]:" >> "$LOGFILENAME"  

    # Get the database names
    if [ "$DB_NAMES" == "ALL" ]; then
        DATABASES=`$MYSQL $CREDENTIALS -h $MYSQL_HOST -P $MYSQL_PORT -Bse 'show databases' | grep -Ev "^(Database|mysql|performance_schema|information_schema)"$`
    else
        DATABASES=$DB_NAMES
    fi

    create_folder_if_not_exists "$BACKUP_PATH"

    for DATABASE in $DATABASES
    do
        echo_in_progress "Backup database: $DATABASE"
        
        # Do some actions before the backup
        execute_action "mysql/$DATABASE/before.sh"
        
        # Do the actual backup
        FILE_NAME="$DATABASE.$CURRENT_DATE-$CURRENT_TIME.sql.gz"
        FILE_PATH="$BACKUP_PATH/"
        FILENAMEPATH="$FILE_PATH$FILE_NAME"
        "${MYSQLDUMP}" $CREDENTIALS -h $MYSQL_HOST -P $MYSQL_PORT $MYSQL_DUMP_OPTIONS $DATABASE | "$GZIP" -9 > "$FILENAMEPATH"
        echo "- $DATABASE" >> "$LOGFILENAME"
        
        # Do some actions after the backup
        execute_action "mysql/$DATABASE/after.sh"
       
        # Send the backup to a destination
        [ $S3_ENABLE -eq 1 ] && s3_backup

        echo_blank
    done

    echo "" >> "$LOGFILENAME"    
    echo_completed
}

# Backup the folders
folders_backup(){
    echo_started "Backing up folders (If any)"
    echo "Folders Backed Up:" >> "$LOGFILENAME"    

    create_folder_if_not_exists "$BACKUP_PATH"
    
    START=1
    for (( c=$START; c<=$TOTAL_ARCHIVE_FOLDERS; c++ ))
    do
        FOLDER_ARCHIVE_PATHS="FOLDER_"$c"_ARCHIVE_PATHS"
        FOLDER_ARCHIVE_NAME="FOLDER_"$c"_ARCHIVE_NAME"
        FILE_NAME="${!FOLDER_ARCHIVE_NAME}.$CURRENT_DATE-$CURRENT_TIME.tar.gz"

        [ $VERBOSE -eq 1 ] && echo -en "Backup Folder: ${!FOLDER_ARCHIVE_PATHS}... \n"
          
        FILE_PATH="$BACKUP_PATH/"
        FILENAMEPATH="$FILE_PATH$FILE_NAME"
        
        # Do some actions before the backup
        execute_action "folders/${!FOLDER_ARCHIVE_NAME}/before.sh"
        
        "$TAR" -zcf "$FILENAMEPATH" -C / "${!FOLDER_ARCHIVE_PATHS#?}"
        echo "- ${!FOLDER_ARCHIVE_PATHS}/*" >> "$LOGFILENAME"

        # Do some actions after the backup
        execute_action "folders/${!FOLDER_ARCHIVE_NAME}/after.sh"
       
        # Send the backup to a destination
        [ $S3_ENABLE -eq 1 ] && s3_backup

        echo_blank        
    done
    
    echo "" >> "$LOGFILENAME"    
    echo_completed
}

# Copy backup files to AWS S3 bucket
s3_backup(){
    echo_in_progress "Uploading backup file to S3 Bucket"
    "$AWSCLI" s3 --profile="$S3_PROFILE" --region="$S3_REGION" cp "$FILE_PATH/$FILE_NAME" "s3://$S3_BUCKET_NAME/$S3_UPLOAD_LOCATION/"
}

# Remove old files
remove_old_backups_and_logs(){
    echo_started "Removing old backups"

    "$FIND" "$BACKUP_PATH" -type f -name "*.tar.gz" -mtime "+$FILE_RETAIN_DAYS" -exec rm -f {} +
    "$FIND" "$BACKUP_PATH" -type f -name "*.sql.gz" -mtime "+$FILE_RETAIN_DAYS" -exec rm -f {} +
    "$FIND" "$LOG_PATH" -type f -name "*.log" -mtime "+$FILE_RETAIN_DAYS" -exec rm -f {} +

    echo_completed    
}

error_if_file_not_exists "$SCRIPTPATH/example.settings.conf"

if [ ! -f $CONFIGFILE ]; then
  cp "$SCRIPTPATH/example.settings.conf" $CONFIGFILE
fi

source $CONFIGFILE

check_bin_apps

DATE_FORMAT='%Y-%m-%d'
CURRENT_DATE=$(date +"${DATE_FORMAT}")
CURRENT_TIME=$(date +"%H-%M")
LOGFILENAME=$LOG_PATH/backup-log-$CURRENT_DATE-$CURRENT_TIME.log
CREDENTIALS="--login-path=$MYSQL_LOGIN_PATH"

create_folder_if_not_exists "$LOG_PATH"
create_file_if_not_exists "$LOGFILENAME"

# Write out current user
BASH_USER="$(id -u -n)"
[ $VERBOSE -eq 1 ] && echo "Starting backup script as: "$BASH_USER
[ $VERBOSE -eq 1 ] && echo ""

# Create log file
echo "" > "$LOGFILENAME"
echo "Backup Report : $CURRENT_DATE $CURRENT_TIME" >> "$LOGFILENAME"
echo "" >> "$LOGFILENAME"

### main ####

check_mysql_connection
db_convert_to_innodb
db_backup
folders_backup
remove_old_backups_and_logs