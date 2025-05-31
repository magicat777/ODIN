#!/bin/bash
# ODIN Kubernetes Quick Start Script

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check for nvidia-smi
    if ! command -v nvidia-smi &> /dev/null; then
        log_error "nvidia-smi not found. Please install NVIDIA drivers."
        exit 1
    fi
    
    # Check for kubectl
    if ! command -v kubectl &> /dev/null; then
        log_warn "kubectl not found. Installing k3s will provide kubectl."
    fi
    
    # Check for helm
    if ! command -v helm &> /dev/null; then
        log_warn "helm not found. Please install Helm 3.x"
        log_info "Visit: https://helm.sh/docs/intro/install/"
    fi
    
    log_info "Prerequisites check completed."
}

install_k3s() {
    log_info "Installing K3s..."
    
    if command -v k3s &> /dev/null; then
        log_warn "K3s is already installed. Skipping..."
        return
    fi
    
    curl -sfL https://get.k3s.io | sh -s - \
        --write-kubeconfig-mode 644 \
        --disable traefik \
        --disable servicelb
    
    # Setup kubeconfig
    mkdir -p ~/.kube
    sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
    sudo chown $USER:$USER ~/.kube/config
    
    log_info "K3s installed successfully."
}

install_nvidia_runtime() {
    log_info "Installing NVIDIA Container Runtime..."
    
    distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
    curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
    curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | \
        sudo tee /etc/apt/sources.list.d/nvidia-docker.list
    
    sudo apt update
    sudo apt install -y nvidia-container-toolkit
    
    # Configure for K3s
    sudo nvidia-ctk runtime configure --runtime=containerd
    sudo systemctl restart k3s
    
    log_info "NVIDIA runtime configured."
}

deploy_nvidia_device_plugin() {
    log_info "Deploying NVIDIA device plugin..."
    
    kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.0/nvidia-device-plugin.yml
    
    # Wait for device plugin to be ready
    kubectl wait --for=condition=ready pod -l name=nvidia-device-plugin-ds -n kube-system --timeout=60s
    
    log_info "NVIDIA device plugin deployed."
}

create_monitoring_namespace() {
    log_info "Creating monitoring namespace..."
    
    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
    
    log_info "Monitoring namespace created."
}

verify_gpu_access() {
    log_info "Verifying GPU access in Kubernetes..."
    
    # Check if GPU is available
    gpu_count=$(kubectl get nodes -o json | jq '[.items[].status.capacity."nvidia.com/gpu" // 0] | add')
    
    if [ "$gpu_count" -eq "0" ]; then
        log_error "No GPUs detected in Kubernetes cluster!"
        exit 1
    fi
    
    log_info "Found $gpu_count GPU(s) in cluster."
    
    # Test GPU access
    kubectl run gpu-test --rm -i --restart=Never --image=nvidia/cuda:11.8.0-base-ubuntu22.04 -- nvidia-smi
    
    log_info "GPU access verified."
}

setup_storage() {
    log_info "Setting up storage..."
    
    # Create directory for persistent volumes
    sudo mkdir -p /var/lib/odin/{prometheus,grafana,loki,alertmanager}
    sudo chown -R $USER:$USER /var/lib/odin
    
    log_info "Storage directories created."
}

print_next_steps() {
    echo ""
    log_info "=== ODIN Quick Start Completed ==="
    echo ""
    echo "Next steps:"
    echo "1. Verify cluster status: kubectl get nodes"
    echo "2. Check GPU availability: kubectl describe nodes | grep nvidia"
    echo "3. Deploy Phase 1: cd /home/magicat777/projects/ODIN && make deploy-phase1"
    echo "4. Monitor progress: watch kubectl get pods -n monitoring"
    echo ""
    echo "Documentation:"
    echo "- Phase 1 Plan: docs/PHASE1_PLAN.md"
    echo "- Deployment Strategy: DEPLOYMENT_STRATEGY.md"
    echo "- Issue Tracker: issues/ISSUE_TRACKER.md"
    echo ""
}

main() {
    log_info "Starting ODIN Kubernetes Quick Start..."
    
    check_prerequisites
    install_k3s
    install_nvidia_runtime
    deploy_nvidia_device_plugin
    create_monitoring_namespace
    verify_gpu_access
    setup_storage
    print_next_steps
    
    log_info "Quick start completed successfully!"
}

# Run main function
main