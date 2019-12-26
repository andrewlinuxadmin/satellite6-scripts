#!/bin/bash


# Usage:
#   ./satellite_create_org.sh 'organization_name' 'location_name' '/path/to/manifest/file'


ORG="${1}"
LOCATION="${2}"
MANIFEST="${3}"

if [ "$#" -ne 3 ]; then
    echo "Usage: ${0} 'organization_name' 'location_name' '/path/to/manifest/file'"
    exit 1
fi

if [ ! -r ${MANIFEST} ]; then
	echo "Invalid manifest file"
	exit 2
fi

if ! $(which hammer 2>/dev/null >/dev/null); then
    echo "Hammer not installed!"
    exit 8
fi


# Create Organization
ORG_EXIST="$(hammer --output=csv --no-headers organization list --search="label = teste1" 2>/dev/null | grep -v ^$ | wc -l)"
if [ "${ORG_EXIST}" == "0" ]; then
	hammer organization create --name="${ORG}" --label="${ORG}" --location="${LOCATION}" --environment-ids=1
	if [ "$?" != "0" ]; then
		echo "[$(date)] Create organization failed!"
		exit 3
	fi
else
	echo "Organization ${ORG} already exists."
fi

# Upload manifest file generated in https://access.redhat.com/management/subscription_allocations
MANIFEST_EXIST="$(hammer --output=csv --no-headers subscription list --organization="${ORG}" | grep -v ^$ | wc -l)"
if [ "${MANIFEST_EXIST}" == "0" ]; then
	hammer subscription upload --organization="${ORG}" --file="${MANIFEST}"
	if [ "$?" != "0" ]; then
		echo "[$(date)] Upload manifest failed!"
		exit 4
	fi
else
	echo "Subscription exists!"
fi

# Enable repositories for RHEL 8
hammer repository-set enable --organization="${ORG}" --product="Red Hat Enterprise Linux for x86_64" --name="Red Hat Enterprise Linux 8 for x86_64 - BaseOS (RPMs)" --releasever="8" --basearch="x86_64"
hammer repository-set enable --organization="${ORG}" --product="Red Hat Enterprise Linux for x86_64" --name="Red Hat Enterprise Linux 8 for x86_64 - AppStream (RPMs)" --releasever="8" --basearch="x86_64"

# Enable repositories for RHEL 7
hammer repository-set enable --organization="${ORG}" --product="Red Hat Enterprise Linux Server" --name="Red Hat Enterprise Linux 7 Server (RPMs)" --releasever="7Server" --basearch="x86_64"
hammer repository-set enable --organization="${ORG}" --product="Red Hat Enterprise Linux Server" --name="Red Hat Enterprise Linux 7 Server - Optional (RPMs)" --releasever="7Server" --basearch="x86_64"
hammer repository-set enable --organization="${ORG}" --product="Red Hat Enterprise Linux Server" --name="Red Hat Enterprise Linux 7 Server - Extras (RPMs)" --releasever="7Server" --basearch="x86_64"
hammer repository-set enable --organization="${ORG}" --product="Red Hat Software Collections for RHEL Server" --name="Red Hat Software Collections RPMs for Red Hat Enterprise Linux 7 Server" --releasever="7Server" --basearch="x86_64"
hammer repository-set enable --organization="${ORG}" --product="Red Hat Ansible Engine" --name="Red Hat Ansible Engine 2.8 RPMs for Red Hat Enterprise Linux 7 Server" --basearch="x86_64"

# Sincronize repositories
for REPOID in $(hammer --output=csv --no-headers repository list --organization="${ORG}" | awk -F',' '{print $1}'); do
	echo "Sync repository ${REPOID}..."
	hammer repository synchronize --organization="${ORG}" --id="${REPOID}";
done

# Create sync plan
hammer sync-plan create --organization="${ORG}" --name="sync_${ORG}" --interval="daily" --sync-date="$(date +%Y-%m-%d)" --enabled=1
for PRODUCT in $(hammer --output=csv --no-headers product list --organization="${ORG}" --enabled=1 | awk -F',' '{print $1}'); do
	echo "Add product ${PRODUCT} in sync plan sync_${ORG}..."
	hammer product set-sync-plan --organization="${ORG}" --sync-plan="sync_${ORG}" --id="${PRODUCT}"
done