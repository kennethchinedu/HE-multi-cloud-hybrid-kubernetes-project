#!/bin/bash

# Kubernetes Control Plane Bootstrap
# Usage: sudo bash bootstrap_local.sh <control_plane_ip> <pod_network_cidr>
# Example: sudo bash bootstrap_local.sh 192.168.56.10 192.168.0.0/16

set -euo pipefail


# Inputs

if [[ $# -lt 2 ]]; then
  echo "Usage: sudo bash $0 <control_plane_ip> <pod_network_cidr>"
  echo "Example: sudo bash $0 192.168.56.10 192.168.0.0/16"
  exit 1
fi

CONTROL_PLANE_IP="$1"
POD_NETWORK_CIDR="$2"

echo "==> Control plane IP : $CONTROL_PLANE_IP"
echo "==> Pod network CIDR : $POD_NETWORK_CIDR"


#  Pre-requisites

echo "==> [1/6] Applying pre-requisites..."

swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

modprobe overlay
modprobe br_netfilter

cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system


#— Install containerd

echo "==> [2/6] Installing containerd..."

apt-get update -qq
apt-get install -y ca-certificates curl gnupg lsb-release

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --batch --yes --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list

apt-get update -qq
apt-get install -y containerd.io

containerd config default | tee /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

systemctl restart containerd
systemctl enable containerd


# Section 3 — Install kubeadm, kubelet, kubectl

echo "==> [3/6] Installing kubeadm, kubelet, kubectl..."

apt-get install -y apt-transport-https

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | \
  gpg --batch --yes --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | \
  tee /etc/apt/sources.list.d/kubernetes.list

apt-get update -qq
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

systemctl enable kubelet


# Section 4 — Initialise control plane

echo "==> [4/6] Initialising control plane..."

if [ -f /etc/kubernetes/admin.conf ]; then
  echo "==> Existing cluster detected — resetting before reinitialising..."
  kubeadm reset -f
  rm -rf /etc/cni/net.d /var/lib/etcd "$HOME/.kube"
  iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X
fi

echo "==> Ensuring containerd is running..."
systemctl restart containerd
until [ -S /run/containerd/containerd.sock ]; do
  echo "   waiting for containerd socket..."
  sleep 2
done
echo "==> containerd is ready."

kubeadm init \
  --apiserver-advertise-address="$CONTROL_PLANE_IP" \
  --pod-network-cidr="$POD_NETWORK_CIDR" \
  --cri-socket=unix:///run/containerd/containerd.sock

mkdir -p "$HOME/.kube"
cp -i /etc/kubernetes/admin.conf "$HOME/.kube/config"
chown "$(id -u):$(id -g)" "$HOME/.kube/config"


#  Install Calico CNI

echo "==> [5/6] Installing Calico CNI..."

kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.3/manifests/tigera-operator.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.3/manifests/custom-resources.yaml

echo "==> Waiting for Calico pods to become Ready..."
kubectl wait --for=condition=Ready pods --all -n calico-system --timeout=180s


# Section 6 — Label control plane node

echo "==> [6/7] Labelling control plane node..."
kubectl label node "$(hostname)" node=control
echo "==> Node labelled as node=control."


# Section 7 — Print join command for workers

echo "==> [7/7] Cluster ready. Run this command on each worker node:"
echo ""
kubeadm token create --print-join-command
echo ""
