# Copyright 2017 K8s For Greeks / Vorstella
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

FROM openjdk:8-jre-slim

ARG BUILD_DATE
ARG VCS_REF
ARG CASSANDRA_VERSION
ARG DEV_CONTAINER

LABEL \
    org.label-schema.build-date=$BUILD_DATE \
    org.label-schema.docker.dockerfile="/Dockerfile" \
    org.label-schema.license="Apache License 2.0" \
    org.label-schema.name="Cassandra container optimized for Kubernetes" \
    org.label-schema.url="https://github.com/k8s-for-greeks/" \
    org.label-schema.vcs-ref=$VCS_REF \
    org.label-schema.vcs-type="Git" \
    org.label-schema.vcs-url="https://github.com/k8s-for-greeks/docker-cassandra-k8s"

ENV \
    CASSANDRA_CONF=/etc/cassandra \
    CASSANDRA_DATA=/var/lib/cassandra \
    CASSANDRA_LOGS=/var/log/cassandra \
    CASSANDRA_RELEASE=3.11.4 \
    CASSANDRA_PATH=/usr/local/apache-cassandra \
    CASSANDRA_SHA=5d598e23c3ffc4db0301ec2b313061e3208fae0f9763d4b47888237dd9069987 \
    DI_VERSION=1.2.0 \
    DI_SHA=81231da1cd074fdc81af62789fead8641ef3f24b6b07366a1c34e5b059faf363 \
    PROMETHEUS_VERSION=0.3.1 \
    LOGENCODER_VERSION=4.10-SNAPSHOT \
    LOGENCODER_SHA=89be27bea7adc05b68c052a27b08c594a9f8e354185acbfd7a7b5f04c7cd9e20

RUN \
    set -ex \
    && export CASSANDRA_VERSION=${CASSANDRA_VERSION:-$CASSANDRA_RELEASE} \
    && export CASSANDRA_HOME=/usr/local/apache-cassandra-${CASSANDRA_VERSION} \
    && apt-get update && apt-get -qq -y install --no-install-recommends \
        libc6 \
        libjemalloc2 \
        localepurge \
        wget \
        jq \
    && wget -q -O - "https://repo1.maven.org/maven2/io/prometheus/jmx/jmx_prometheus_javaagent/0.13.0/jmx_prometheus_javaagent-0.13.0.jar" > /usr/local/share/prometheus-agent.jar \
    && wget -q -O - "https://archive.apache.org/dist/cassandra/${CASSANDRA_VERSION}/apache-cassandra-${CASSANDRA_VERSION}-bin.tar.gz" > /usr/local/apache-cassandra-bin.tar.gz \
    && echo "$CASSANDRA_SHA /usr/local/apache-cassandra-bin.tar.gz" | sha256sum -c - \
    && tar -xzf /usr/local/apache-cassandra-bin.tar.gz -C /usr/local \
    && rm /usr/local/apache-cassandra-bin.tar.gz \
    && ln -s $CASSANDRA_HOME $CASSANDRA_PATH \
    && wget -q -O - "https://github.com/mstump/logstash-logback-encoder/releases/download/${LOGENCODER_VERSION}/logstash-logback-encoder-${LOGENCODER_VERSION}.jar" > /usr/local/apache-cassandra/lib/log-encoder.jar \
    && echo "$LOGENCODER_SHA /usr/local/apache-cassandra/lib/log-encoder.jar" | sha256sum -c - \
    && wget -q -O - https://github.com/Yelp/dumb-init/releases/download/v${DI_VERSION}/dumb-init_${DI_VERSION}_amd64 > /sbin/dumb-init \
    && echo "$DI_SHA  /sbin/dumb-init" | sha256sum -c - \
    && if [ -n "$DEV_CONTAINER" ]; then apt-get -y --no-install-recommends install python; else rm -rf  $CASSANDRA_HOME/pylib; fi \
    && apt-get -y purge wget jq localepurge \
    && apt-get -y autoremove \
    && apt-get clean \
    && rm -rf \
        $CASSANDRA_HOME/*.txt \
        $CASSANDRA_HOME/doc \
        $CASSANDRA_HOME/javadoc \
        $CASSANDRA_HOME/tools/*.yaml \
        $CASSANDRA_HOME/tools/bin/*.bat \
        $CASSANDRA_HOME/bin/*.bat \
        doc \
        man \
        info \
        locale \
        common-licenses \
        ~/.bashrc \
        /var/lib/apt/lists/* \
        /var/log/**/* \
        /var/cache/debconf/* \
        /etc/systemd \
        /lib/lsb \
        /lib/udev \
        /usr/share/doc/ \
        /usr/share/doc-base/ \
        /usr/share/man/ \
        /tmp/*

COPY files /

RUN \
    adduser -u 1099 --disabled-password --gecos '' --disabled-login cassandra \
    && mkdir -p /var/lib/cassandra/ /var/log/cassandra/ /etc/cassandra/triggers \
    && chmod +x /sbin/dumb-init /ready-probe.sh \
    && mv /backup.sh /logback-stdout.xml /logback-json-files.xml /logback-json-stdout.xml /logback-files.xml /cassandra.yaml /jvm.options /prometheus.yaml /etc/cassandra/ \
    && mv /usr/local/apache-cassandra/conf/cassandra-env.sh /etc/cassandra/ \
    # For the backup jar you can build it with maven from here:
    # https://github.com/puneetloya/cassandra-backup/tree/feature/jenkins-support
    && mv /cassandra-backup /usr/bin/ \
    && chown cassandra: /ready-probe.sh \
    && cat /cassandra.rc >> /home/cassandra/.bashrc \
    && echo 'export ENV=$HOME/.bashrc' >> "$HOME/.profile" \
    && chown -c -R cassandra:cassandra "${CASSANDRA_DATA}" "${CASSANDRA_CONF}" "${CASSANDRA_LOGS}" "/usr/local/apache-cassandra-${CASSANDRA_RELEASE}"

VOLUME ["/var/lib/cassandra"]

# 1234: prometheus jmx_exporter
# 7000: intra-node communication
# 7001: TLS intra-node communication
# 7199: JMX
# 9042: CQL
# 9160: thrift service
# 8778: jolokia port
EXPOSE 1234 7000 7001 7199 9042 9160 8778

CMD ["/sbin/dumb-init", "/bin/bash", "/run.sh"]
