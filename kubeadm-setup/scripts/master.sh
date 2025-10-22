#!/bin/bash
#
# Setup script for Kubernetes Control Plane (Master)
# Safe for AWS / Azure / Local VMs

set -euxo pipefail

# CONFIGURATION
PUBLIC_IP_ACCESS="false"         # set true if you need public API access
POD_CIDR="192.168.0.0/16"
NODENAME=$(hostname -s)

echo "==== Pulling required kubeadm images ===="
sudo kubeadm config images pull

echo "==== Detecting IP Address ===="
# Auto-detect first non-loopback interface with private IP
MASTER_PRIVATE_IP=$(hostname -I | awk '{print $1}')
echo "Detected MASTER_PRIVATE_IP: $MASTER_PRIVATE_IP"

# Initialize kubeadm
if [[ "$PUBLIC_IP_ACCESS" == "false" ]]; then
    echo "==== Initializing control plane using PRIVATE IP ===="
    sudo kubeadm init \
      --apiserver-advertise-address="$MASTER_PRIVATE_IP" \
      --apiserver-cert-extra-sans="$MASTER_PRIVATE_IP" \
      --pod-network-cidr="$POD_CIDR" \
      --node-name "$NODENAME" \
      --ignore-preflight-errors=Swap

elif [[ "$PUBLIC_IP_ACCESS" == "true" ]]; then
    echo "==== Initializing control plane using PUBLIC IP ===="
    MASTER_PUBLIC_IP=$(curl -s ifconfig.me)
    echo "Detected MASTER_PUBLIC_IP: $MASTER_PUBLIC_IP"

    sudo kubeadm init \
      --control-plane-endpoint="$MASTER_PUBLIC_IP" \
      --apiserver-cert-extra-sans="$MASTER_PUBLIC_IP" \
      --pod-network-cidr="$POD_CIDR" \
      --node-name "$NODENAME" \
      --ignore-preflight-errors=Swap
else
    echo "Error: Invalid value for PUBLIC_IP_ACCESS: $PUBLIC_IP_ACCESS"
    exit 1
fi

echo "==== Configuring kubeconfig for kubectl ===="
mkdir -p "$HOME"/.kube
sudo cp -i /etc/kubernetes/admin.conf "$HOME"/.kube/config
sudo chown "$(id -u)":"$(id -g)" "$HOME"/.kube/config

echo "==== Waiting for control plane pods to start ===="
sleep 15

echo "==== Installing Calico CNI Plugin ===="
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.2/manifests/calico.yaml

echo "==== Cluster setup complete! ===="
echo "To join worker nodes, run the following command on each worker:"

kubeadm token create --print-join-command
