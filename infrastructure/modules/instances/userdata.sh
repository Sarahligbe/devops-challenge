#!/bin/bash

# Enable exit on error and undefined variables
set -eu

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Variables
K8S_VERSION="1.31"
CALICO_VERSION="v3.28.2"
POD_NETWORK_CIDR="192.168.0.0/16"
REGION="${region}"
HOME="/home/ubuntu"
# Set variables for IRSA configuration
DISCOVERY_BUCKET="${discovery_bucket_name}" 
IRSA_DIR="/etc/kubernetes/irsa"
PKCS_KEY="$IRSA_DIR/oidc-issuer.pub"
PRIV_KEY="$IRSA_DIR/oidc-issuer.key"
ISSUER_HOSTPATH="s3-${region}.amazonaws.com/${discovery_bucket_name}"
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
    log "Creating a directory for the IRSA bucket"
    mkdir -p $IRSA_DIR

    log "Retrieving IRSA keys from s3 bucket"
    aws s3 cp s3://$DISCOVERY_BUCKET/keys/oidc-issuer.pub $PKCS_KEY
    aws s3 cp s3://$DISCOVERY_BUCKET/keys/oidc-issuer.key $PRIV_KEY

    log "Setting strict permissions on the directory and files"
    sudo chmod 700 $IRSA_DIR
    sudo chmod 600 $PKCS_KEY $PRIV_KEY

    log "Creating kubeconfig file"
    cat <<-EOT > kubeadm-config.yaml
    apiVersion: kubeadm.k8s.io/v1beta3
    kind: ClusterConfiguration
    apiServer:
      extraArgs:
        service-account-key-file: /etc/kubernetes/irsa/oidc-issuer.pub
        service-account-signing-key-file: /etc/kubernetes/irsa/oidc-issuer.key
        api-audiences: "sts.amazonaws.com"
        service-account-issuer: "https://$ISSUER_HOSTPATH"
      extraVolumes:
        - name: irsa-keys
          hostPath: "/home/ubuntu/$IRSA_DIR"
          mountPath: /etc/kubernetes/irsa
          readOnly: true
          pathType: DirectoryOrCreate
    networking:
      podSubnet: 192.168.0.0/16
EOT
    
    log "Initializing Kubernetes controlplane node"
    sudo kubeadm init --config kubeadm-config.yaml

    log "set up kubeconfig"
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown ubuntu:ubuntu $HOME/.kube/config

    log "Installing Calico network plugin"
    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/$CALICO_VERSION/manifests/calico.yaml
    kubectl set env daemonset/calico-node -n kube-system ICALICO_IPV4POOL_IPIP=CrossSubnet

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

    log "Installing cert manager CRDs"
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.15.3/cert-manager.crds.yaml

    log "Adding cert manager helm repo"
    helm repo add cert-manager https://charts.jetstack.io

    log "Installing cert-manager helm chart"
    helm install certs cert-manager/cert-manager --version 1.15.3

    sleep 60s

    log "cert-manager is ready. Installing aws-pod-identity-webhook"
    kubectl create -f https://raw.githubusercontent.com/aws/amazon-eks-pod-identity-webhook/refs/heads/master/deploy/auth.yaml
    kubectl create -f https://raw.githubusercontent.com/aws/amazon-eks-pod-identity-webhook/refs/heads/master/deploy/service.yaml
    kubectl create -f https://raw.githubusercontent.com/aws/amazon-eks-pod-identity-webhook/refs/heads/master/deploy/mutatingwebhook.yaml
    kubectl create -f https://raw.githubusercontent.com/aws/amazon-eks-pod-identity-webhook/refs/heads/master/deploy/deployment-base.yaml

    log "aws-pod-identity-webhook installation completed"
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
    /sbin/runuser -l ubuntu << EOF
$(declare -f log setup_controlplane)
setup_controlplane
EOF
elif [ "$NODE_TYPE" == "worker" ]; then
    /sbin/runuser -l ubuntu << EOF
$(declare -f log setup_worker)
setup_worker
EOF
else
    log "Error: Invalid node type specified. Must be 'controlplane' or 'worker'"
    exit 1
fi