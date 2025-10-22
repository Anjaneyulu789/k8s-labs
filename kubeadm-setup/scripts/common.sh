#!/bin/bash
#
# Common setup script for Kubernetes Control Plane and Worker Nodes
# Works on Amazon Linux 2 / CentOS / RHEL-based systems

set -euxo pipefail

# Kubernetes version
KUBERNETES_VERSION="1.29.0"

echo "==== Disabling swap ===="
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Disable swap permanently (in case crontab is used)
(crontab -l 2>/dev/null; echo "@reboot /sbin/swapoff -a") | crontab - || true

echo "==== Updating system packages ===="
sudo yum update -y

echo "==== Setting up required kernel modules ===="
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# sysctl params required by setup, persist across reboots
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system

echo "==== Installing containerd ===="
sudo yum install -y yum-utils device-mapper-persistent-data lvm2
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo sed -i 's/\$releasever/7/g' /etc/yum.repos.d/docker-ce.repo
sudo yum install -y containerd.io || sudo yum install -y https://download.docker.com/linux/centos/7/x86_64/stable/Packages/containerd.io-1.6.28-3.1.el7.x86_64.rpm

sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

sudo systemctl enable containerd --now

echo "==== Adding Kubernetes repository ===="
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

echo "==== Installing Kubernetes components (kubeadm, kubelet, kubectl) ===="
sudo yum install -y kubelet-${KUBERNETES_VERSION}* kubeadm-${KUBERNETES_VERSION}* kubectl-${KUBERNETES_VERSION}* --disableexcludes=kubernetes
sudo systemctl enable --now kubelet

# Optional: Install jq for JSON parsing
sudo yum install -y jq

# Set node IP dynamically
local_ip="$(hostname -I | awk '{print $1}')"
cat <<EOF | sudo tee /etc/default/kubelet
KUBELET_EXTRA_ARGS=--node-ip=$local_ip
EOF

echo "==== Common setup completed successfully! ===="
