This document is the complete technical runbook for configuring NVIDIA GPU observability and multi-tenant isolation on OpenShift 4.14+.

---

## 1. Global Infrastructure Setup (Admin Only)

### Step 1: Enable User Workload Monitoring
By default, OpenShift monitoring only covers platform components. You must enable it to scrape metrics from user namespaces.

```bash
# Create/Update the cluster-monitoring-config
cat <<EOF | oc apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-monitoring-config
  namespace: openshift-monitoring
data:
  config.yaml: |
    enableUserWorkload: true
    
### Step 2: Patch the GPU ClusterPolicy
The GPU Operator must be configured to use honorLabels so that the namespace metadata from the GPU processes is preserved in the monitoring database.

# Update the ClusterPolicy via CLI to ensure persistence
```bash
oc patch clusterpolicy gpu-cluster-policy --type merge -p '
{
  "spec": {
    "dcgmExporter": {
      "serviceMonitor": {
        "enabled": true,
        "honorLabels": true
      },
      "env": [
        {
          "name": "DCGM_EXPORTER_COLLECTORS",
          "value": "/etc/dcgm-exporter/dcp-metrics-included.csv"
        }
      ]
    }
  }
}'

### Step 3: Label the ServiceMonitor
Tag the nvidia-dcgm-exporter ServiceMonitor so the User Workload Prometheus stack starts collecting metrics.

```bash
oc label servicemonitor nvidia-dcgm-exporter -n nvidia-gpu-operator openshift.io/user-monitoring=true --overwrite

## 2. User & Project Provisioning Automation
Run this script logic whenever a new user or namespace requires GPU visibility. This ensures User 1 cannot see User 2's GPU metrics and vice-versa.

```bash

# Define target namespace and user
TARGET_NS="user1"
TARGET_USER="user1"

# 1. Opt-in the namespace to the monitoring stack
oc label namespace $TARGET_NS openshift.io/cluster-monitoring=true --overwrite

# 2. Assign required RBAC roles for the Metrics Dashboard
oc adm policy add-role-to-user monitoring-edit $TARGET_USER -n $TARGET_NS
oc adm policy add-role-to-user view $TARGET_USER -n $TARGET_NS

## 3. High-Load Validation (Testing)
Standard tests exit too fast for the 30-second Prometheus scrape interval. Use this "Stressing" Pod to verify VRAM and Compute spikes on the dashboard.

```bash
apiVersion: v1
kind: Pod
metadata:
  name: gpu-stress-test
  namespace: user1
spec:
  restartPolicy: Always
  containers:
  - name: cuda-nbody
    image: nvcr.io/nvidia/k8s/cuda-sample:nbody-cuda11.7.1-ubuntu18.04
    # -numbodies=2048000 and -fp64 (double precision) inflates the VRAM footprint
    args: ["-benchmark", "-numbodies=2048000", "-fp64"]
    resources:
      limits:
        [nvidia.com/gpu](https://nvidia.com/gpu): 1

## 4. Key Metrics ReferenceUse these PromQL queries in the OpenShift Console (Observe > Metrics) to verify data flow.
RequirementMetric NameDescriptionCompute LoadDCGM_FI_DEV_GPU_UTILCurrent GPU engine utilization (%)VRAM UsageDCGM_FI_DEV_FB_USEDFramebuffer memory currently allocated (MiB)Heat/HealthDCGM_FI_DEV_GPU_TEMPGPU Core Temperature (°C)Clock SpeedDCGM_FI_DEV_SM_CLOCKStreaming Multiprocessor frequency


Python
# Generating a single, complete Markdown file that includes all headers, descriptions, 
# and code blocks in a clean, copy-pasteable format.

final_complete_markdown = """# OpenShift GPU Multi-Tenancy Automation & Configuration Guide

This document is the complete technical runbook for configuring NVIDIA GPU observability and multi-tenant isolation on OpenShift 4.14+.

---

## 1. Global Infrastructure Setup (Admin Only)

### Step 1: Enable User Workload Monitoring
By default, OpenShift monitoring only covers platform components. You must enable it to scrape metrics from user namespaces.

```bash
# Create/Update the cluster-monitoring-config
cat <<EOF | oc apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-monitoring-config
  namespace: openshift-monitoring
