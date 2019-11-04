#!/bin/bash

# This script allows you to add custom repositories in multiples hosts
# Tested in Satellite 6.4.0 and 6.5.2.1
# Required: Hammer and GNU Parallel

# Repository to enable
REPO="${1}"

# Search string for hosts
SEARCH="${2}"

# Number of parallel execution. Too high a number will cause Satellite performance issues.
PARALLEL="10"

DEBUG=1
TEMPFILE="/tmp/hammer_host_list"


enablerepolog() {
    LEVEL="${1}"
    DEBUG="${2}"
    MSG="${3}"
    if [ "${DEBUG}" == "0" ] && [ "${LEVEL}" == 3 ]; then
        return
    fi
    DATE="$(date "+%Y-%d-%m %H:%M:%S")"
    PREFIX="*"
    [ "${LEVEL}" == 2 ] && PREFIX="   -"
    [ "${LEVEL}" == 3 ] && PREFIX="      >"
    echo -e "[${DATE}] ${PREFIX} ${MSG}"
}
export -f enablerepolog

enablerepo() {
    REPO="${1}"
    DEBUG=${2}
    HOST="${3}"
    HOST_ID="$(echo "${HOST}" | cut -d'#' -f 1)"
    HOST_NAME="$(echo "${HOST}" | cut -d'#' -f 2)"
    CHECK="$(hammer --output=csv --no-headers host subscription product-content --host-id="${HOST_ID}" | grep "${REPO}")"
    if [ "${CHECK}" != "" ]; then
        CHECK_ENABLED="$(echo "${CHECK}" | grep "enabled:1" | wc -l)"
        if [ "${CHECK_ENABLED}" == "0" ]; then
            RESP="$(hammer host subscription content-override --content-label="${REPO}" --host-id="${HOST_ID}" --override-name="enabled" --value="true")"
            if [ "$?" == "0" ]; then
                enablerepolog 2 "${DEBUG}" "\e[32mSuccessfully\e[39m enabled ${REPO} for host ${HOST_NAME}"
            else
                enablerepolog 2 "${DEBUG}" "\e[31mFAILED\e[39m to enable ${REPO} repository for host ${HOST_NAME}"
            fi
            enablerepolog 3 "${DEBUG}" "HAMMER RESPONSE: ${RESP}"
            enablerepolog 3 "${DEBUG}" "CHECK REPO: ${CHECK}"
        else
            enablerepolog 2 "${DEBUG}" "\e[33mSkipped:\e[39m repository ${REPO} already enabled for host ${HOST_NAME}"
            enablerepolog 3 "${DEBUG}" "CHECK REPO: ${CHECK}"
        fi
    else
        enablerepolog 2 "${DEBUG}" "\e[33mSkipped:\e[39m repository ${REPO} not available for host ${HOST_NAME}."
    fi
}
export -f enablerepo


if ! $(which hammer 2>/dev/null >/dev/null); then
    enablerepolog 1 "${DEBUG}" "\e[31mERRO!\e[39m Hammer not installed."
    exit 8
fi

if ! $(which parallel 2>/dev/null >/dev/null); then
    enablerepolog 1 "${DEBUG}" "\e[31mERRO!\e[39m Parallel not installed. Install parallel available on EPEL repository."
    exit 9
fi

if [ "$#" -ne 2 ]; then
    echo "Usage: ${0} 'repo_full_name' 'search_string'"
    exit 2
fi

REPOEXIST="$(hammer --output=csv --no-headers repository list --search="content_label = ${REPO}" | wc -l)"
if [ "${REPOEXIST}" != "1" ]; then
    enablerepolog 1 "${DEBUG}" "\e[31mERRO!\e[39m Repository not found."
    exit 3
fi

enablerepolog 1 "${DEBUG}" "Listing hosts..."
enablerepolog 2 "${DEBUG}" "Search string: ${SEARCH}"
hammer --output=csv --no-headers host list --search="${SEARCH}" | grep -v ^$ | awk -F',' '{print $1"#"$2}' > ${TEMPFILE}
if [ "$?" != "0" ]; then
    enablerepolog 2 "${DEBUG}" "\e[31mFAILED\e[39m to list hosts!"
    exit 1
fi

enablerepolog 1 "${DEBUG}" "Listing capsules..."
for CAPSULE in $(hammer --output=csv --no-headers capsule list | awk -F',' '{print $2}'); do
    enablerepolog 2 "${DEBUG}" "Removing capsule ${CAPSULE} from list"
    sed -i "/^[0-9]\+#${CAPSULE}\$/d" ${TEMPFILE}
done

enablerepolog 1 "${DEBUG}" "Found $(wc -l ${TEMPFILE} | awk '{print $1}') hosts"

enablerepolog 1 "${DEBUG}" "Enabling repo ${REPO}..."
parallel --will-cite -j ${PARALLEL} enablerepo "${REPO}" "${DEBUG}" < ${TEMPFILE}
