# Kubernetes Cluster Bootstrap — What We Did and Why

This document walks through the process of bootstrapping a self-managed Kubernetes cluster using `kubeadm`, troubleshooting a CNI (Container Network Interface) failure, and correctly configuring node IPs in a VirtualBox/Vagrant environment. Every section explains not just _what_ we did but _why_ it matters.

---

## Table of Contents

1. [Cluster Architecture](#1-cluster-architecture)
2. [Installing Kubernetes Tooling](#2-installing-kubernetes-tooling)
3. [Initializing the Control Plane with kubeadm](#3-initializing-the-control-plane-with-kubeadm)
4. [What is a CNI Plugin?](#4-what-is-a-cni-plugin)
5. [Installing Calico](#5-installing-calico)
6. [Debugging: Pod CIDR Overlap](#6-debugging-pod-cidr-overlap)
7. [Debugging: Stale Certificates After Reset](#7-debugging-stale-certificates-after-reset)
8. [Debugging: Wrong Node IPs (VirtualBox NAT)](#8-debugging-wrong-node-ips-virtualbox-nat)
9. [Fixing Node IPs via Kubelet](#9-fixing-node-ips-via-kubelet)
10. [Final Cluster State](#10-final-cluster-state)
11. [Key Concepts Glossary](#11-key-concepts-glossary)
12. [Further Reading](#12-further-reading)

---

## 1. Cluster Architecture

Our cluster uses the topology defined in `bootstrap/vagrantfile`:

| Role          | Hostname        | IP               | CPU | RAM  |
|---------------|-----------------|------------------|-----|------|
| Control Plane | `control-plane` | `192.168.56.10`  | 2   | 4GB  |
| Worker        | `worker-1`      | `192.168.56.11`  | 2   | 2GB  |
| Worker        | `worker-2`      | `192.168.56.12`  | 2   | 2GB  |
| Worker        | `worker-3`      | `192.168.56.13`  | 2   | 2GB  |

The VMs are connected on a **host-only network** (`192.168.56.0/24`), which means the VMs can talk to each other and to your Mac, but not to the internet directly. VirtualBox also gives each VM a separate **NAT interface** (`10.0.2.15`) for internet access.

> **Why host-only networking?** It gives each VM a stable, unique, routable IP that you control. Without it, Kubernetes nodes would only be reachable through NAT, which causes the IP conflicts we debug later in this document.

References:
- [VirtualBox Networking Modes](https://www.virtualbox.org/manual/ch06.html)
- [Vagrant Networking](https://developer.hashicorp.com/vagrant/docs/networking)

---

## 2. Installing Kubernetes Tooling

On each node we installed three binaries from the official Kubernetes apt repository:

```bash
apt-get install -y apt-transport-https

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | \
  gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | \
  tee /etc/apt/sources.list.d/kubernetes.list

apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
systemctl enable kubelet
```

### What each binary does

| Binary    | Purpose |
|-----------|---------|
| `kubelet` | The node agent. Runs on every node. Receives pod specs from the API server and ensures containers are running via the container runtime (containerd). |
| `kubeadm` | A one-shot bootstrap tool. Used to initialize the control plane and join worker nodes. Not used after the cluster is up. |
| `kubectl` | The CLI for interacting with the Kubernetes API. You use this to deploy apps, inspect pods, debug issues, etc. |

### Why `apt-mark hold`?

Kubernetes components must all run the **same version**. If `apt upgrade` silently upgrades `kubelet` to v1.30 while your API server is still v1.29, the cluster breaks. Holding pins the versions until you explicitly upgrade.

References:
- [Installing kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/)
- [Kubernetes version skew policy](https://kubernetes.io/docs/setup/release/version-skew-policy/)

---

## 3. Initializing the Control Plane with kubeadm

On the control plane node:

```bash
kubeadm init --apiserver-advertise-address=192.168.56.10 --pod-network-cidr=10.244.0.0/16 --cri-socket=unix:///run/containerd/containerd.sock
```

### Flag-by-flag breakdown

| Flag | Value | Why |
|------|-------|-----|
| `--apiserver-advertise-address` | `192.168.56.10` | Tells the API server which IP to listen on and advertise. Must be the host-only IP, not the NAT IP. |
| `--pod-network-cidr` | `10.244.0.0/16` | Reserves an IP range for pods. Must not overlap with node IPs or your home network. |
| `--cri-socket` | `unix:///run/containerd/containerd.sock` | Tells kubeadm which container runtime to use. We use containerd, not Docker. |

### What kubeadm init actually does

1. Generates TLS certificates for the API server, etcd, and all internal communication.
2. Starts the control plane static pods: `kube-apiserver`, `kube-controller-manager`, `kube-scheduler`, `etcd`.
3. Creates the `kube-system` namespace and installs `kube-proxy` and `CoreDNS`.
4. Outputs a `kubeadm join` command with a token for workers to use.

After init, you copy the admin kubeconfig:

```bash
mkdir -p $HOME/.kube
cp /etc/kubernetes/admin.conf $HOME/.kube/config
```

This file contains the certificates and API server address that `kubectl` needs to authenticate.

References:
- [kubeadm init reference](https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-init/)
- [Kubernetes control plane components](https://kubernetes.io/docs/concepts/overview/components/#control-plane-components)

---

## 4. What is a CNI Plugin?

After `kubeadm init`, the nodes are `NotReady` and no pods can be scheduled. This is because Kubernetes itself does **not** implement pod networking — it delegates that to a **CNI (Container Network Interface) plugin**.

### The problem CNI solves

Every pod in Kubernetes gets its own IP address. For this to work:
- Pods on the same node must be able to reach each other.
- Pods on **different** nodes must also be able to reach each other (without NAT).
- Services need to be able to route to pods.

Kubernetes defines the rules ([the network model](https://kubernetes.io/docs/concepts/services-networking/#the-kubernetes-network-model)) but leaves the implementation to CNI plugins.

### How CNI works

When `kubelet` creates a pod, it calls the CNI plugin binary (installed at `/opt/cni/bin/`) and passes it the pod's network namespace. The CNI plugin:
1. Creates a virtual network interface in the pod's namespace.
2. Assigns it an IP from the pod CIDR.
3. Sets up routes so other nodes know how to reach that IP.

If the CNI plugin isn't running, `kubelet` throws:
```
plugin type="calico" failed (add): stat /var/lib/calico/nodename: no such file or directory
```
This means the Calico node agent hasn't written its node registration file yet — it's not up.

References:
- [CNI specification](https://github.com/containernetworking/cni/blob/main/SPEC.md)
- [Kubernetes network model](https://kubernetes.io/docs/concepts/services-networking/#the-kubernetes-network-model)
- [Cluster networking overview](https://kubernetes.io/docs/concepts/cluster-administration/networking/)

---

## 5. Installing Calico

We chose **Calico** as our CNI plugin. Calico uses **BGP (Border Gateway Protocol)** to exchange routing information between nodes, so pods on different nodes can reach each other directly.

```bash
curl -O https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml
kubectl apply -f calico.yaml
```

### What Calico deploys

| Component | Type | Purpose |
|-----------|------|---------|
| `calico-node` | DaemonSet | Runs on every node. Configures routes, manages the CNI plugin, runs BIRD (BGP daemon). |
| `calico-kube-controllers` | Deployment | Watches Kubernetes API for changes (node added/removed, NetworkPolicy changes) and updates Calico state. |

### The DaemonSet model

Because `calico-node` is a **DaemonSet**, Kubernetes automatically ensures exactly one pod runs on every node — including new nodes added later. This is the standard pattern for node-level infrastructure like CNI plugins, log collectors, and monitoring agents.

References:
- [Calico architecture](https://docs.tigera.io/calico/latest/reference/architecture/overview)
- [Kubernetes DaemonSets](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/)
- [BGP explained](https://www.cloudflare.com/learning/security/glossary/what-is-bgp/)

---

## 6. Debugging: Pod CIDR Overlap

### The mistake

Our first `kubeadm init` used `--pod-network-cidr=192.168.0.0/16`. This was wrong.

The node IPs are in the `192.168.56.0/24` range. The subnet `192.168.56.0/24` is a **subset** of `192.168.0.0/16` — meaning the pod CIDR and the node network overlapped.

```
192.168.0.0/16  covers  192.168.0.0 → 192.168.255.255
192.168.56.10           ← node IP falls inside this range!
```

### Why this breaks things

Calico tries to assign pod IPs from `192.168.0.0/16`. When it sets up routes, the kernel gets confused: is `192.168.56.11` a pod or a node? BGP routing breaks, and calico-node gets stuck in `Init:0/3`.

### The fix

Reset the cluster and reinitialize with a non-overlapping CIDR:

```bash
# On control plane
kubeadm reset -f --cri-socket=unix:///run/containerd/containerd.sock
rm -rf /etc/cni/net.d /var/lib/etcd /var/lib/kubelet /etc/kubernetes

# Reinit with safe CIDR
kubeadm init --apiserver-advertise-address=192.168.56.10 --pod-network-cidr=10.244.0.0/16 --cri-socket=unix:///run/containerd/containerd.sock

# On each worker
kubeadm reset -f --cri-socket=unix:///run/containerd/containerd.sock
rm -rf /etc/cni/net.d /var/lib/kubelet
```

`10.244.0.0/16` is the conventional Flannel/Calico-friendly range that doesn't conflict with typical home or VM networks.

References:
- [CIDR notation explained](https://www.digitalocean.com/community/tutorials/understanding-ip-addresses-subnets-and-cidr-notation-for-networking)
- [kubeadm reset](https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-reset/)

---

## 7. Debugging: Stale Certificates After Reset

After resetting and reinitializing, `kubectl apply -f calico.yaml` failed:

```
tls: failed to verify certificate: x509: certificate signed by unknown authority
```

### Why this happens

`~/.kube/config` still contained the TLS certificates from the **old** cluster (the one we reset). The new cluster generated entirely new certificates, so `kubectl` was trying to authenticate with credentials that the new API server didn't recognize.

### The fix

Overwrite the kubeconfig with the new cluster's admin config:

```bash
mkdir -p $HOME/.kube
cp -f /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config
```

`/etc/kubernetes/admin.conf` is always regenerated by `kubeadm init` for the current cluster.

References:
- [Kubeconfig files](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/)
- [TLS in Kubernetes](https://kubernetes.io/docs/tasks/tls/managing-tls-in-a-cluster/)

---

## 8. Debugging: Wrong Node IPs (VirtualBox NAT)

### The problem

After the cluster came up, `kubectl get nodes -o wide` showed:

```
control-plane   Ready   192.168.56.10   ← correct
worker-1        Ready   10.0.2.15       ← WRONG
worker-2        Ready   10.0.2.15       ← WRONG
```

All workers reported `10.0.2.15` — the VirtualBox NAT interface IP. All VMs share this same NAT IP.

### Why the kubelet picks the wrong interface

When `kubelet` starts, it determines the node IP by looking at the default route:

```bash
ip route show default
# default via 10.0.2.2 dev enp0s3
```

The default route uses `enp0s3` (the NAT interface), so kubelet registers `10.0.2.15` as the node IP — even though `enp0s8` has the real unique host-only IP.

### Why this breaks the cluster

Calico uses BGP to share pod routes between nodes. BGP peers are identified by their node IP. If two nodes both register as `10.0.2.15`:
- Calico thinks they're the same node.
- BGP peering fails.
- Pods on different nodes cannot communicate.
- All cross-node service calls fail silently.

For a microservices app like Online Boutique where `frontend` calls `productcatalog`, `cart`, `checkout`, etc., this means roughly half of all requests would fail depending on where pods land.

References:
- [VirtualBox NAT networking](https://www.virtualbox.org/manual/ch06.html#network_nat)
- [Calico BGP peering](https://docs.tigera.io/calico/latest/networking/configuring/bgp)

---

## 9. Fixing Node IPs via Kubelet

### Why Calico's `IP_AUTODETECTION_METHOD` wasn't enough

We first tried:

```bash
kubectl set env daemonset/calico-node -n kube-system IP_AUTODETECTION_METHOD=interface=enp0s8
```

This tells Calico which interface to use for BGP — but the problem is deeper. The **kubelet** itself had already registered the node in the Kubernetes API with IP `10.0.2.15`. Fixing Calico's view doesn't fix what the API server knows about each node.

### The real fix: `--node-ip` kubelet flag

The kubelet flag `--node-ip` explicitly tells kubelet which IP to advertise to the API server. It's stored in:

```
/var/lib/kubelet/kubeadm-flags.env
```

We appended `--node-ip=<correct-ip>` to the existing flags on each node:

```bash
# control-plane
echo 'KUBELET_KUBEADM_ARGS="--container-runtime-endpoint=unix:///run/containerd/containerd.sock --pod-infra-container-image=registry.k8s.io/pause:3.9 --node-ip=192.168.56.10"' > /var/lib/kubelet/kubeadm-flags.env
systemctl restart kubelet
```

```bash
# worker-1
echo 'KUBELET_KUBEADM_ARGS="... --node-ip=192.168.56.11"' > /var/lib/kubelet/kubeadm-flags.env
systemctl restart kubelet
```

```bash
# worker-2
echo 'KUBELET_KUBEADM_ARGS="... --node-ip=192.168.56.12"' > /var/lib/kubelet/kubeadm-flags.env
systemctl restart kubelet
```

After restarting kubelet, the API server updates the node's `InternalIP` field, and Calico reconfigures BGP peering on the correct IPs.

### Why we preserved the existing flags

The original content of `kubeadm-flags.env` was:
```
KUBELET_KUBEADM_ARGS="--container-runtime-endpoint=... --pod-infra-container-image=..."
```

- `--container-runtime-endpoint` tells kubelet where to find containerd's socket.
- `--pod-infra-container-image` sets the pause container image used for every pod's network namespace.

Both are required — removing them would break the node.

References:
- [kubelet configuration](https://kubernetes.io/docs/reference/config-api/kubelet-config.v1beta1/)
- [kubeadm-flags.env explained](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/kubelet-integration/)
- [The pause container](https://www.ianlewis.org/en/almighty-pause-container)

---

## 10. Final Cluster State

```
NAME            STATUS   ROLES           AGE   VERSION    INTERNAL-IP
control-plane   Ready    control-plane   ~20m  v1.29.15   192.168.56.10
worker-1        Ready    <none>          ~19m  v1.29.15   192.168.56.11
worker-2        Ready    <none>          ~18m  v1.29.15   192.168.56.12
```

All system pods running:

```
calico-kube-controllers   1/1 Running
calico-node (x3)          1/1 Running  ← one per node
coredns (x2)              1/1 Running
etcd                      1/1 Running
kube-apiserver            1/1 Running
kube-controller-manager   1/1 Running
kube-proxy (x3)           1/1 Running  ← one per node
kube-scheduler            1/1 Running
```

The cluster is ready for application workloads.

---

## 11. Key Concepts Glossary

| Term | Definition |
|------|-----------|
| **CNI** | Container Network Interface. A standard for how network plugins integrate with container runtimes. |
| **DaemonSet** | A Kubernetes workload that ensures one pod runs on every node (or a subset). Used for node-level agents. |
| **BGP** | Border Gateway Protocol. A routing protocol that shares IP route information between nodes. Calico uses it to enable cross-node pod communication. |
| **Pod CIDR** | The IP address range reserved for pods across the whole cluster. |
| **kubeconfig** | A YAML file containing API server address, TLS certificates, and credentials for `kubectl`. |
| **kubelet** | The primary node agent. Runs on every node. Responsible for starting, stopping, and monitoring pods. |
| **pause container** | A tiny container that holds the network namespace for a pod. All other containers in the pod share its network. |
| **host-only network** | A VirtualBox network mode that gives VMs unique IPs reachable from the host but not the internet. |
| **NAT interface** | VirtualBox's default network for internet access. All VMs share the same external IP (`10.0.2.15`). |
| **BIRD** | BGP Internet Routing Daemon. The process inside `calico-node` that handles BGP peering. |

---

## 12. Further Reading

- [Kubernetes the Hard Way](https://github.com/kelseyhightower/kubernetes-the-hard-way) — Build a cluster manually to understand every component deeply.
- [Official kubeadm docs](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/)
- [Calico docs](https://docs.tigera.io/calico/latest/about/)
- [CNI plugins repository](https://github.com/containernetworking/plugins)
- [Kubernetes networking deep dive (Cloudflare blog)](https://blog.cloudflare.com/moving-k8s-communication-to-grpc/)
- [How BGP works (Cloudflare)](https://www.cloudflare.com/learning/security/glossary/what-is-bgp/)
- [The almighty pause container](https://www.ianlewis.org/en/almighty-pause-container)
- [IP addressing and CIDR](https://www.digitalocean.com/community/tutorials/understanding-ip-addresses-subnets-and-cidr-notation-for-networking)
