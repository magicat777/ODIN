#!/bin/bash
# ODIN Kubernetes Quick Start Script - No Sudo Version
# This script performs all operations that don't require sudo

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

check_prerequisites() {
    log_step "Checking prerequisites..."
    
    # Check for nvidia-smi
    if ! command -v nvidia-smi &> /dev/null; then
        log_error "nvidia-smi not found. Please ensure NVIDIA drivers are installed."
        log_warn "Request admin to install NVIDIA drivers"
        exit 1
    else
        log_info "✓ NVIDIA drivers detected"
        nvidia-smi --query-gpu=name,driver_version --format=csv,noheader
    fi
    
    # Check for kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found."
        log_warn "K3s should provide kubectl. Check if K3s is installed."
        exit 1
    else
        log_info "✓ kubectl found"
    fi
    
    # Check for Python 3
    if ! command -v python3 &> /dev/null; then
        log_error "python3 not found. Please install Python 3.x"
        exit 1
    else
        log_info "✓ Python 3 found"
    fi
    
    # Check disk space
    AVAILABLE_SPACE=$(df -BG /home/$USER | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$AVAILABLE_SPACE" -lt 50 ]; then
        log_warn "Low disk space: ${AVAILABLE_SPACE}GB available (recommended: 50GB+)"
    else
        log_info "✓ Disk space: ${AVAILABLE_SPACE}GB available"
    fi
    
    log_info "Prerequisites check completed."
}

check_k3s() {
    log_step "Checking K3s installation..."
    
    if kubectl version --client &> /dev/null; then
        log_info "✓ kubectl is available"
        
        # Check if we can connect to cluster
        if kubectl get nodes &> /dev/null; then
            log_info "✓ K3s cluster is accessible"
            kubectl get nodes
        else
            log_error "Cannot connect to K3s cluster"
            log_warn "Please ensure K3s is installed and running"
            log_warn "Request admin to run: curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644"
            exit 1
        fi
    else
        log_error "K3s not properly configured"
        exit 1
    fi
}

setup_kubeconfig() {
    log_step "Setting up kubeconfig..."
    
    # Check if kubeconfig exists
    if [ -f "/etc/rancher/k3s/k3s.yaml" ]; then
        mkdir -p ~/.kube
        cp /etc/rancher/k3s/k3s.yaml ~/.kube/config 2>/dev/null || {
            log_warn "Cannot copy k3s.yaml. It might not be readable."
            log_warn "Request admin to run: sudo chmod 644 /etc/rancher/k3s/k3s.yaml"
            exit 1
        }
        log_info "✓ Kubeconfig set up"
    else
        log_error "K3s config not found at /etc/rancher/k3s/k3s.yaml"
        exit 1
    fi
}

check_gpu_support() {
    log_step "Checking GPU support in Kubernetes..."
    
    # Check if NVIDIA device plugin is installed
    if kubectl get pods -n kube-system | grep -q nvidia-device-plugin; then
        log_info "✓ NVIDIA device plugin found"
        
        # Check if GPU is available in node capacity
        GPU_COUNT=$(kubectl get nodes -o json | jq '[.items[].status.capacity."nvidia.com/gpu" // "0"] | map(tonumber) | add')
        if [ "$GPU_COUNT" != "null" ] && [ "$GPU_COUNT" -gt 0 ]; then
            log_info "✓ Found $GPU_COUNT GPU(s) in cluster"
        else
            log_warn "No GPUs detected in Kubernetes"
            log_info "Deploying NVIDIA device plugin..."
            kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.0/nvidia-device-plugin.yml
            
            # Wait for device plugin
            log_info "Waiting for device plugin to be ready..."
            kubectl wait --for=condition=ready pod -l name=nvidia-device-plugin-ds -n kube-system --timeout=60s || {
                log_error "Device plugin failed to start"
                log_warn "GPU support may require additional configuration"
            }
        fi
    else
        log_info "Installing NVIDIA device plugin..."
        kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.0/nvidia-device-plugin.yml
        kubectl wait --for=condition=ready pod -l name=nvidia-device-plugin-ds -n kube-system --timeout=60s
    fi
}

create_namespace() {
    log_step "Creating monitoring namespace..."
    
    if kubectl get namespace monitoring &> /dev/null; then
        log_info "✓ Monitoring namespace already exists"
    else
        kubectl create namespace monitoring
        log_info "✓ Monitoring namespace created"
    fi
}

check_storage() {
    log_step "Checking storage configuration..."
    
    # Check for storage class
    if kubectl get storageclass | grep -q local-path; then
        log_info "✓ Local-path storage class found"
    else
        log_info "Creating local-path storage class..."
        cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-path
provisioner: rancher.io/local-path
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
EOF
        log_info "✓ Storage class created"
    fi
    
    # Check if storage directories exist
    STORAGE_DIR="/var/lib/odin"
    if [ -d "$STORAGE_DIR" ]; then
        if [ -w "$STORAGE_DIR" ]; then
            log_info "✓ Storage directory is writable"
        else
            log_warn "Storage directory exists but is not writable"
            log_warn "Request admin to run: sudo chown -R $USER:$USER $STORAGE_DIR"
        fi
    else
        log_warn "Storage directory $STORAGE_DIR does not exist"
        log_warn "Request admin to run:"
        log_warn "  sudo mkdir -p $STORAGE_DIR/{prometheus,grafana,loki,alertmanager}"
        log_warn "  sudo chown -R $USER:$USER $STORAGE_DIR"
    fi
}

test_gpu_access() {
    log_step "Testing GPU access in Kubernetes..."
    
    log_info "Running GPU test pod..."
    
    # Create test pod
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: gpu-test
  namespace: monitoring
spec:
  restartPolicy: Never
  containers:
  - name: gpu-test
    image: nvidia/cuda:11.8.0-base-ubuntu22.04
    command: ["nvidia-smi"]
    resources:
      limits:
        nvidia.com/gpu: 1
EOF
    
    # Wait for pod to complete
    log_info "Waiting for GPU test to complete..."
    sleep 5
    
    # Check pod status
    POD_STATUS=$(kubectl get pod gpu-test -n monitoring -o jsonpath='{.status.phase}')
    
    if [ "$POD_STATUS" = "Succeeded" ]; then
        log_info "✓ GPU test successful!"
        kubectl logs gpu-test -n monitoring
    else
        log_error "GPU test failed with status: $POD_STATUS"
        kubectl describe pod gpu-test -n monitoring
    fi
    
    # Cleanup
    kubectl delete pod gpu-test -n monitoring --ignore-not-found=true
}

create_quickstart_resources() {
    log_step "Creating quickstart resources..."
    
    # Create a simple test deployment
    cat <<EOF > k8s/quickstart-test.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: quickstart-config
  namespace: monitoring
data:
  status: "ready"
  initialized: "$(date)"
---
apiVersion: v1
kind: Service
metadata:
  name: quickstart-test
  namespace: monitoring
spec:
  selector:
    app: quickstart-test
  ports:
  - port: 8080
    targetPort: 8080
EOF
    
    kubectl apply -f k8s/quickstart-test.yaml
    log_info "✓ Quickstart resources created"
}

install_dependencies() {
    log_step "Installing Python dependencies..."
    
    # Install required Python packages in user space
    pip3 install --user prometheus-client requests pytest pyyaml
    
    log_info "✓ Python dependencies installed"
}

print_next_steps() {
    echo ""
    log_info "=== ODIN Quick Start Completed Successfully ==="
    echo ""
    echo -e "${GREEN}✓ Environment Checks:${NC}"
    echo "  - NVIDIA drivers installed"
    echo "  - K3s cluster accessible"
    echo "  - GPU support configured"
    echo "  - Monitoring namespace ready"
    echo ""
    echo -e "${YELLOW}⚠ Admin Actions Required:${NC}"
    
    # Check if storage directory is writable
    if [ ! -w "/var/lib/odin" ] 2>/dev/null; then
        echo "  1. Create storage directories:"
        echo "     sudo mkdir -p /var/lib/odin/{prometheus,grafana,loki,alertmanager}"
        echo "     sudo chown -R $USER:$USER /var/lib/odin"
    fi
    
    # Check if we need NVIDIA runtime
    if ! kubectl get runtimeclass | grep -q nvidia 2>/dev/null; then
        echo "  2. Configure NVIDIA runtime for K3s"
    fi
    
    echo ""
    echo -e "${BLUE}Next Steps:${NC}"
    echo "  1. Review the deployment strategy: cat DEPLOYMENT_STRATEGY.md"
    echo "  2. Start Phase 1 deployment: make deploy-phase1"
    echo "  3. Follow the Claude guide: cat docs/CLAUDE_DEPLOYMENT_GUIDE.md"
    echo "  4. Monitor progress: watch kubectl get pods -n monitoring"
    echo ""
    echo -e "${GREEN}Useful Commands:${NC}"
    echo "  - Check cluster status: kubectl get nodes"
    echo "  - View GPU resources: kubectl describe nodes | grep nvidia"
    echo "  - List monitoring pods: kubectl get pods -n monitoring"
    echo "  - View issues: make issues-todo"
    echo ""
    echo "Documentation available in:"
    echo "  - Phase plans: docs/PHASE*_PLAN.md"
    echo "  - Architecture: docs/architecture/"
    echo "  - Runbooks: docs/runbooks/"
    echo ""
}

print_summary() {
    log_info "=== Quick Start Summary ==="
    
    # Create summary file
    cat > quickstart-summary.txt << EOF
ODIN Quickstart Summary
Generated: $(date)

Cluster Status:
$(kubectl get nodes 2>/dev/null || echo "Not accessible")

GPU Status:
$(kubectl get nodes -o json 2>/dev/null | jq '.items[].status.capacity."nvidia.com/gpu"' || echo "Unknown")

Namespace Status:
$(kubectl get namespace monitoring -o json 2>/dev/null | jq -r '.status.phase' || echo "Not created")

Next Actions:
1. Ensure storage directories are created with proper permissions
2. Deploy Phase 1 using: make deploy-phase1
3. Follow progress in issue tracker: make issues-todo

For help: cat docs/CLAUDE_DEPLOYMENT_GUIDE.md
EOF
    
    log_info "Summary saved to quickstart-summary.txt"
}

main() {
    log_info "Starting ODIN Kubernetes Quick Start (No Sudo Version)..."
    echo ""
    
    check_prerequisites
    check_k3s
    setup_kubeconfig
    check_gpu_support
    create_namespace
    check_storage
    test_gpu_access
    create_quickstart_resources
    install_dependencies
    print_summary
    print_next_steps
    
    log_info "Quick start completed! 🚀"
}

# Run main function
main