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
IRSA_DIR="irsa_keys"
PKCS_KEY="$IRSA_DIR/oidc-issuer.pub"
PRIV_KEY="$IRSA_DIR/oidc-issuer.key"
ISSUER_HOSTPATH="s3-${region}.amazonaws.com/${discovery_bucket_name}"
# Determine if this is a controlplane or worker node
NODE_TYPE="${node_type}"
CLUSTER_NAME="${cluster_name}"
AWS_LB_ROLE_ARN="${aws_lb_role_arn}"
HOSTNAME="$(curl -s http://169.254.169.254/latest/meta-data/local-hostname)"
INSTANCE_ID="$(curl -s http://169.254.169.254/latest/meta-data/instance-id)"
GRAFANA_PASSWD="${grafana_passwd}"
CERT_ARN="${cert_arn}"
DOMAIN="${domain}"
DNS_ROLE_ARN="${dns_role_arn}"

log "Starting Kubernetes $NODE_TYPE node setup"

# Common setup for both controlplane and worker nodes
setup_common() {
    log "Setting up hostname"
    sudo hostnamectl set-hostname $HOSTNAME
    
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

    log "Retrieving IRSA keys from SSM Parameter Store"
    aws ssm get-parameter --name "/k8s/irsa/private-key" --with-decryption --query "Parameter.Value" --region $REGION --output text > $PRIV_KEY
    aws ssm get-parameter --name "/k8s/irsa/public-key" --with-decryption --query "Parameter.Value" --region $REGION --output text > $PKCS_KEY

    log "Creating kubeconfig file"
    cat <<EOF > kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
apiServer:
  extraArgs:
    - name: "service-account-key-file"
      value: "/etc/kubernetes/irsa/oidc-issuer.pub"
    - name: "service-account-signing-key-file"
      value: "/etc/kubernetes/irsa/oidc-issuer.key"
    - name: "api-audiences" 
      value: "sts.amazonaws.com"
    - name: "service-account-issuer"
      value:  "https://$ISSUER_HOSTPATH"
  extraVolumes:
    - name: irsa-keys
      hostPath: "/home/ubuntu/$IRSA_DIR"
      mountPath: /etc/kubernetes/irsa
      readOnly: true
      pathType: DirectoryOrCreate
networking:
  podSubnet: 192.168.0.0/16
EOF
    
    log "Initializing Kubernetes controlplane node"
    sudo kubeadm init --config kubeadm-config.yaml --v=5

    log "set up kubeconfig"
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown ubuntu:ubuntu $HOME/.kube/config

    log "Storing kubeconfig in SSM Parameter Store"
    KUBECONFIG_CONTENT=$(cat $HOME/.kube/config | base64 -w 0)
    aws ssm put-parameter \
        --name "/k8s/kubeconfig" \
        --type "SecureString" \
        --value "$KUBECONFIG_CONTENT" \
        --tier "Advanced" \
        --region $REGION \
        --overwrite

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

    log "Update providerID"
    kubectl patch node $HOSTNAME -p "{\"spec\":{\"providerID\":\"aws://$REGION/$INSTANCE_ID\"}}"
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

    log "Retrieving kubeconfig from SSM Parameter Store"
    KUBECONFIG_CONTENT=$(aws ssm get-parameter \
        --name "/k8s/kubeconfig" \
        --with-decryption \
        --query "Parameter.Value" \
        --output text \
        --region $REGION)

    if [ -n "$KUBECONFIG_CONTENT" ]; then
        log "Setting up kubeconfig for worker node"
        mkdir -p $HOME/.kube
        echo "$KUBECONFIG_CONTENT" | base64 -d > $HOME/.kube/config
        sudo chown ubuntu:ubuntu $HOME/.kube/config
        chmod 700 $HOME/.kube
        chmod 600 $HOME/.kube/config
        log "Kubeconfig set up successfully"
    else
        log "Error: Failed to retrieve kubeconfig from SSM Parameter Store"
        return 1
    fi

    log "Installing cert manager"
    kubectl create -f https://github.com/cert-manager/cert-manager/releases/download/v1.15.3/cert-manager.yaml

    log "Waiting for cert-manager pods to be ready"
    kubectl wait --for=condition=Ready pods --all -n cert-manager --timeout=300s

    log "Verifying cert-manager webhook"
    # Retry mechanism for webhook verification
    max_attempts=5
    attempt=1
    while [ $attempt -le $max_attempts ]; do
        if kubectl get validatingwebhookconfigurations cert-manager-webhook -o jsonpath='{.webhooks[0].clientConfig.service.name}' | grep -q "cert-manager-webhook"; then
            log "Cert-manager webhook is verified and ready"
            break
        fi
        log "Attempt $attempt: Cert-manager webhook not ready yet, waiting 30 seconds..."
        sleep 30
        attempt=$((attempt+1))
    done

    if [ $attempt -gt $max_attempts ]; then
        log "Error: Cert-manager webhook not ready after $max_attempts attempts"
        return 1
    fi

    log "cert-manager is ready. Installing aws-pod-identity-webhook"
    kubectl create -f https://raw.githubusercontent.com/aws/amazon-eks-pod-identity-webhook/refs/heads/master/deploy/auth.yaml
    kubectl create -f https://raw.githubusercontent.com/aws/amazon-eks-pod-identity-webhook/refs/heads/master/deploy/service.yaml
    kubectl create -f https://raw.githubusercontent.com/aws/amazon-eks-pod-identity-webhook/refs/heads/master/deploy/mutatingwebhook.yaml
    curl -o deployment.yaml https://raw.githubusercontent.com/aws/amazon-eks-pod-identity-webhook/refs/heads/master/deploy/deployment-base.yaml
    sed -i 's|IMAGE|amazon/amazon-eks-pod-identity-webhook:v0.5.7|' deployment.yaml
    kubectl apply -f deployment.yaml
    
    log "Waiting for pod identity pods to be ready"
    kubectl wait --for=condition=Ready pods --all -n cert-manager --timeout=300s

    log "aws-pod-identity-webhook installation completed"

    log "Update providerID"
    kubectl patch node $HOSTNAME -p "{\"spec\":{\"providerID\":\"aws://$REGION/$INSTANCE_ID\"}}"

    log "Setting up aws loadbalancer controller"
    cat <<EOF > aws_lb_service_account.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: aws-load-balancer-controller
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: $AWS_LB_ROLE_ARN
EOF
    kubectl apply -f aws_lb_service_account.yaml
    helm repo add eks https://aws.github.io/eks-charts
    helm install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system --set clusterName=$CLUSTER_NAME --set serviceAccount.create=false --set serviceAccount.name=aws-load-balancer-controller
    
    kubectl wait --for=condition=Available deployment/aws-load-balancer-controller -n kube-system --timeout=300s
    log "AWS LBC installed successfully"

    log "Installing external dns"
    cat <<EOF > external_dns_values.yaml
provider:
  name: aws
env:
  - name: AWS_DEFAULT_REGION
    value: "$REGION"
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: $DNS_ROLE_ARN
EOF
    helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/
    helm install external-dns external-dns/external-dns --values external_dns_values.yaml

    log "installing argocd"
    cat <<EOF > argo_cd_values.yaml
global:
  domain: "argocd.$DOMAIN"
server:
  ingress:
    enabled: true
    ingressClassName: alb
    annotations:
      alb.ingress.kubernetes.io/scheme: internet-facing
      alb.ingress.kubernetes.io/target-type: instance
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
      alb.ingress.kubernetes.io/ssl-redirect: "443"
      alb.ingress.kubernetes.io/group.name: bird-alb
      alb.ingress.kubernetes.io/certificate-arn: "$CERT_ARN"
      alb.ingress.kubernetes.io/backend-protocol: HTTP
      external-dns.alpha.kubernetes.io/hostname: "argocd.$DOMAIN"
    hostname: "argocd.$DOMAIN"
    paths:
      - /
    pathType: Prefix
  extraArgs:
    - --insecure
  service:
    type: NodePort
applicationSet:
  enabled: true
EOF
    helm repo add argo https://argoproj.github.io/argo-helm
    helm install argocd argo/argo-cd --namespace argocd --create-namespace --values argo_cd_values.yaml

    kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s

    log "Argocd installed successfully"

    log "Deploy bird app"
    cat <<EOF > bird_appset.yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: birdapp
  namespace: argocd
spec: 
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators: 
  - git: 
      repoURL: https://github.com/Sarahligbe/devops-challenge.git
      revision: HEAD
      directories: 
      - path: helm
  template: 
    metadata: 
      name: '{{.path.basename}}'
    spec: 
      project: default
      sources: 
        - repoURL: https://github.com/Sarahligbe/devops-challenge.git
          targetRevision: HEAD
          path: '{{.path.path}}'
          helm:
            parameters:
            - name: "global.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/listen-ports"
              value: '[{"HTTPS":443}]'
            - name: "global.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/ssl-redirect"
              value: "443"
            - name: "global.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/certificate-arn"
              value: "${CERT_ARN}"
            - name: "bird.ingress.annotations.external-dns\\.alpha\\.kubernetes\\.io/hostname"
              value: 'bird.${DOMAIN}'
            - name: "birdimage.ingress.annotations.external-dns\\.alpha\\.kubernetes\\.io/hostname"
              value: 'birdimage.${DOMAIN}'
            - name: "bird.ingress.hosts[0].host"
              value: "bird.${DOMAIN}"
            - name: "birdimage.ingress.hosts[0].host"
              value: "birdimage.${DOMAIN}"
      destination: 
        server: https://kubernetes.default.svc
        namespace: '{{.path.basename}}'
      syncPolicy: 
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
EOF
    log "Applying birdapp argocd manifest"
    kubectl apply -f bird_appset.yaml

    log "Installing Prometheus and grafana"
    cat <<EOF > prometheus_values.yaml
prometheus:
  service:
    type: NodePort
grafana:
  adminPassword: "$GRAFANA_PASSWD"
  ingress:
    enabled: true
    ingressClassName: alb
    annotations:
      alb.ingress.kubernetes.io/scheme: internet-facing
      alb.ingress.kubernetes.io/target-type: instance
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
      alb.ingress.kubernetes.io/ssl-redirect: "443"
      alb.ingress.kubernetes.io/group.name: bird-alb
      alb.ingress.kubernetes.io/certificate-arn: $CERT_ARN
      alb.ingress.kubernetes.io/backend-protocol: HTTP
      alb.ingress.kubernetes.io/healthcheck-path: /login
      external-dns.alpha.kubernetes.io/hostname: "grafana.$DOMAIN"
    hosts:
      - "grafana.$DOMAIN"
    path: /
    pathType: Prefix
  service:
    type: NodePort
EOF

    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm install monitoring prometheus-community/kube-prometheus-stack --namespace monitoring --create-namespace --values prometheus_values.yaml

    kubectl wait --for=condition=Ready pods --all -n monitoring --timeout=300s
    log "monitoring stack installed successfully"
    
}