data:
  config.yaml: |
    enableUserWorkload: true
EOF
Step 2: Patch the GPU ClusterPolicy
The GPU Operator must be configured to use honorLabels so that the namespace metadata from the GPU processes is preserved in the monitoring database.

Bash
# Update the ClusterPolicy via CLI to ensure persistence
oc patch clusterpolicy gpu-cluster-policy --type merge -p '
{
  "spec": {
    "dcgmExporter": {
      "serviceMonitor": {
        "enabled": true,
        "honorLabels": true
      },
      "env": [
        {
          "name": "DCGM_EXPORTER_COLLECTORS",
          "value": "/etc/dcgm-exporter/dcp-metrics-included.csv"
        }
      ]
    }
  }
}'
Step 3: Label the ServiceMonitor
Tag the nvidia-dcgm-exporter ServiceMonitor so the User Workload Prometheus stack starts collecting metrics.

Bash
oc label servicemonitor nvidia-dcgm-exporter -n nvidia-gpu-operator openshift.io/user-monitoring=true --overwrite
2. User & Project Provisioning Automation
Run this script logic whenever a new user or namespace requires GPU visibility. This ensures User 1 cannot see User 2's GPU metrics and vice-versa.

Bash
# Define target namespace and user
TARGET_NS="user1"
TARGET_USER="user1"

# 1. Opt-in the namespace to the monitoring stack
oc label namespace $TARGET_NS openshift.io/cluster-monitoring=true --overwrite

# 2. Assign required RBAC roles for the Metrics Dashboard
oc adm policy add-role-to-user monitoring-edit $TARGET_USER -n $TARGET_NS
oc adm policy add-role-to-user view $TARGET_USER -n $TARGET_NS
3. High-Load Validation (Testing)
Standard tests exit too fast for the 30-second Prometheus scrape interval. Use this "Stressing" Pod to verify VRAM and Compute spikes on the dashboard.

YAML
apiVersion: v1
kind: Pod
metadata:
  name: gpu-stress-test
  namespace: user1
spec:
  restartPolicy: Always
  containers:
  - name: cuda-nbody
    image: nvcr.io/nvidia/k8s/cuda-sample:nbody-cuda11.7.1-ubuntu18.04
    # -numbodies=2048000 and -fp64 (double precision) inflates the VRAM footprint
    args: ["-benchmark", "-numbodies=2048000", "-fp64"]
    resources:
      limits:
        [nvidia.com/gpu](https://nvidia.com/gpu): 1
4. Key Metrics Reference
Use these PromQL queries in the OpenShift Console (Observe > Metrics) to verify data flow.

Requirement	Metric Name	Description
Compute Load	DCGM_FI_DEV_GPU_UTIL	Current GPU engine utilization (%)
VRAM Usage	DCGM_FI_DEV_FB_USED	Framebuffer memory currently allocated (MiB)
Heat/Health	DCGM_FI_DEV_GPU_TEMP	GPU Core Temperature (°C)
Clock Speed	DCGM_FI_DEV_SM_CLOCK	Streaming Multiprocessor frequency (MHz)

5. Maintenance Checklist (Troubleshooting)
Verify Scrapes: Run oc rsh -n nvidia-gpu-operator <dcgm_pod> curl localhost:9400/metrics. If metrics show up here but not in the UI, check your ServiceMonitor labels.

Dashboard Isolation: If User 1 sees User 2's data, check that honorLabels: true is set in the ServiceMonitor.

Empty Dashboard: If the UI shows "No Datapoints Found" for an admin, restart the monitoring pods:
oc delete pod -l app.kubernetes.io/name=prometheus -n openshift-monitoring
"""
