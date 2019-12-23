#!/bin/bash


ORG="${1}"
LOCATION="${2}"
MANIFEST="${3}"


hammer organization create --name="${ORG}" --label="${ORG}" --location="${LOCATION}" --environment-ids=1

hammer subscription upload --organization="${ORG}" --file="${MANIFEST}"

hammer repository-set enable --organization="${ORG}" --product="Red Hat Enterprise Linux for x86_64" --name="Red Hat Enterprise Linux 8 for x86_64 - BaseOS (RPMs)" --releasever="8" --basearch="x86_64"
hammer repository-set enable --organization="${ORG}" --product="Red Hat Enterprise Linux for x86_64" --name="Red Hat Enterprise Linux 8 for x86_64 - AppStream (RPMs)" --releasever="8" --basearch="x86_64"

hammer repository-set enable --organization="${ORG}" --product="Red Hat Enterprise Linux Server" --name="Red Hat Enterprise Linux 7 Server (RPMs)" --releasever="7Server" --basearch="x86_64"
hammer repository-set enable --organization="${ORG}" --product="Red Hat Enterprise Linux Server" --name="Red Hat Enterprise Linux 7 Server - Optional (RPMs)" --releasever="7Server" --basearch="x86_64"
hammer repository-set enable --organization="${ORG}" --product="Red Hat Enterprise Linux Server" --name="Red Hat Enterprise Linux 7 Server - Extras (RPMs)" --releasever="7Server" --basearch="x86_64"

hammer repository-set enable --organization="${ORG}" --product="Red Hat Software Collections for RHEL Server" --name="Red Hat Software Collections RPMs for Red Hat Enterprise Linux 7 Server" --releasever="7Server" --basearch="x86_64"

hammer repository-set enable --organization="${ORG}" --product="Red Hat Ansible Engine" --name="Red Hat Ansible Engine 2.8 RPMs for Red Hat Enterprise Linux 7 Server" --basearch="x86_64"



for REPOID in $(hammer --output=csv --no-headers repository list --organization="${ORG}" | awk -F',' '{print $1}'); do
	echo "Sync repository ${REPOID}..."
	hammer repository synchronize --organization="${ORG}" --id="${REPOID}";
done

hammer sync-plan create --organization="${ORG}" --name="sync_${ORG}" --interval="daily" --sync-date="$(date +%Y-%m-%d)" --enabled=1

for PRODUCT in $(hammer --output=csv --no-headers product list --organization="${ORG}" --enabled=1 | awk -F',' '{print $1}'); do
	echo "Add product ${PRODUCT} in sync plan sync_${ORG}..."
	hammer product set-sync-plan --organization="${ORG}" --sync-plan="sync_${ORG}" --id="${PRODUCT}"
done