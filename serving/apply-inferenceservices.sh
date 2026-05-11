#!/usr/bin/env bash
# serving/apply-inferenceservices.sh
#
# Reads the actual NooBaa bucket names from the DataConnection secrets
# (created by setup/patch-data-connections.sh) and applies the
# InferenceService manifests with the correct storageUri.
#
# Run AFTER:
#   1. setup/obc.yaml applied and OBCs are Bound
#   2. setup/patch-data-connections.sh completed
#   3. model-upload jobs completed
#   4. serving/servingruntime.yaml applied

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ">>> Reading bucket names from DataConnection secrets..."

BUCKET_USERA=$(oc get secret aws-connection-granite-usera -n usera \
  -o jsonpath='{.data.AWS_S3_BUCKET}' | base64 -d)

BUCKET_USERB=$(oc get secret aws-connection-granite-userb -n userb \
  -o jsonpath='{.data.AWS_S3_BUCKET}' | base64 -d)

echo "    usera bucket: ${BUCKET_USERA}"
echo "    userb bucket: ${BUCKET_USERB}"

echo ">>> Applying InferenceServices..."

sed \
  -e "s|BUCKET_NAME_USERA|${BUCKET_USERA}|g" \
  -e "s|BUCKET_NAME_USERB|${BUCKET_USERB}|g" \
  "${SCRIPT_DIR}/inferenceservice.yaml" | oc apply -f -

echo ""
echo "Done. Monitor rollout with:"
echo "  oc get inferenceservice -n usera"
echo "  oc get inferenceservice -n userb"
echo ""
echo "Watch the storage-initializer pull the model from NooBaa:"
echo "  oc logs -f -n usera \$(oc get pod -n usera -l serving.kserve.io/inferenceservice=granite-usera -o jsonpath='{.items[0].metadata.name}') -c storage-initializer"
