#!/bin/bash


# Usage:
#   ./satellite_create_org.sh 'organization_name' 'location_name' '/path/to/manifest/file.zip'


ORG="${1}"
LOCATION="${2}"
MANIFEST="${3}"

# Repositories:
# product,name,releasever,basearch
REPOSITORIES="
Red Hat Enterprise Linux for x86_64,Red Hat Enterprise Linux 8 for x86_64 - BaseOS (RPMs),8,x86_64
Red Hat Enterprise Linux for x86_64,Red Hat Enterprise Linux 8 for x86_64 - AppStream (RPMs),8,x86_64
Red Hat Enterprise Linux Server,Red Hat Enterprise Linux 7 Server (RPMs),7Server,x86_64
Red Hat Enterprise Linux Server,Red Hat Enterprise Linux 7 Server - Optional (RPMs),7Server,x86_64
Red Hat Enterprise Linux Server,Red Hat Enterprise Linux 7 Server - Extras (RPMs),7Server,x86_64
Red Hat Software Collections for RHEL Server,Red Hat Software Collections RPMs for Red Hat Enterprise Linux 7 Server,7Server,x86_64
Red Hat Ansible Engine,Red Hat Ansible Engine 2.8 RPMs for Red Hat Enterprise Linux 7 Server,7Server,x86_64
"

SYNC_ASYNC=0
SYNC_PLAN_INTERVAL="daily"
DEBUG=1


log() {
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


if [ "$#" -ne 3 ]; then
    echo "Usage: ${0} 'organization_name' 'location_name' '/path/to/manifest/file.zip'"
    exit 1
fi

if [ ! -r ${MANIFEST} ]; then
	log 1 "${DEBUG}" "Invalid manifest file"
	exit 2
fi

if ! $(which hammer 2>/dev/null >/dev/null); then
    log 1 "${DEBUG}" "Hammer not installed!"
    exit 8
fi

SATELLITE_VERSION="$(rpm -qa satellite)"
log 1 "${DEBUG}" "Satellite version: ${SATELLITE_VERSION}"


# Check location exists
log 1 "${DEBUG}" "Check location ${LOCATION}..."
LOCATION_EXIST="$(hammer --output=csv --no-headers location list --search="name = \"${LOCATION}\"" | grep -v ^$ | wc -l)"
if [ "${LOCATION_EXIST}" == "0" ]; then
	log 2 "${DEBUG}" "ERROR: Location ${LOCATION} does not exists!"
	exit 9
fi

# Create Organization
log 1 "${DEBUG}" "Creating organization ${ORG}..."
ORG_EXIST="$(hammer --output=csv --no-headers organization list --search="label = ${ORG}" 2>/dev/null | grep -v ^$ | wc -l)"
if [ "${ORG_EXIST}" == "0" ]; then
	ORG_RESP="$(hammer organization create --name="${ORG}" --label="${ORG}" --location="${LOCATION}" --environment-ids=1)"
	if [ "$?" != "0" ]; then
		log 2 "${DEBUG}" "ERROR: Create organization failed!"
		exit 3
	fi
	log 2 "${DEBUG}" "Organization created!"
	log 3 "${DEBUG}" "Hammer RESP: ${ORG_RESP}"
else
	log 2 "${DEBUG}" "Organization ${ORG} already exists."
fi

# Upload manifest file generated in https://access.redhat.com/management/subscription_allocations
log 1 "${DEBUG}" "Uploading manifest for organization ${ORG}..."
MANIFEST_EXIST="$(hammer --output=csv --no-headers subscription list --organization="${ORG}" | grep -v ^$ | wc -l)"
if [ "${MANIFEST_EXIST}" == "0" ]; then
	hammer subscription upload --organization="${ORG}" --file="${MANIFEST}"
	if [ "$?" != "0" ]; then
		log 2 "${DEBUG}" "ERROR: Upload manifest failed!"
		exit 4
	fi
	log 2 "${DEBUG}" "Manifest uploaded!"
