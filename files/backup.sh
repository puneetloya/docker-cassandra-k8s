#!/bin/bash

function clean() {
  echo "[+] Cleaning"
  /usr/local/apache-cassandra/bin/nodetool clearsnapshot
  rm -r /var/backup/cassandra/`hostname`/*.tar.gz
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
  prefix_dir="/usr/local/apache-cassandra"
  cassandra_dir="/var/lib/cassandra"
  keyspace="${CASSANDRA_KEYSPACE}"
  host=`hostname`
  backup_dir="/var/backup/cassandra/${host}"

  # Create snapshot
  echo "[+] Starting Snapshot"
  /usr/local/apache-cassandra/bin/nodetool snapshot -t ${snap_name} > /tmp/snapshot2s3.log 2>&1
  if [ $? != 0 ] ; then
    echo "Error during snapshot, please check manually, cleaning before exit"
    #alert_failure "Error during snaptshot:\n$(cat /tmp/snapshot2s3.log)"
    clean
    release_lock
    exit 1
  fi
  cat /tmp/snapshot2s3.log


  find /var/lib/cassandra/data -name ${snap_name} -print | while read f; do
    snap_dir=`echo $f | sed "s/snapshots\/${snap_name}//g"`
    mkdir -p ${cassandra_dir}/${snap_name}/${snap_dir}
    cp -r $f/* ${cassandra_dir}/${snap_name}/${snap_dir}
  done

  # Dump schemas
  # mkdir -p ${prefix_dir}/snap/var/lib/cassandra/schemas
  # for schema in $(cqlsh -e "select keyspace_name from system_schema.keyspaces;" | egrep "^\s+" | awk '{ print $1 }' | grep -v keyspace_name) ; do
  #   cqlsh -e "describe keyspace ${schema}" > ${prefix_dir}/snap/var/lib/cassandra/schemas/${schema}.cql
  #   if [ $? != 0 ] ; then
  #     echo "Error while dumping schema ${schema}"
  #     #alert_failure "Error while dumping ${schema} schema"
  #     clean
  #     release_lock
  #     exit 1
  #   fi
  # done
  mkdir -p ${backup_dir}
  tar -cf -  ${cassandra_dir}/${snap_name}  | pigz -9 > ${cassandra_dir}/${snap_name}.tar.gz
  mv ${cassandra_dir}/${snap_name}.tar.gz ${backup_dir}
  cat /tmp/snapshot2s3.log

  # Clean snapshot
  clean
  release_lock
}

function restore() {
  create_lock


  cat /tmp/snapshot2s3.log

  release_lock
}

function list() {
  duplicity {{ default "--archive-dir /var/lib/cassandra/.duplicity --allow-source-mismatch --s3-european-buckets --s3-use-new-style --copy-links --num-retries 3 --s3-use-multiprocessing --s3-multipart-chunk-size 100 --volsize 1024" .Values.cassandraBackup.duplicityOptions }} collection-status {{ .Values.cassandraBackup.awsDestinationPath }}
}

function help() {
  echo "Usage: $0 [backup|restore|list] AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_PASSPHRASE AWS_BUCKET [RESTORE_TIME]"
  exit 1
}


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
