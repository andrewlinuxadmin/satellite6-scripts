#!/bin/bash

# This script allows you to add custom repositories in multiples hosts
# Tested in Satellite 6.4.0 and 6.5.2.1
# Required: Hammer and GNU Parallel

# Repository to enable
REPO="custom_repo"

# Search string for hosts
SEARCH="name ~ srv"

# Satellite URL
SERVER="https://localhost"

# Number of parallel execution. Too high a number will cause Satellite performance issues.
PARALLEL="10"

DEBUG=1
LOGFILE="/root/enable_bulk_custom_repositories"
TEMPFILE="/tmp/hammer_host_list"

enablerepolog() {
    if [ "${DEBUG}" == "0" ] && [ "${LEVEL}" == 3 ]; then
        return
    fi
    DATE="$(date "+%Y-%d-%m %H:%M:%S")"
    LEVEL="${1}"
    MSG="${2}"
    PREFIX="*"
    [ "${LEVEL}" == 2 ] && PREFIX="   -"
    [ "${LEVEL}" == 3 ] && PREFIX="      >"
    echo -e "[${DATE}] ${PREFIX} ${MSG}"
}
export -f enablerepolog

enablerepo() {
    REPO="${1}"
    HOST="${2}"
    HOST_ID="$(echo "${HOST}" | cut -d'#' -f 1)"
    HOST_NAME="$(echo "${HOST}" | cut -d'#' -f 2)"
    RESP=$(hammer host subscription content-override --content-label="${REPO}" --host-id="${HOST_ID}" --override-name="enabled" --value="true")
    if [ "$?" == "0" ]; then
        enablerepolog 2 "\e[32mSuccessfully\e[39m enabled ${REPO} for host ${HOST_NAME}"
    else
        enablerepolog 2 "\e[31mFAILED\e[39m to enable ${REPO} repository for host ${HOST_NAME}"
    fi
    enablerepolog 3 "HAMMER RESPONSE: ${RESP}"
}
export -f enablerepo


if ! $(which parallel 2>/dev/null >/dev/null); then
    enablerepolog 1 "\e[31mERRO!\e[39m Parallel not installed. Install parallel available on EPEL repository."
    exit 9
fi

enablerepolog 1 "Listing hosts..."
enablerepolog 2 "Search string: ${SEARCH}"
hammer --output=csv --no-headers host list --search="${SEARCH}" | grep -v ^$ | awk -F',' '{print $1"#"$2}' > ${TEMPFILE}
if [ "$?" != "0" ]; then
    enablerepolog 2 "\e[31mFAILED\e[39m to list hosts!"
    exit 1
fi
enablerepolog 1 "Found $(wc -l ${TEMPFILE} | awk '{print $1}') hosts"

enablerepolog 1 "Enabling repo ${REPO}..."
parallel --will-cite -j ${PARALLEL} enablerepo "${REPO}" < ${TEMPFILE}
