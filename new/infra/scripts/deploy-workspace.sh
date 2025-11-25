#!/bin/bash
# Skrypt do wdrażania workspace'u
# Użycie: ./deploy-workspace.sh <workspace-name>

set -euo pipefail

WORKSPACE_NAME=${1:-}

if [[ -z "$WORKSPACE_NAME" ]]; then
    echo "Użycie: $0 <workspace-name>"
    exit 1
fi

NAMESPACE="llm-workspace-${WORKSPACE_NAME}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
OVERLAY_DIR="${INFRA_DIR}/k8s/overlays/${WORKSPACE_NAME}"

echo "=== Wdrażanie workspace'u: ${WORKSPACE_NAME} ==="

# Sprawdź czy overlay istnieje
if [[ ! -d "$OVERLAY_DIR" ]]; then
    echo "BŁĄD: Overlay nie istnieje: ${OVERLAY_DIR}"
    echo "Najpierw utwórz workspace: ./create-workspace.sh ${WORKSPACE_NAME}"
    exit 1
fi

# Sprawdź połączenie z klastrem
echo "[1/4] Sprawdzanie połączenia z klastrem..."
kubectl cluster-info > /dev/null || {
    echo "BŁĄD: Brak połączenia z klastrem Kubernetes"
    exit 1
}

# Dry-run
echo "[2/4] Walidacja (dry-run)..."
kubectl apply -k "$OVERLAY_DIR" --dry-run=client

# Potwierdzenie
echo ""
read -p "Czy wdrożyć powyższe zasoby? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Anulowano."
    exit 1
fi

# Deploy
echo "[3/4] Wdrażanie..."
kubectl apply -k "$OVERLAY_DIR"

# Weryfikacja
echo "[4/4] Weryfikacja..."
echo ""
echo "Oczekiwanie na pody..."
sleep 5

kubectl -n "$NAMESPACE" get pods

echo ""
echo "=== Wdrożenie zakończone ==="
echo ""
echo "Przydatne komendy:"
echo "  kubectl -n ${NAMESPACE} get pods"
echo "  kubectl -n ${NAMESPACE} logs -l app=mlflow"
echo "  kubectl -n ${NAMESPACE} port-forward svc/llama-factory-webui 7860:7860"
