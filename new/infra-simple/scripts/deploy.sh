#!/bin/bash
# Wdrożenie LLaMA-Factory na Kubernetes
# Użycie: ./deploy.sh [all|base|webui|inference]

set -e

ACTION=${1:-all}
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
K8S_DIR="${SCRIPT_DIR}/../k8s"

# Sprawdź PROJECT_ID
if [ -z "$PROJECT_ID" ]; then
    echo "BŁĄD: Ustaw zmienną PROJECT_ID"
    echo "  export PROJECT_ID=your-gcp-project"
    exit 1
fi

# Zamień placeholder PROJECT_ID w manifestach
echo "Przygotowanie manifestów (PROJECT_ID=${PROJECT_ID})..."
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

cp "${K8S_DIR}"/*.yaml "$TEMP_DIR/"
sed -i "s/PROJECT_ID/${PROJECT_ID}/g" "$TEMP_DIR"/*.yaml

echo ""
echo "=========================================="
echo "  Wdrażanie LLaMA-Factory"
echo "=========================================="

case "$ACTION" in
    all)
        echo "Wdrażam wszystko (base + webui)..."
        kubectl apply -f "$TEMP_DIR/01-namespace.yaml"
        kubectl apply -f "$TEMP_DIR/02-secrets.yaml"
        kubectl apply -f "$TEMP_DIR/03-pvc.yaml"
        kubectl apply -f "$TEMP_DIR/04-configmap.yaml"
        kubectl apply -f "$TEMP_DIR/05-llama-webui.yaml"
        echo ""
        echo "WebUI wdrożone. Inference wdróż osobno po treningu."
        ;;
    base)
        echo "Wdrażam tylko bazę (namespace, secrets, pvc)..."
        kubectl apply -f "$TEMP_DIR/01-namespace.yaml"
        kubectl apply -f "$TEMP_DIR/02-secrets.yaml"
        kubectl apply -f "$TEMP_DIR/03-pvc.yaml"
        kubectl apply -f "$TEMP_DIR/04-configmap.yaml"
        ;;
    webui)
        echo "Wdrażam WebUI..."
        kubectl apply -f "$TEMP_DIR/05-llama-webui.yaml"
        ;;
    inference)
        echo "Wdrażam vLLM inference..."
        kubectl apply -f "$TEMP_DIR/07-vllm-inference.yaml"
        ;;
    *)
        echo "Użycie: $0 [all|base|webui|inference]"
        exit 1
        ;;
esac

echo ""
echo "=========================================="
echo "  Status"
echo "=========================================="
kubectl -n llm-training get pods
