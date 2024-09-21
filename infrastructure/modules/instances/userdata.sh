#!/bin/bash

# Enable exit on error and undefined variables
set -eu

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Variables
K8S_VERSION="1.31"
CALICO_VERSION="v3.28.1"
POD_NETWORK_CIDR="10.244.0.0/16"
REGION="${region}"
HOME="/home/ubuntu"

# Determine if this is a controlplane or worker node
NODE_TYPE="${node_type}"

log "Starting Kubernetes $NODE_TYPE node setup"

# Common setup for both controlplane and worker nodes
setup_common() {
    log "Updating system and installing prerequisites"
    sudo apt update -y
    sudo apt install -y curl gnupg2 software-properties-common apt-transport-https ca-certificates

    log "Disabling swap"
    sudo swapoff -a
    sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

    log "Configuring kernel modules"
    cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
    overlay
    br_netfilter
EOF
    sudo modprobe overlay
    sudo modprobe br_netfilter

    log "Configuring sysctl params"
    cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
    net.bridge.bridge-nf-call-iptables  = 1
    net.bridge.bridge-nf-call-ip6tables = 1
    net.ipv4.ip_forward                 = 1
EOF
    sudo sysctl --system

    log "Installing containerd"
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update
    sudo apt install -y containerd.io

    log "Configuring containerd"
    sudo mkdir -p /etc/containerd
    containerd config default | sudo tee /etc/containerd/config.toml >/dev/null 2>&1
    sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml
    sudo systemctl restart containerd
    sudo systemctl enable containerd

    log "Installing Kubernetes components"
    sudo mkdir -p /etc/apt/keyrings
    sudo curl -fsSL https://pkgs.k8s.io/core:/stable:/v$K8S_VERSION/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v$K8S_VERSION/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
    sudo apt-get update
    sudo apt-get install -y kubelet kubeadm kubectl
    sudo apt-mark hold kubelet kubeadm kubectl

    log "Installing AWS CLI"
    sudo apt-get install -y awscli

    log "Installing Helm"
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
}

setup_controlplane() {
    log "Initializing Kubernetes controlplane node"
    sudo kubeadm config images pull
    sudo kubeadm init --pod-network-cidr=$POD_NETWORK_CIDR

    log "Configuring kubectl for the current user"
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown ubuntu:ubuntu $HOME/.kube/config

    log "Installing Calico network plugin"
    /sbin/runuser ubuntu -s /bin/bash -c "
    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/$CALICO_VERSION/manifests/tigera-operator.yaml
    sudo curl https://raw.githubusercontent.com/projectcalico/calico/$CALICO_VERSION/manifests/custom-resources.yaml -O
    sudo sed -i 's/cidr: 192\.168\.0\.0\/16/cidr: 10.244.0.0\/16/g' custom-resources.yaml
    kubectl create -f custom-resources.yaml"

    log "Generating join command for worker nodes"
    JOIN_COMMAND=$(kubeadm token create --print-join-command)
    
    # Update the SSM parameter with the real join command
    if ! aws ssm put-parameter \
        --name "/k8s/join-command" \
        --type "SecureString" \
        --value "$JOIN_COMMAND" \
        --region $REGION \
        --overwrite; then
        log "Error: Failed to update SSM parameter with join command"
        return 1
    fi

    # Verify the parameter was updated correctly
    VERIFIED_COMMAND=$(aws ssm get-parameter \
        --name "/k8s/join-command" \
        --with-decryption \
        --query "Parameter.Value" \
        --output text \
        --region $REGION)

    if [ "$JOIN_COMMAND" != "$VERIFIED_COMMAND" ]; then
        log "Error: SSM parameter verification failed"
        return 1
    fi

    log "Join command stored in Parameter Store"
}

setup_worker() {
    log "Retrieving join command from Parameter Store"
    # Implement a retry mechanism
    max_attempts=5
    attempt=1
    while [ $attempt -le $max_attempts ]; do
        JOIN_COMMAND=$(aws ssm get-parameter \
            --name "/k8s/join-command" \
            --with-decryption \
            --query "Parameter.Value" \
            --output text \
            --region $REGION)

        if [ -n "$JOIN_COMMAND" ] && [ "$JOIN_COMMAND" != "placeholder" ]; then
            log "Join command retrieved successfully"
            break
        fi

        log "Attempt $attempt: Failed to retrieve valid join command, retrying in 30 seconds..."
        sleep 30
        attempt=$((attempt+1))
    done

    if [ $attempt -gt $max_attempts ]; then
        log "Error: Failed to retrieve valid join command after $max_attempts attempts"
        return 1
    fi

    log "Joining the Kubernetes cluster"
    if ! sudo $JOIN_COMMAND; then
        log "Error: Failed to join the Kubernetes cluster"
        return 1
    fi

    log "Successfully joined the Kubernetes cluster"

}

# Main execution
setup_common

if [ "$NODE_TYPE" == "controlplane" ]; then
    setup_controlplane
elif [ "$NODE_TYPE" == "worker" ]; then
    setup_worker
else
    log "Error: Invalid node type specified. Must be 'controlplane' or 'worker'."
    exit 1
fi

log "Kubernetes $NODE_TYPE node setup completed"