else
	log 2 "${DEBUG}" "Subscription exists!"
fi

BKPIFS=${IFS}
IFS=$(echo -en "\n\b")

# Enable repositories
log 1 "${DEBUG}" "Enable repositories for organization ${ORG}..."
for REPO in ${REPOSITORIES}; do
	REPO_PRODUCT="$(echo "${REPO}" | awk -F',' '{print $1}')"
	REPO_NAME="$(echo "${REPO}" | awk -F',' '{print $2}')"
	REPO_RELEASEVER="$(echo "${REPO}" | awk -F',' '{print $3}')"
	REPO_BASEARCH="$(echo "${REPO}" | awk -F',' '{print $4}')"
	REPO_EXIST="$(hammer --output=csv --no-headers repository-set list --organization="${ORG}" --enabled=1 --search="product_name = \"${REPO_PRODUCT}\" and name = \"${REPO_NAME}\"" | grep -v ^$ | wc -l)"
	if [ "${REPO_EXIST}" == "0" ]; then
		REPO_RESP="$(hammer repository-set enable --organization="${ORG}" --product="${REPO_PRODUCT}" --name="${REPO_NAME}" --releasever="${REPO_RELEASEVER}" --basearch="${REPO_BASEARCH}")"
		log 2 "${DEBUG}" "Enabled repository \"${REPO_NAME}\""
		log 3 "${DEBUG}" "Hammer RESP: ${REPO_RESP}"
	else
		log 2 "${DEBUG}" "Repository ${REPO_NAME} already exists."
	fi
done

# Sincronize repositories
log 1 "${DEBUG}" "Synchronize repositories for organization ${ORG}..."
for SYNC_REPO in $(hammer --output=csv --no-headers repository list --organization="${ORG}" | awk -F',' '{print $1","$2}'); do
	SYNC_REPO_ID="$(echo "${SYNC_REPO}" | awk -F',' '{print $1}')"
	SYNC_REPO_NAME="$(echo "${SYNC_REPO}" | awk -F',' '{print $2}')"
	log 2 "${DEBUG}" "Sync repository \"${SYNC_REPO_NAME}\"..."
	if [ "${SYNC_ASYNC}" == "0" ]; then
		hammer repository synchronize --organization="${ORG}" --id="${SYNC_REPO_ID}"
	else
		hammer repository synchronize --organization="${ORG}" --id="${SYNC_REPO_ID}" --async
	fi
done

# Create sync plan
log 1 "${DEBUG}" "Create sync plan for organization ${ORG}..."
SYNC_PLAN_RESP="$(hammer sync-plan create --organization="${ORG}" --name="sync_${ORG}" --interval="${SYNC_PLAN_INTERVAL}" --sync-date="$(date +%Y-%m-%d)" --enabled=1)"
log 2 "${DEBUG}" "Created sync plan sync_${ORG} with interval ${SYNC_INTERVAL}"
log 3 "${DEBUG}" "Hammer RESP: ${SYNC_PLAN_RESP}"
for PRODUCT in $(hammer --output=csv --no-headers product list --organization="${ORG}" --enabled=1 | awk -F',' '{print $1","$2}'); do
	PRODUCT_ID="$(echo "${PRODUCT}" | awk -F',' '{print $1}')"
	PRODUCT_NAME="$(echo "${PRODUCT}" | awk -F',' '{print $2}')"
	SYNC_PLAN_PRODUCT_RESP="$(hammer product set-sync-plan --organization="${ORG}" --sync-plan="sync_${ORG}" --id="${PRODUCT_ID}")"
	log 2 "${DEBUG}" "Added product \"${PRODUCT_NAME}\" in sync plan sync_${ORG}..."
	log 3 "${DEBUG}" "Hammer RESP: ${SYNC_PLAN_PRODUCT_RESP}"
done

IFS=${BKPIFS}

exit 0

