#!/bin/bash
# Setup k3s z obsługą GPU (NVIDIA)
#
# WYMAGANIA:
# - Ubuntu 22.04+ / Debian 12+
# - NVIDIA Driver 535+
# - sudo access
#
# ŹRÓDŁA:
# - https://docs.k3s.io/advanced
# - https://github.com/UntouchedWagons/K3S-NVidia
# - https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/gpu-sharing.html

set -e

echo "=== K3s + GPU Setup ==="

# Kolory
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Funkcje pomocnicze
info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Sprawdzenie wymagań
check_requirements() {
    info "Sprawdzanie wymagań..."

    # NVIDIA Driver
    if ! nvidia-smi &>/dev/null; then
        error "NVIDIA driver nie jest zainstalowany. Zainstaluj: sudo apt install nvidia-driver-535"
    fi

    # NVIDIA Container Toolkit
    if ! dpkg -l | grep -q nvidia-container-toolkit; then
        warn "NVIDIA Container Toolkit nie jest zainstalowany"
        echo "Instaluję..."
        install_nvidia_toolkit
    fi

    info "GPU wykryte:"
    nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
}

# Instalacja NVIDIA Container Toolkit
install_nvidia_toolkit() {
    info "Instalacja NVIDIA Container Toolkit..."

    # Dodaj repo NVIDIA
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
        sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

    sudo apt-get update
    sudo apt-get install -y nvidia-container-toolkit

    info "NVIDIA Container Toolkit zainstalowany"
}

# Instalacja k3s
install_k3s() {
    info "Instalacja k3s..."

    if command -v k3s &>/dev/null; then
        warn "k3s już zainstalowany, pomijam..."
        return
    fi

    # Instalacja k3s
    curl -sfL https://get.k3s.io | sh -s - \
        --write-kubeconfig-mode 644

    # Poczekaj na k3s
    sleep 10

    # Konfiguracja kubectl
    mkdir -p ~/.kube
    sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
    sudo chown $(id -u):$(id -g) ~/.kube/config

    info "k3s zainstalowany"
}

# Konfiguracja containerd dla NVIDIA
configure_containerd() {
    info "Konfiguracja containerd dla GPU..."

    # K3s używa własnego containerd
    sudo nvidia-ctk runtime configure --runtime=containerd \
        --config=/var/lib/rancher/k3s/agent/etc/containerd/config.toml

    # Restart k3s
    sudo systemctl restart k3s

    sleep 10
    info "Containerd skonfigurowany"
}

# Instalacja GPU Operator
install_gpu_operator() {
    info "Instalacja NVIDIA GPU Operator..."

    # Helm
    if ! command -v helm &>/dev/null; then
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    fi

    # Dodaj repo
    helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
    helm repo update

    # Instaluj GPU Operator
    # Dla k3s używamy containerd
    helm install gpu-operator nvidia/gpu-operator \
        --namespace gpu-operator \
        --create-namespace \
        --set driver.enabled=false \
        --set toolkit.enabled=false \
        --set operator.defaultRuntime=containerd \
        --set toolkit.env[0].name=CONTAINERD_CONFIG \
        --set toolkit.env[0].value=/var/lib/rancher/k3s/agent/etc/containerd/config.toml \
        --set toolkit.env[1].name=CONTAINERD_SOCKET \
        --set toolkit.env[1].value=/run/k3s/containerd/containerd.sock \
        --set toolkit.env[2].name=CONTAINERD_RUNTIME_CLASS \
        --set toolkit.env[2].value=nvidia

    info "GPU Operator zainstalowany"
}

# Konfiguracja time-slicing
configure_timeslicing() {
    info "Konfiguracja GPU time-slicing..."

    # Poczekaj na GPU Operator
    kubectl wait --for=condition=available deployment/gpu-operator \
        -n gpu-operator --timeout=300s || true

    # Aplikuj konfigurację time-slicing
    kubectl apply -f k8s/00-gpu-timeslice.yaml

    # Patch clusterpolicy
    kubectl patch clusterpolicy/cluster-policy \
        -n gpu-operator \
        --type merge \
        -p '{"spec": {"devicePlugin": {"config": {"name": "time-slicing-config", "default": "any"}}}}'

    info "Time-slicing skonfigurowany (2 logiczne GPU)"
}

# Tworzenie katalogu storage
create_storage() {
    info "Tworzenie katalogu storage..."

    sudo mkdir -p /data/llm-storage/{models,output,data,mlflow}
    sudo chmod -R 777 /data/llm-storage

    info "Storage utworzony: /data/llm-storage"
}

# Weryfikacja
verify_setup() {
    info "Weryfikacja setup..."

    echo ""
    echo "=== Status klastra ==="
    kubectl get nodes -o wide

    echo ""
    echo "=== GPU w klastrze ==="
    kubectl get nodes -o jsonpath='{.items[*].status.allocatable}' | jq . 2>/dev/null || \
        kubectl describe nodes | grep -A 5 "Allocatable:"

    echo ""
    echo "=== GPU Operator ==="
    kubectl get pods -n gpu-operator

    echo ""
    info "Setup zakończony!"
    echo ""
    echo "Następne kroki:"
    echo "  1. Pobierz model do /data/llm-storage/models/base-model"
    echo "  2. Deploy: ./scripts/deploy.sh all"
    echo "  3. WebUI:  ./scripts/ui.sh webui"
}

# Main
main() {
    check_requirements
    install_k3s
    configure_containerd
    install_gpu_operator
    configure_timeslicing
    create_storage
    verify_setup
}

# Uruchom jeśli nie jest źródłem
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
