#!/bin/bash

# Kubernetes Worker Node Bootstrap
# Usage: sudo bash bootstrap_worker_local.sh <control_plane_ip> <token> <ca_hash>
# Example: sudo bash bootstrap_worker_local.sh 192.168.56.10 abc123.xyz token sha256:abcdef...
#
# Get <token> and <ca_hash> from the control plane by running:
#   kubeadm token create --print-join-command
#

set -euo pipefail

# -----------------------------------------------------------------------------
# Inputs
# -----------------------------------------------------------------------------
if [[ $# -lt 3 ]]; then
  echo "Usage: sudo bash $0 <control_plane_ip> <token> <ca_hash>"
  echo "Example: sudo bash $0 192.168.56.10 abc123.xyz123 sha256:abcdef1234..."
  echo ""
  echo "Get these values from the control plane:"
  echo "  kubeadm token create --print-join-command"
  exit 1
fi

CONTROL_PLANE_IP="$1"
JOIN_TOKEN="$2"
CA_HASH="$3"

echo "==> Control plane IP : $CONTROL_PLANE_IP"
echo "==> Join token       : $JOIN_TOKEN"
echo "==> CA hash          : $CA_HASH"

# -----------------------------------------------------------------------------
# Section 1 — Pre-requisites
# -----------------------------------------------------------------------------
echo "==> [1/4] Applying pre-requisites..."

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

# -----------------------------------------------------------------------------
# Section 2 — Install containerd
# -----------------------------------------------------------------------------
echo "==> [2/4] Installing containerd..."

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

# -----------------------------------------------------------------------------
# Section 3 — Install kubeadm, kubelet, kubectl
# -----------------------------------------------------------------------------
echo "==> [3/4] Installing kubeadm, kubelet, kubectl..."

apt-get install -y apt-transport-https

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | \
  gpg --batch --yes --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | \
  tee /etc/apt/sources.list.d/kubernetes.list

apt-get update -qq
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

systemctl enable kubelet

# -----------------------------------------------------------------------------
# Section 4 — Join the cluster
# -----------------------------------------------------------------------------
echo "==> [4/4] Joining the cluster..."

if [ -f /etc/kubernetes/kubelet.conf ]; then
  echo "==> Node already joined — resetting before rejoining..."
  kubeadm reset -f
  rm -rf /etc/cni/net.d "$HOME/.kube"
  iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X
fi

echo "==> Ensuring containerd is running..."
systemctl restart containerd
until [ -S /run/containerd/containerd.sock ]; do
  echo "   waiting for containerd socket..."
  sleep 2
done
echo "==> containerd is ready."

kubeadm join "${CONTROL_PLANE_IP}:6443" \
  --token "${JOIN_TOKEN}" \
  --discovery-token-ca-cert-hash "${CA_HASH}" \
  --cri-socket=unix:///run/containerd/containerd.sock

echo "==> Worker node joined successfully."

# -----------------------------------------------------------------------------
# Section 5 — Label this node
# -----------------------------------------------------------------------------
echo "==> [5/4] Labelling node..."
kubectl label node "$(hostname)" node=worker
echo "==> Node labelled as node=worker."
