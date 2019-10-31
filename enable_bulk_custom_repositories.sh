#!/bin/bash

# Satellite access information
SERVER="https://satellite.example.com"
USER="user"
PASS="pass"

# Repository to enable
REPO="custom_repo"

# Search string for hosts
SEARCH=""

if [ "${SEARCH}" != "" ]; then
    HOSTSEARCH="--search='${SEARCH}'"
fi


echo "Listing hosts..."
hammer host list ${HOSTSEARCH} | grep ^[0-9] | awk '{print $1"#"$3}' > /tmp/hammer_host_list
if [ "$?" != "0" ]; then
	echo "Failed to list hosts"
	exit 1
fi
echo

for HOST in $(cat /tmp/hammer_host_list); do
    HOST_ID="$(echo "${HOST}" | cut -d'#' -f 1)"
    HOST_NAME="$(echo "${HOST}" | cut -d'#' -f 2)"
    JSON_DATA="{'content_overrides':[{'content_label':'${REPO}','name':'enabled','value':true}]}" "${SERVER}/api/v2/hosts/${HOST_ID}/subscriptions/content_override"
    curl --header "Accept:application/json,version=2" --header "Content-Type:application/json" --request PUT --user "${USER}:${PASS}" --insecure --data "${JSON_DATA}" 2>&1 >/dev/null
    if [ "$?" == "0" ]; then
    	echo "Successfully enabled ${REPO} for host ${HOST_NAME}"
    else
    	echo "Failed to enable ${REPO} repository for host ${HOST_NAME}"
	exit 2
    fi
done
