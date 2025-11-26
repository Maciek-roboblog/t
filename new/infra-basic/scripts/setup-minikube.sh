#!/bin/bash
# Setup minikube z obsługą GPU (NVIDIA)
#
# WYMAGANIA:
# - Ubuntu 22.04+ / Debian 12+
# - NVIDIA Driver 535+
# - Docker z NVIDIA Container Toolkit
# - sudo access
#
# ŹRÓDŁO: https://minikube.sigs.k8s.io/docs/tutorials/nvidia/

set -e

echo "=== Minikube + GPU Setup ==="

# Kolory
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Parametry
MINIKUBE_CPUS="${MINIKUBE_CPUS:-4}"
MINIKUBE_MEMORY="${MINIKUBE_MEMORY:-16384}"  # 16GB
MINIKUBE_DISK="${MINIKUBE_DISK:-100g}"

# Sprawdzenie wymagań
check_requirements() {
    info "Sprawdzanie wymagań..."

    # NVIDIA Driver
    if ! nvidia-smi &>/dev/null; then
        error "NVIDIA driver nie jest zainstalowany"
    fi

    # Docker
    if ! docker info &>/dev/null; then
        error "Docker nie jest zainstalowany lub nie działa"
    fi

    # NVIDIA Container Toolkit dla Docker
    if ! docker run --rm --gpus all nvidia/cuda:12.0-base nvidia-smi &>/dev/null; then
        warn "Docker GPU support nie działa"
        echo "Instaluję NVIDIA Container Toolkit..."
        install_nvidia_toolkit_docker
    fi

    info "GPU wykryte:"
    nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
}

# Instalacja NVIDIA Container Toolkit dla Docker
install_nvidia_toolkit_docker() {
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
        sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

    sudo apt-get update
    sudo apt-get install -y nvidia-container-toolkit
    sudo nvidia-ctk runtime configure --runtime=docker
    sudo systemctl restart docker
}

# Instalacja minikube
install_minikube() {
    info "Instalacja minikube..."

    if command -v minikube &>/dev/null; then
        warn "Minikube już zainstalowany"
    else
        curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
        sudo install minikube-linux-amd64 /usr/local/bin/minikube
        rm minikube-linux-amd64
    fi

    # kubectl
    if ! command -v kubectl &>/dev/null; then
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        sudo install kubectl /usr/local/bin/kubectl
        rm kubectl
    fi

    info "Minikube zainstalowany"
}

# Start minikube z GPU
start_minikube() {
    info "Uruchamianie minikube z GPU..."

    # Zatrzymaj istniejący klaster jeśli istnieje
    minikube status &>/dev/null && minikube stop || true

    # Start z GPU
    minikube start \
        --driver=docker \
        --gpus=all \
        --cpus=${MINIKUBE_CPUS} \
        --memory=${MINIKUBE_MEMORY} \
        --disk-size=${MINIKUBE_DISK} \
        --addons=ingress \
        --addons=metrics-server

    info "Minikube uruchomiony"
}

# Instalacja GPU device plugin
install_gpu_plugin() {
    info "Instalacja NVIDIA GPU device plugin..."

    # Oficjalny device plugin
    kubectl create -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.3/nvidia-device-plugin.yml

    # Poczekaj na uruchomienie
    kubectl rollout status daemonset/nvidia-device-plugin-daemonset -n kube-system --timeout=120s

    info "GPU device plugin zainstalowany"
}

# Konfiguracja time-slicing (opcjonalne)
configure_timeslicing() {
    info "Konfiguracja GPU time-slicing..."

    # Dla minikube używamy ConfigMap device plugin
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: nvidia-plugin-config
  namespace: kube-system
data:
  config.json: |
    {
      "version": "v1",
      "sharing": {
        "timeSlicing": {
          "resources": [
            {
              "name": "nvidia.com/gpu",
              "replicas": 2
            }
          ]
        }
      }
    }
EOF

    # Restart device plugin
    kubectl rollout restart daemonset/nvidia-device-plugin-daemonset -n kube-system

    info "Time-slicing skonfigurowany"
}

# Mount storage
setup_storage() {
    info "Konfiguracja storage..."

    # Tworzenie katalogu na hoście
    mkdir -p ~/llm-storage/{models,output,data,mlflow}

    # Mount do minikube
    minikube mount ~/llm-storage:/data/llm-storage &
    MOUNT_PID=$!
    echo $MOUNT_PID > /tmp/minikube-mount.pid

    info "Storage zamontowany (PID: $MOUNT_PID)"
    warn "Mount działa w tle. Zatrzymaj: kill \$(cat /tmp/minikube-mount.pid)"
}

# Weryfikacja
verify_setup() {
    info "Weryfikacja setup..."

    echo ""
    echo "=== Status klastra ==="
    kubectl get nodes -o wide

    echo ""
    echo "=== GPU w klastrze ==="
    kubectl get nodes -o jsonpath='{.items[*].status.allocatable}' 2>/dev/null | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(f'GPU: {d.get(\"nvidia.com/gpu\", \"N/A\")}')" || \
        kubectl describe nodes | grep -E "nvidia.com/gpu|Allocatable:" | head -5

    echo ""
    echo "=== Device Plugin ==="
    kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds

    echo ""
    info "Setup zakończony!"
    echo ""
    echo "Następne kroki:"
    echo "  1. Pobierz model do ~/llm-storage/models/base-model"
    echo "  2. Deploy: ./scripts/deploy.sh all"
    echo "  3. WebUI:  ./scripts/ui.sh webui"
    echo ""
    warn "Pamiętaj o mount: minikube mount ~/llm-storage:/data/llm-storage"
}

# Main
main() {
    check_requirements
    install_minikube
    start_minikube
    install_gpu_plugin
    configure_timeslicing
    setup_storage
    verify_setup
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
