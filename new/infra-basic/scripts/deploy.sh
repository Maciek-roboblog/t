#!/bin/bash
# Deploy LLaMA-Factory + vLLM do k3s/minikube
#
# UŻYCIE:
#   ./scripts/deploy.sh all      # Deploy wszystkiego
#   ./scripts/deploy.sh base     # Tylko namespace, storage, config
#   ./scripts/deploy.sh webui    # Tylko WebUI
#   ./scripts/deploy.sh vllm     # Tylko vLLM
#   ./scripts/deploy.sh mlflow   # Tylko MLflow (opcjonalne)
#   ./scripts/deploy.sh status   # Pokaż status
#   ./scripts/deploy.sh delete   # Usuń wszystko

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="${SCRIPT_DIR}/../k8s"
NAMESPACE="llm-basic"

# Kolory
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Deploy base (namespace, storage, config)
deploy_base() {
    info "Deploying base resources..."

    kubectl apply -f "${K8S_DIR}/01-namespace.yaml"
    kubectl apply -f "${K8S_DIR}/02-storage.yaml"
    kubectl apply -f "${K8S_DIR}/03-configmap.yaml"

    info "Base resources deployed"
}

# Deploy WebUI
deploy_webui() {
    info "Deploying LLaMA-Factory WebUI..."

    kubectl apply -f "${K8S_DIR}/04-llama-webui.yaml"

    # Poczekaj na deployment
    kubectl rollout status deployment/llama-webui -n ${NAMESPACE} --timeout=300s || \
        warn "WebUI może potrzebować więcej czasu na uruchomienie (pobieranie obrazu)"

    info "WebUI deployed"
}

# Deploy vLLM
deploy_vllm() {
    info "Deploying vLLM..."

    # Sprawdź czy model istnieje
    if ! kubectl exec -n ${NAMESPACE} deploy/llama-webui -- ls /storage/models/merged-model 2>/dev/null; then
        warn "Model /storage/models/merged-model nie istnieje"
        warn "vLLM będzie czekał na model. Najpierw przeprowadź trening i merge."
    fi

    kubectl apply -f "${K8S_DIR}/05-vllm.yaml"

    info "vLLM deployed (może wymagać modelu w /storage/models/merged-model)"
}

# Deploy MLflow (opcjonalne)
deploy_mlflow() {
    info "Deploying MLflow..."

    kubectl apply -f "${K8S_DIR}/optional/mlflow.yaml"

    kubectl rollout status deployment/mlflow -n ${NAMESPACE} --timeout=120s

    info "MLflow deployed"
}

# Deploy all
deploy_all() {
    info "Deploying all resources..."

    deploy_base
    deploy_webui

    echo ""
    warn "vLLM NIE jest deployowany automatycznie."
    warn "Przeprowadź najpierw trening w WebUI, potem merge, a następnie:"
    echo "  ./scripts/deploy.sh vllm"
}

# Status
show_status() {
    echo ""
    echo "=== Namespace ==="
    kubectl get ns ${NAMESPACE} 2>/dev/null || echo "Namespace nie istnieje"

    echo ""
    echo "=== Pods ==="
    kubectl get pods -n ${NAMESPACE} -o wide 2>/dev/null || echo "Brak podów"

    echo ""
    echo "=== Services ==="
    kubectl get svc -n ${NAMESPACE} 2>/dev/null || echo "Brak serwisów"

    echo ""
    echo "=== PVC ==="
    kubectl get pvc -n ${NAMESPACE} 2>/dev/null || echo "Brak PVC"

    echo ""
    echo "=== GPU Usage ==="
    kubectl exec -n ${NAMESPACE} deploy/llama-webui -- nvidia-smi 2>/dev/null || \
        echo "WebUI nie działa lub brak GPU"

    echo ""
    echo "=== Access ==="
    echo "WebUI:  ./scripts/ui.sh webui   → http://localhost:7860"
    echo "vLLM:   ./scripts/ui.sh vllm    → http://localhost:8000"
    echo "MLflow: ./scripts/ui.sh mlflow  → http://localhost:5000"
}

# Delete all
delete_all() {
    warn "Usuwanie wszystkich zasobów..."

    read -p "Czy na pewno? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Anulowano"
        exit 0
    fi

    kubectl delete namespace ${NAMESPACE} --ignore-not-found=true
    kubectl delete pv llm-storage-pv --ignore-not-found=true

    info "Wszystkie zasoby usunięte"
}

# Main
case "${1:-}" in
    all)
        deploy_all
        ;;
    base)
        deploy_base
        ;;
    webui)
        deploy_webui
        ;;
    vllm)
        deploy_vllm
        ;;
    mlflow)
        deploy_mlflow
        ;;
    status)
        show_status
        ;;
    delete)
        delete_all
        ;;
    *)
        echo "Usage: $0 {all|base|webui|vllm|mlflow|status|delete}"
        echo ""
        echo "Commands:"
        echo "  all     - Deploy namespace, storage, config, WebUI"
        echo "  base    - Deploy only namespace, storage, config"
        echo "  webui   - Deploy only LLaMA-Factory WebUI"
        echo "  vllm    - Deploy only vLLM (requires trained model)"
        echo "  mlflow  - Deploy MLflow (optional)"
        echo "  status  - Show deployment status"
        echo "  delete  - Delete all resources"
        exit 1
        ;;
esac
