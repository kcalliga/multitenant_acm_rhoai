# OpenShift Multi-Tenant AI Demo

Two tenants (`usera` / `userb`) each serving Granite 7B Instruct via vLLM on KServe,
with per-tenant Grafana dashboards showing DCGM GPU metrics scoped to their workload.

Infrastructure is managed via **ACM PolicyGenerator + GitOps (ArgoCD)**.
Plain manifests live in `acm/policygenerator/manifests/`. The PolicyGenerator plugin
wraps them into ACM Policy objects at sync time. ACM propagates policies to any
managed cluster labelled `demo-ai-workloads=true`.

Dynamic steps that depend on runtime values (OBC credentials, bucket names,
SA tokens) are handled by helper scripts run once against the managed cluster.

---

## Repository Structure

```
acm/
  gitops/
    acm-gitops-perm-clusterrole.yaml   # ClusterRole for ArgoCD SA
    acm-gitops-perm-binding.yaml       # ClusterRoleBinding
    argocd-patch.yaml                  # Patch to install PolicyGenerator plugin
    applicationset.yaml                # ArgoCD ApplicationSet pointing at this repo
  policygenerator/
    policygenerator.yaml               # PolicyGenerator template (generates all policies)
    kustomization.yaml                 # Kustomize entry point
    manifests/
      gpu-operator/                    # NVIDIA GPU Operator + ClusterPolicy
      grafana-operator/                # Community Grafana Operator
      namespaces/                      # usera + userb namespaces + RHOAI projects
      gpu-quota/                       # ResourceQuota 1 GPU per namespace
      obc/                             # ObjectBucketClaims (NooBaa)
      servingruntimes/                 # vLLM ServingRuntime per namespace
      grafana-instances/               # Grafana CR + SA + RBAC per namespace
      grafana-datasource/              # GrafanaDataSource -> thanos-querier
      grafana-dashboard/               # DCGM dashboard JSON per namespace
setup/
  patch-data-connections.sh            # Reads OBC creds, creates RHOAI DataConnections
model-upload/
  upload-job.yaml                      # Job: pull Granite 7B from HF, push to NooBaa
serving/
  apply-inferenceservices.sh           # Reads bucket name, applies InferenceServices
observability/
  create-sa-tokens.sh                  # Creates SA tokens, injects into Grafana pods
```

---

## Prerequisites

- OpenShift 4.14+ with ACM hub
- GitOps operator (openshift-gitops) installed on hub
- RHOAI 2.x on managed cluster
- ODF + NooBaa (MultiCloud Object Gateway) on managed cluster
- `oc` CLI logged in as cluster-admin on hub

---

## Step 0 — Substitute Cluster Domain

```bash
DOMAIN=apps.mycluster.example.com
grep -rl 'CLUSTER_DOMAIN' . | xargs sed -i "s/CLUSTER_DOMAIN/${DOMAIN}/g"
```

Update `acm/gitops/applicationset.yaml` with your Git repo URL and branch:
```bash
sed -i "s|YOUR_GIT_REPO_URL|https://github.com/yourorg/your-repo.git|g" acm/gitops/applicationset.yaml
sed -i "s|YOUR_GIT_BRANCH|main|g" acm/gitops/applicationset.yaml
```

---

## Step 1 — Label the Managed Cluster

```bash
oc label managedcluster <your-cluster-name> demo-ai-workloads=true
```

---

## Step 2 — Set Up ArgoCD for PolicyGenerator (hub, once)

```bash
# Grant ArgoCD SA permission to manage ACM policy resources
oc apply -f acm/gitops/acm-gitops-perm-clusterrole.yaml
oc apply -f acm/gitops/acm-gitops-perm-binding.yaml

# Patch ArgoCD to install the PolicyGenerator Kustomize plugin binary
oc patch argocd openshift-gitops -n openshift-gitops \
  --type=merge --patch-file acm/gitops/argocd-patch.yaml
```

Wait for the ArgoCD repo-server pod to restart before continuing.

---

## Step 3 — Commit to Git and Create the ApplicationSet

Push this repo to your Git remote, then apply the ApplicationSet on the hub:

```bash
oc apply -f acm/gitops/applicationset.yaml
```

ArgoCD will:
1. Clone the repo
2. Run `kustomize build --enable-alpha-plugins` on `acm/policygenerator/`
3. PolicyGenerator expands `policygenerator.yaml` into 9 ACM Policy objects
4. ArgoCD syncs those policies to the hub (`policies` namespace)
5. ACM propagates each policy to your managed cluster

Monitor in the ACM Governance UI or:
```bash
oc get policy -n policies
```

---

## Step 4 — Create HF Token Secret (managed cluster)

```bash
oc create secret generic hf-token --from-literal=token=<YOUR_HF_TOKEN> -n usera
oc create secret generic hf-token --from-literal=token=<YOUR_HF_TOKEN> -n userb
```

---

## Step 5 — Patch DataConnections (managed cluster)

Run after OBCs are Bound (check with `oc get obc -n usera`):

```bash
chmod +x setup/patch-data-connections.sh
./setup/patch-data-connections.sh
```

---

## Step 6 — Upload Models (managed cluster)

```bash
oc apply -f model-upload/upload-job.yaml
oc logs -f job/upload-granite-model -n usera   # ~15-30 min
oc logs -f job/upload-granite-model -n userb
```

---

## Step 7 — Apply InferenceServices (managed cluster)

Run after both upload Jobs complete:

```bash
chmod +x serving/apply-inferenceservices.sh
./serving/apply-inferenceservices.sh
```

---

## Step 8 — Wire Grafana SA Tokens (managed cluster)

Run after Grafana pods are Running:

```bash
chmod +x observability/create-sa-tokens.sh
./observability/create-sa-tokens.sh
```

---

## Policy Summary

| Manifest directory   | Policy generated              | Dynamic script needed after? |
|----------------------|-------------------------------|------------------------------|
| gpu-operator         | policy-gpu-operator           | No                           |
| grafana-operator     | policy-grafana-operator       | No                           |
| namespaces           | policy-namespaces             | No                           |
| gpu-quota            | policy-gpu-quota              | No                           |
| obc                  | policy-obc                    | Yes — patch-data-connections |
| servingruntimes      | policy-servingruntimes        | Yes — apply-inferenceservices|
| grafana-instances    | policy-grafana-instances      | Yes — create-sa-tokens       |
| grafana-datasource   | policy-grafana-datasource     | No                           |
| grafana-dashboard    | policy-grafana-dashboard      | No                           |

---

## Demo Flow

1. Show ArgoCD app synced — all resources green
2. Show ACM Governance — 9 policies Compliant
3. Open RHOAI dashboard — usera and userb projects visible
4. Start usera InferenceService via RHOAI dashboard
5. Open usera Grafana — GPU utilization and memory rising
6. Stop usera InferenceService — GPU releases, metrics drop to zero
7. Start userb InferenceService via RHOAI dashboard
8. Open userb Grafana — GPU metrics appear for userb pod only
9. Switch back to usera Grafana — shows only usera's window, nothing from userb
