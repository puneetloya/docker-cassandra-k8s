#!/bin/bash

# function alert_failure() {
#   content=$1
#   file="${CASSANDRA_CLUSTER_NAME}_$(hostname)"
#   resource="/$AWS_BUCKET/failures/${file}"
#   contentType="text/plain"
#   dateValue=`date -u "+%Y%m%d"`
#   stringToSign="PUT\n\n${contentType}\n${dateValue}\n${resource}"
#
#   stringToSign="PUT\n"
#   dateStamp=`date -u "+%Y%m%dT%H%M%SZ"`
#   stringToSign="AWS4-HMAC-SHA256"
#
#   # Create Signature Key
#   keyDate=`echo AWS4${AWS_SECRET_ACCESS_KEY}$dateValue | sha256sum | cut -d " " -f 1`
#   keyRegion=`echo ${keyDate}${SL_REGION} | sha256sum | cut -d " " -f 1`
#   keyService=`echo ${keyRegion}s3 | sha256sum | cut -d " " -f 1`
#   keySign=`echo ${keyService}aws4_request | sha256sum | cut -d " " -f 1`
#
#
#   signature=`echo -en ${stringToSign} | openssl sha1 -hmac ${AWS_SECRET_ACCESS_KEY} -binary | base64`
#
#   echo -e ${content} >> $file
#   curl -X PUT -T "${file}" \
#     -H "Host: ${AWS_BUCKET}.${S3_ENDPOINT}" \
#     -H "Date: ${dateValue}" \
#     -H "Content-Type: ${contentType}" \
#     -H "Authorization: AWS ${AWS_ACCESS_KEY_ID}:${signature}" \
#     https://${AWS_BUCKET}.s3-eu-west-1.amazonaws.com/failures/${file}
#   rm -f $file
# }

function clean() {
  echo "[+] Cleaning"
  /usr/local/apache-cassandra/bin/nodetool clearsnapshot
  rm -Rf /snap /tmp/snapshot2s3.log
}

# Create lock or stop if already present
function create_lock() {
  if [ -f /tmp/snapshot2s3.lock ] ; then
    echo "Backup or restore is already in progress for $CLUSTER_DOMAIN/$CASSANDRA_CLUSTER_NAME/$(hostname)"
    exit 0
  fi
}

function release_lock() {
  rm -Rf /tmp/snapshot2s3.lock
}

function backup() {

  create_lock
  clean

  export LC_ALL=C
  snap_name="snapshot_$(date +%Y-%m-%d_%H-%M-%S)"

  # Create snapshot
  echo "[+] Starting Snapshot"
  /usr/local/apache-cassandra/bin/nodetool snapshot -t $snap_name > /tmp/snapshot2s3.log 2>&1
  if [ $? != 0 ] ; then
    echo "Error during snapshot, please check manually, cleaning before exit"
    #alert_failure "Error during snaptshot:\n$(cat /tmp/snapshot2s3.log)"
    clean
    release_lock
    exit 1
  fi
  cat /tmp/snapshot2s3.log

  # Create temporary folder
  find /var/lib/cassandra/data -name $snap_name -exec mkdir -p /snap/{} \;

  # Make snapshot symlinks
  cd /snap
  for i in $(find . -name $snap_name | sed 's/^.\///') ; do
    rmdir /snap/$i
    ln -s /$i /snap/$i
  done

  # Dump schemas
  mkdir -p /snap/var/lib/cassandra/schemas
  for schema in $(cqlsh -e "select keyspace_name from system_schema.keyspaces;" | egrep "^\s+" | awk '{ print $1 }' | grep -v keyspace_name) ; do
    cqlsh -e "describe keyspace ${schema}" > /snap/var/lib/cassandra/schemas/${schema}.cql
    if [ $? != 0 ] ; then
      echo "Error while dumping schema ${schema}"
      #alert_failure "Error while dumping ${schema} schema"
      clean
      release_lock
      exit 1
    fi
  done

  tar -cvf ${snap_name}.tar.gz /snap/
  echo "[+] Running ascp to transfer to s3"
  if ascp -L / -d -l 500M --mode=send -P 33001 --user ${BACKUP_USER} --host ${BACKUP_HOST} -i /backup.key --tags "{\"aspera\": { \"node\": { \"file_id\":\"${BACKUP_FOLDER_ID}\",\"access_key\":\"${ACCESS_KEY}\" }}}" -d ${snap_name}.tar.gz '/'; then
    echo '{ "message" : "Cassandra backup okay", "tags": "cassandra_backup" }'
    exit 0
  else
    echo '{ "mesaage" : "Cassandra backup FAILED.", "tags": "cassandra_backup"  }'
    cat ./aspera-scp-transfer.log
    exit 1
  fi
  rm -rf ${snap_name}.tar.gz /snap/
  if [ $? != 0 ] ; then
    echo "Error while backup $CLUSTER_DOMAIN/$CASSANDRA_CLUSTER_NAME/$(hostname)"
    #alert_failure "Error with duplicity\n$(cat /tmp/snapshot2s3.log)"
  fi
  cat /tmp/snapshot2s3.log

  # Clean snapshot
  clean
  release_lock
}

function restore() {
  create_lock

  echo "[+] Running duplicity to restore from AWS"
  # duplicity {{ default "--archive-dir /var/lib/cassandra/.duplicity --allow-source-mismatch --s3-european-buckets --s3-use-new-style --copy-links --num-retries 3 --s3-use-multiprocessing --s3-multipart-chunk-size 100 --volsize 1024" .Values.cassandraBackup.duplicityOptions }} --time $RESTORE_TIME {{ .Values.cassandraBackup.awsDestinationPath }} {{ .Values.cassandraBackup.restoreFolder }} > /tmp/snapshot2s3.log 2>&1
  if [ $? != 0 ] ; then
    echo "Error while restoring $CLUSTER_DOMAIN/$CASSANDRA_CLUSTER_NAME/$(hostname)"
    #alert_failure "Error with duplicity\n$(cat /tmp/snapshot2s3.log)"
  fi
  cat /tmp/snapshot2s3.log

  # Clean snapshot
  clean
  release_lock
}

function list() {
  duplicity {{ default "--archive-dir /var/lib/cassandra/.duplicity --allow-source-mismatch --s3-european-buckets --s3-use-new-style --copy-links --num-retries 3 --s3-use-multiprocessing --s3-multipart-chunk-size 100 --volsize 1024" .Values.cassandraBackup.duplicityOptions }} collection-status {{ .Values.cassandraBackup.awsDestinationPath }}
}

function help() {
  echo "Usage: $0 [backup|restore|list] AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_PASSPHRASE AWS_BUCKET [RESTORE_TIME]"
  exit 1
}

    # Check number of args
test "$#" -lt 5 && help

source /usr/local/apache-cassandra/scripts/envVars.sh
export AWS_ACCESS_KEY_ID=$2
export AWS_SECRET_ACCESS_KEY=$3
export PASSPHRASE=$4
export AWS_BUCKET=$5
export RESTORE_TIME=$6

if [ $1 == "backup" ] ; then
  backup
elif [ $1 == "restore" ] ; then
  test "$#" -ne 6 && help
  restore
elif [ $1 == "list" ] ; then
  list
else
  echo "Don't know what to do, please look help at ./$0"
fi
