#!/bin/bash

# DESCRIPTION:  This script allows you to add virt-who subscriptions to Activation Keys
# TESTED:       Satellite 6.4.0 and 6.5.2.1
# REQUIRED:     Hammer
# AUTHOR:       Andrew Max <andrew@linuxadmin.eti.br>


# Search for Activation Keys who will receive Virt-Who subscriptions
AK_SEARCH="name ~ example1 or name ~ example2 or name ~ example3"

# Organization name
ORG="myorg"

# Temp files
TEMPDIR="/tmp"
TEMPFILE_LIST_AK="${TEMPDIR}/sat_list_ak"
TEMPFILE_LIST_VIRTWHO_SUBS="${TEMPDIR}/sat_list_virtwho_subs"
TEMPFILE_LIST_AK_SUBS="${TEMPDIR}/sat_list_subs_ak"
TEMPFILE_LIST_AK_SUBS_DIFF="${TEMPDIR}/sat_list_subs_diff_ak"

rm -f ${TEMPFILE_LIST_AK} ${TEMPFILE_LIST_VIRTWHO_SUBS} ${TEMPFILE_LIST_AK_SUBS}_* ${TEMPFILE_LIST_AK_SUBS_DIFF}_*

echo "[$(date)] Listing virt-who subscription..."
hammer --output csv subscription list --organization ${ORG} --search "type = STACK_DERIVED" | grep "^[0-9]" | grep ",Virtual," | cut -d',' -f1 | sort > ${TEMPFILE_LIST_VIRTWHO_SUBS}
if [ "$?" != "0" ]; then
	echo "[$(date)] List virt-who subscription failed!"
	exit 1
fi

echo "[$(date)] Listing activation keys..."
hammer --output csv activation-key list --organization ${ORG} --search "${AK_SEARCH}" | grep "^[0-9]" | cut -d',' -f2 | sort > ${TEMPFILE_LIST_AK}
if [ "$?" != "0" ]; then
	echo "[$(date)] List activation keys failed!"
	exit 2
fi

for AK in $(cat ${TEMPFILE_LIST_AK}); do
	echo "[$(date)] Listing subscriptons in activation key ${AK}..."
	hammer --output csv activation-key subscriptions --organization ${ORG} --activation-key ${AK} | grep "^[0-9]" | cut -d',' -f1 | sort > ${TEMPFILE_LIST_AK_SUBS}_${AK}
	if [ "$?" != "0" ]; then
		echo "[$(date)] List subscriptions in activation keys ${AK} failed!"
		exit 3
	fi

	LIST_AK_SUBS_COUNT="$(wc -l ${TEMPFILE_LIST_AK_SUBS}_${AK} | awk '{print $1}')"
	if [ "${LIST_AK_SUBS_COUNT}" == "0" ]; then
		echo "[$(date)] List subscriptions in activation keys ${AK} failed!"
		exit 4
	fi

	comm -23 ${TEMPFILE_LIST_VIRTWHO_SUBS} ${TEMPFILE_LIST_AK_SUBS}_${AK} > ${TEMPFILE_LIST_AK_SUBS_DIFF}_${AK}
	LIST_AK_SUBS_DIFF_COUNT="$(wc -l ${TEMPFILE_LIST_AK_SUBS_DIFF}_${AK} | awk '{print $1}')"
	if [ "${LIST_AK_SUBS_DIFF_COUNT}" != "0" ]; then
		echo "[$(date)]   * ${LIST_AK_SUBS_DIFF_COUNT} subscription to add to activation key ${AK}"
		for SUBID in $(cat ${TEMPFILE_LIST_AK_SUBS_DIFF}_${AK}); do
			echo "[$(date)]     - Adding subscription ID ${SUBID} to activation key ${AK}..."
			hammer activation-key add-subscription --organization ${ORG} --name ${AK} --subscription-id ${SUBID}
		done
	else
		echo "[$(date)]   * No subscriptions to add on activation key ${KEY}"
	fi
done

echo "[$(date)] End process"


