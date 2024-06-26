#!/bin/bash
#############################################################################################
# Script 		: The code of Dissolution Dissolution Algorithm.sh 
# Description		: The results of the experiments in this paper indicate that the proposed framework appears efficient in a practical situation based on the outcomes.
# Input parameters 	: 1 DBNAME
#		   			: 2 PARALLELISM  (Default value is 2)
#					: 3 BACKUP TYEP i.e. FULL or INCRL0 or INCRL1 or FINAL (Default value is FULL)
#					: 4 SECTION SIZE (Default values is 2g)
#
# Requirments		: db_file_recovery_dest (Flash recovery area) must be set 
#			  in the database. (/u03/oradata/backup)
# Called by		: None.
# Calling script	: None.
#
# Modification history 
# Date		    Created by			Version		Details
# -----------	-----------			-------		--------------------------------------------------
# 02-May-2024	Vaheed & Natarajan	1.0			First Version and Tested on Cloud Oracle Databases

#############################################################################################
#set -x
# Verify the number of input parameters.
if [ $# -lt 1 ]
then
 echo "###################################################################################"
 echo "#Usage for full backup: $0 DBNAME [PARALLELISM]"
 echo "#Ex: $0 oprbid 2"
 echo "#Usage for incr backup: $0 DBNAME PARALLELISM BACKUP_TYPE [SECTION_SIZE]"
 echo "#Ex: $0 oprbid 4 INCRL0/INCRL1 8g"
 echo "###################################################################################"
 exit 1

fi

export DBNAME=${1%[0-9]}
# Set minimum parallelism to 2
export RMAN_PARALLELISM=${2:-2}
export BACKUP_TYPE=${3:-FULL}
export SECTION_SIZE=${4:-8g}

# Set databse environment
#export PATH=/usr/ccs/bin:/usr/local/bin:/bin:/usr/bin:.
#export ORAENV_ASK=NO
#. oraenv


#Set variable for the job
export START_TIME=`date +"%Y%m%dT%H%M%S"`
export DBA=/u02/oradata/dba
export SCR_DIR=$DBA/scripts
export LOG_DIR=$DBA/log
export LOG_FILE=$LOG_DIR/rman_db_backup_${DBNAME}_${START_TIME}.log
export BACKUP_HIST_FILE=$LOG_DIR/rman_db_backup_history.log
export BACKUP_TAG=${DBNAME}_${BACKUP_TYPE}_`date +%Y%m%d`
export NLS_DATE_FORMAT='dd-MON-yyyy hh24:mi:ss'
export NOTIFY_LIST=oracle-dba@altisource.com
export PASSWD=`grep -v ^# /u02/oradata/dba/scripts/.bkp`

#Setting ORACLE_HOME
export ORACLE_HOME=/u01/app/oracle/product/11.2.0.3/db_1
export PATH=$PATH:$ORACLE_HOME/bin

#Get the db_recovery_file_dest from database.
SNAP_CTL_FILE_LOC=`(sqlplus -s << EOF1
rman_backup/$PASSWD@${DBNAME}_BACKUP as sysdba
set pages 0 term off feed off
select r.name
from sys.v\\$recovery_file_dest r;
exit;
EOF1
)`

if [ -d $SNAP_CTL_FILE_LOC ]
then
  export SNAP_CTL_FILE_LOC
else
  echo "RMAN backup failed to start for $DBNAME as db_recovery_file_dest $SNAP_CTL_FILE_LOC is not available." >>$LOG_FILE
  echo "$DBNAME                  $BACKUP_TYPE    $START_TIME     $END_TIME       $BACKUP_TAG             FAILED" >> $BACKUP_HIST_FILE
  cat $LOG_FILE | mailx -s "FAILED:RMAN $BACKUP_TYPE backup for $DBNAME" $NOTIFY_LIST
  exit 1

fi

if [ $BACKUP_TYPE = "FULL" ]
then
rman nocatalog  <<EOF2 > $LOG_FILE
connect target  rman_backup/$PASSWD@${DBNAME}_BACKUP
run
{
configure controlfile autobackup on;
configure default device type to disk;
configure channel device type  disk  connect 'rman_backup/$PASSWD@${DBNAME}_BACKUP';
configure device type disk parallelism $RMAN_PARALLELISM backup type to compressed backupset;
crosscheck archivelog all;
backup tag "$BACKUP_TAG" filesperset 2 database plus archivelog delete input;
CONFIGURE CHANNEL DEVICE TYPE DISK clear;
}

sql "alter database backup controlfile to trace as ''$SNAP_CTL_FILE_LOC/${DBNAME}_ctl_file.trc'' reuse";

exit;
EOF2

else
  if [ $BACKUP_TYPE = "INCRL0" ]
  then
rman nocatalog <<EOF3 > $LOG_FILE
connect target  rman_backup/$PASSWD@${DBNAME}_BACKUP
run
{
configure controlfile autobackup on;
configure default device type to disk;
configure channel device type  disk  connect  'rman_backup/$PASSWD@${DBNAME}_BACKUP';
configure device type disk parallelism $RMAN_PARALLELISM backup type to compressed backupset;
crosscheck archivelog all;
startup nomount;
restore controlfile from service 'primary-cloud-server';
restore database from service 'primary-cloud-server';
alter session set container =ORCLPDB1;
CONFIGURE CHANNEL DEVICE TYPE DISK clear;
}

sql "alter database backup controlfile to trace as ''$SNAP_CTL_FILE_LOC/${DBNAME}_ctl_file.trc'' reuse";

exit;
EOF3

else
 if [ $BACKUP_TYPE = "INCRL1" ]
  then
rman nocatalog <<EOF4 > $LOG_FILE
connect target  rman_backup/$PASSWD@${DBNAME}_BACKUP
run
{
configure controlfile autobackup on;
configure default device type to disk;
configure channel device type  disk  connect  'rman_backup/$PASSWD@${DBNAME}_BACKUP';  
configure device type disk parallelism $RMAN_PARALLELISM backup type to compressed backupset; 
recover database from service 'primary-cloud-server';
CONFIGURE CHANNEL DEVICE TYPE DISK clear;
}

sql "alter database backup controlfile to trace as ''$SNAP_CTL_FILE_LOC/${DBNAME}_ctl_file.trc'' reuse";

exit;
EOF4

else
 if [ $BACKUP_TYPE = "FINAL" ]
  then
rman nocatalog <<EOF5 > $LOG_FILE
connect target  rman_backup/$PASSWD@${DBNAME}_BACKUP
run
{
configure controlfile autobackup on;
configure default device type to disk;
configure channel device type  disk  connect  'rman_backup/$PASSWD@${DBNAME}_BACKUP';  
configure device type disk parallelism $RMAN_PARALLELISM backup type to compressed backupset; 
recover database from service 'primary-cloud-server';
recover database;
alter database open resetlogs;
CONFIGURE CHANNEL DEVICE TYPE DISK clear;
}

sql "alter database backup controlfile to trace as ''$SNAP_CTL_FILE_LOC/${DBNAME}_ctl_file.trc'' reuse";

exit;
EOF5

else
 echo "###################################################################################"
 echo "#Pass the correct parameters to script"
 echo "#Usage for full backup: $0 DBNAME [PARALLELISM]"
 echo "#Ex: $0 oprbid 2"
 echo "#Usage for incr backup: $0 DBNAME PARALLELISM BACKUP_TYPE [SECTION_SIZE]"
 echo "#Ex: $0 oprbid 4 INCRL0/INCRL1 8g"
 echo "###################################################################################"
 exit 1;
fi

fi
fi

export END_TIME=`date +"%Y%m%dT%H%M%S"`

if [ `egrep -c '^RMAN-00569|ORA-' $LOG_FILE` -gt 0 ]
then
 echo "$DBNAME  		$BACKUP_TYPE	$START_TIME	$END_TIME	$BACKUP_TAG		FAILED" >> $BACKUP_HIST_FILE
 cat $LOG_FILE | mailx -s "FAILED:RMAN $BACKUP_TYPE backup for $DBNAME" $NOTIFY_LIST
 exit 1

fi

echo "$DBNAME	        	$BACKUP_TYPE	$START_TIME	$END_TIME	$BACKUP_TAG     	SUCCESS" >> $BACKUP_HIST_FILE

if [ -d $SNAP_CTL_FILE_LOC/log ]
then
  cp $LOG_FILE $SNAP_CTL_FILE_LOC/log
  find $SNAP_CTL_FILE_LOC/log -name "*.log"  -mtime +7 -exec rm {} \;
else
 mkdir -p $SNAP_CTL_FILE_LOC/log
 cp $LOG_FILE $SNAP_CTL_FILE_LOC/log
fi


exit 0

