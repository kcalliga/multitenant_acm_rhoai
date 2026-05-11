#!/usr/bin/env bash
# observability/create-sa-tokens.sh
#
# Creates a long-lived ServiceAccount token for each Grafana SA
# and patches it into the GrafanaDataSource as an environment variable
# that the Grafana Operator injects into the Grafana pod.
#
# Run AFTER grafana-instances.yaml has been applied and pods are Running.

set -euo pipefail

for TENANT in usera userb; do
  SA="grafana-sa-${TENANT}"
  SECRET_NAME="grafana-sa-${TENANT}-token"
  NS="${TENANT}"

  echo ">>> Creating SA token secret for ${SA} in namespace ${NS}..."

  # Create a long-lived token secret bound to the SA
  oc apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${SECRET_NAME}
  namespace: ${NS}
  annotations:
    kubernetes.io/service-account.name: "${SA}"
type: kubernetes.io/service-account-token
EOF

  echo "    Waiting for token to be populated..."
  for i in $(seq 1 15); do
    TOKEN=$(oc get secret "${SECRET_NAME}" -n "${NS}" \
      -o jsonpath='{.data.token}' 2>/dev/null | base64 -d || true)
    if [[ -n "${TOKEN}" ]]; then
      echo "    Token ready."
      break
    fi
    sleep 5
    if [[ $i -eq 15 ]]; then
      echo "ERROR: token not populated for ${SECRET_NAME}"
      exit 1
    fi
  done

  # Patch the token into the Grafana deployment as an env var
  # so GrafanaDataSource's ${GRAFANA_SA_TOKEN} interpolation works
  oc set env deployment/grafana-usera-deployment \
    GRAFANA_SA_TOKEN="$(oc get secret "${SECRET_NAME}" -n "${NS}" \
      -o jsonpath='{.data.token}' | base64 -d)" \
    -n "${NS}" 2>/dev/null || \
  oc set env deployment/grafana-${TENANT}-deployment \
    GRAFANA_SA_TOKEN="$(oc get secret "${SECRET_NAME}" -n "${NS}" \
      -o jsonpath='{.data.token}' | base64 -d)" \
    -n "${NS}"

  echo "    Token injected into grafana-${TENANT} deployment."
done

echo ""
echo "Done. Grafana datasources will reconnect within ~30 seconds."
echo "Verify in each Grafana UI: Configuration -> Data Sources -> Prometheus -> Test"
