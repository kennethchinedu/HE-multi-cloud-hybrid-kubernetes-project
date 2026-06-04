# HA-multi-cloud-k8s-project

A hands-on SRE project that deploys Google's [Online Boutique](https://github.com/GoogleCloudPlatform/microservices-demo) microservices application onto a self-managed Kubernetes cluster. The project covers the full platform engineering stack: cluster provisioning, GitOps, service mesh, policy enforcement, observability, and chaos engineering.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│                  Your Host                     │
│  kubectl  ──►  127.0.0.1:6443                        │
│  Browser  ──►  192.168.56.11:30080 (ArgoCD UI)       │
└────────────────────┬────────────────────────────────┘
                     │ VirtualBox host-only network
        ┌────────────┼────────────┐
        ▼            ▼            ▼
  control-plane   worker-1     worker-2
  192.168.56.10  192.168.56.11 192.168.56.12
  4GB / 4CPU      2GB / 2CPU    2GB / 2CPU
```

The cluster runs 3 VMs provisioned by Vagrant/VirtualBox. All application workloads are pinned to worker nodes via `nodeSelector: node: worker`.

---

## Stack

| Layer | Technology |
|---|---|
| VM Provisioning | Vagrant + VirtualBox (Ubuntu 22.04) |
| Container Runtime | containerd |
| Kubernetes | kubeadm v1.29 |
| CNI | Calico v3.27 |
| GitOps | ArgoCD |
| Service Mesh | Istio (base, istiod, CNI, ingress gateway) |
| Chaos Engineering | Chaos Mesh |
| Infrastructure-as-Code | Terragrunt + Terraform (Helm provider) |
| Application | Google Online Boutique (11 microservices) |

---

## Project Structure

```
.
├── bootstrap/                  # Cluster provisioning
│   ├── vagrantfile             # 1 control plane + 2 worker VMs
│   ├── bootstrap_control_local.sh   # Runs on control plane
│   └── bootstrap_worker_local.sh    # Runs on each worker
│
├── base/                       # Raw Kubernetes manifests
│   ├── deployment.yaml         # 11 microservice deployments
│   ├── service.yaml            # ClusterIP services
│   ├── hpa.yaml                # HPA (1–10 replicas, CPU 50% / mem 75%)
│   ├── secret.yaml             # Image pull secret
│   └── volume.yaml             # hostPath volumes
│
├── platform/                   # Helm charts for platform tools
│   ├── argocd/                 # ArgoCD wrapper chart
│   └── istio/                  # Istio scaffold chart
│
├── infra/                      # Terragrunt/Terraform
│   └── environments/
│       └── root.hcl            # Kubernetes + Helm provider config
│
├── gitops/                     # ArgoCD ApplicationSets & Applications
│   ├── apps/appsets/           # ApplicationSets (to be added)
│   ├── apps/applications/      # Applications (to be added)
│   └── project/                # ArgoCD Project definitions
│
├── policies/                   # OPA/Kyverno policies (to be added)
│   ├── security/
│   ├── networking/
│   ├── cost/
│   └── mutations/
│
├── boutique-app/               # Helm chart wrapping the boutique app
├── docs/                       # Architecture, runbooks, decisions
└── script/                     # Helper scripts
```

---

## Microservices

| Service | Port | Description |
|---|---|---|
| frontend | 8080 | Web UI |
| product-catalog | 3550 | Product listings |
| cart | 7070 | Shopping cart (backed by Redis) |
| email | 8080 | Order confirmation emails |
| checkout | 5050 | Order orchestration |
| recommendation | 8080 | Product recommendations |
| currency | 7000 | Currency conversion |
| ads | 9555 | Advertisement service |
| shipping | 50051 | Shipping cost calculation |
| payment | 5000 | Payment processing |
| redis-cart | 6379 | Cart session store |



---

## Getting Started

### 1. Provision the cluster

```bash
cd bootstrap
vagrant up
```

### 2. Bootstrap the control plane

SSH into the control plane and run:

```bash
sudo bash bootstrap_control_local.sh 192.168.56.10 192.168.0.0/16
```

Copy the `kubeadm join` command printed at the end.

### 3. Join the worker nodes

SSH into each worker and run:

```bash
sudo bash bootstrap_worker_local.sh 192.168.56.10 <token> sha256:<hash>
```

### 4. Verify the cluster

```bash
kubectl get nodes -o wide
```

All nodes should show `Ready` with roles `control` / `worker`.

### 5. Deploy the application

```bash
# Create the image pull secret first
kubectl apply -f base/secret.yaml

# Apply all manifests
kubectl apply -f base/
```

### 6. Install platform tools (ArgoCD)

```bash
cd platform/argocd
helm dependency update
helm upgrade --install argocd . \
  --namespace argocd \
  --create-namespace \
  --values values.yaml
```

Get the ArgoCD admin password:

```bash
kubectl get secret argocd-initial-admin-secret \
  -n argocd \
  -o jsonpath="{.data.password}" | base64 -d
```

Access the UI at `http://192.168.56.11:30080` (user: `admin`).

---

## Accessing the Cluster from Your Mac

The Vagrant `private_network` bridges your Mac directly to the VM subnet.

| What | How |
|---|---|
| `kubectl` | Forward port 6443 — already in Vagrantfile. Set `--server=https://127.0.0.1:6443` in kubeconfig |
| ArgoCD UI | `http://192.168.56.11:30080` |
| Any NodePort service | `http://192.168.56.1x:<nodeport>` |
| Worker HTTP (port 80) | `http://localhost:8080` (worker-1) / `8081` (worker-2) |

---

## Roadmap 

- [ ] ArgoCD ApplicationSets for GitOps app delivery
- [ ] Kyverno policies (security, networking, cost)
- [ ] Istio service mesh with mTLS
- [ ] RED/USE dashboards (Prometheus + Grafana)
- [ ] Error budgets and burn-rate alerts
- [ ] Chaos Mesh experiments in CI/CD
- [ ] KEDA autoscaling on queue length
- [ ] Canary deployments and rollbacks
- [ ] Kubecost for resource rightsizing
- [ ] eBPF network policy and packet tracing
