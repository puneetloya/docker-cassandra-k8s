#!/bin/bash -eu

initialize() {
  set -x
  export GIT_COMMIT=${GIT_COMMIT:-$(git rev-parse --short HEAD)}
  export GIT_BRANCH=${GIT_BRANCH:-$(git symbolic-ref -q HEAD)}
  export ASCP_VERSION=${ASCP_VERSION:-"3.9.1.168302"}
  export AS_DEV_CORE_PATH=${AS_DEV_CORE_PATH:-/aspera/process/test/entsrv/3.9/archive/asp-dev-core-${ASCP_VERSION}-linux-64.tgz}
  export LICENSE_PATH=${LICENSE_PATH:-$(curl -s https://license.aspera.us/evals | grep Download\ a | grep -o '/evals/.*zip')}
  export UPDATE_ASCP=${UPDATE_ASCP:-false}
  export UPDATE_LICENSE=${UPDATE_LICENSE:-false}
  set +x
}

update_ascp() {
  if ${UPDATE_ASCP}; then
    tar xzvf ${AS_DEV_CORE_PATH} --strip-components=5 asp-dev-core/fasp/BUILD/linux-64-release/bin/ascp
  fi
}
update_license() {
  if ${UPDATE_LICENSE}; then
    # get license
    wget https://license.aspera.us/${LICENSE_PATH} -O ./licenses.zip
    # this is kludgy. only expect to see 10 numbers, so rely on ????3 and ????4 always being present
    unzip -n ./licenses.zip "*7-TransferServer-unlim*"
    mv *7-TransferServer* aspera-license
    rm ./licenses.zip
  fi
}

# build() {
#   docker-build \
#     -s $(pwd) \
#     -n mysql-backup \
#     -t ${GIT_COMMIT},${GIT_BRANCH/refs\/heads\//}-latest,${GIT_BRANCH/refs\/heads\//}-${GIT_COMMIT} \
#     -reg ahab.asperasoft.com/aspera,gitlab-registry.aspera.us/devops/mysql-docker-backup \
#     -p -y
# }

run() {
  initialize
  update_ascp
  #update_license
  #build
}

run "$@"