# Main execution
setup_common


if [ "$NODE_TYPE" == "controlplane" ]; then
    /sbin/runuser -l ubuntu << EOF
export REGION="$REGION"
export DISCOVERY_BUCKET="$DISCOVERY_BUCKET"
export IRSA_DIR="$IRSA_DIR"
export PKCS_KEY="$PKCS_KEY"
export PRIV_KEY="$PRIV_KEY"
export ISSUER_HOSTPATH="$ISSUER_HOSTPATH"
export K8S_VERSION="$K8S_VERSION"
export CALICO_VERSION="$CALICO_VERSION"
export POD_NETWORK_CIDR="$POD_NETWORK_CIDR"
export HOSTNAME="$HOSTNAME"
export INSTANCE_ID="$INSTANCE_ID"
$(declare -f log setup_controlplane)
setup_controlplane
EOF
elif [ "$NODE_TYPE" == "worker" ]; then
    /sbin/runuser -l ubuntu << EOF
export REGION="$REGION"
export K8S_VERSION="$K8S_VERSION"
export CLUSTER_NAME="$CLUSTER_NAME"
export AWS_LB_ROLE_ARN="$AWS_LB_ROLE_ARN"
export INSTANCE_ID="$INSTANCE_ID"
export GRAFANA_PASSWD="$GRAFANA_PASSWD"
export CERT_ARN="$CERT_ARN"
export DOMAIN="$DOMAIN"
export DNS_ROLE_ARN="$DNS_ROLE_ARN"
$(declare -f log setup_worker)
setup_worker
EOF
else
    log "Error: Invalid node type specified. Must be 'controlplane' or 'worker'"
    exit 1
fi