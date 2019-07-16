#!/bin/bash

S3_ENDPOINT="${S3_ENDPOINT:-http://s3.private.us.cloud-object-storage.appdomain.cloud}"
cassandra-backup ${KEYSPACE_NAME} \
--cluster ${CLUSTER_NAME} --id ${HOSTNAME} --bs IBM_COS \
--endpoint ${S3_ENDPOINT} -p /tmp/cassandra \
--bucket ${BUCKET_NAME} \
--jmx service:jmx:rmi:///jndi/rmi://:7199/jmxrmi --speed plaid
