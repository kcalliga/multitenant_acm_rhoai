#!/usr/bin/env bash
# setup/patch-data-connections.sh
#
# Run after OBCs are Bound.  Reads credentials from the NooBaa-generated
# Secret and ConfigMap, then creates a properly labelled RHOAI DataConnection
# Secret in each tenant namespace.
#
# Usage:
#   chmod +x setup/patch-data-connections.sh
#   ./setup/patch-data-connections.sh

set -euo pipefail

NOOBAA_ENDPOINT="https://s3.openshift-storage.svc:443"
REGION="us-east-1"   # NooBaa accepts any region string

for TENANT in usera userb; do
  OBC_NAME="granite-models-${TENANT}"
  DC_NAME="aws-connection-granite-${TENANT}"

  echo ">>> Waiting for OBC ${OBC_NAME} in namespace ${TENANT} to be Bound..."
  for i in $(seq 1 30); do
    PHASE=$(oc get obc "${OBC_NAME}" -n "${TENANT}" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    if [[ "${PHASE}" == "Bound" ]]; then
      echo "    OBC is Bound."
      break
    fi
    echo "    Attempt ${i}/30 - phase: ${PHASE:-pending}. Waiting 10s..."
    sleep 10
    if [[ $i -eq 30 ]]; then
      echo "ERROR: OBC ${OBC_NAME} did not become Bound in time."
      exit 1
    fi
  done

  # Pull credentials from NooBaa-generated secret and configmap
  ACCESS_KEY=$(oc get secret "${OBC_NAME}" -n "${TENANT}" \
    -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d)
  SECRET_KEY=$(oc get secret "${OBC_NAME}" -n "${TENANT}" \
    -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d)
  BUCKET_NAME=$(oc get configmap "${OBC_NAME}" -n "${TENANT}" \
    -o jsonpath='{.data.BUCKET_NAME}')

  echo "    Bucket: ${BUCKET_NAME}"
  echo "    Creating DataConnection secret: ${DC_NAME}"

  oc create secret generic "${DC_NAME}" \
    --namespace="${TENANT}" \
    --from-literal=AWS_ACCESS_KEY_ID="${ACCESS_KEY}" \
    --from-literal=AWS_SECRET_ACCESS_KEY="${SECRET_KEY}" \
    --from-literal=AWS_DEFAULT_REGION="${REGION}" \
    --from-literal=AWS_S3_BUCKET="${BUCKET_NAME}" \
    --from-literal=AWS_S3_ENDPOINT="${NOOBAA_ENDPOINT}" \
    --dry-run=client -o yaml | \
  oc label --local -f - \
    opendatahub.io/managed=true \
    opendatahub.io/dashboard=true \
    -o yaml | \
  oc annotate --local -f - \
    opendatahub.io/connection-type=s3 \
    "openshift.io/display-name=granite-${TENANT}" \
    -o yaml | \
  oc apply -f -

  echo "    DataConnection ${DC_NAME} created in namespace ${TENANT}."
done

echo ""
echo "Done. Both DataConnections are ready."
echo "You can verify in the RHOAI dashboard under each project -> Data connections."
