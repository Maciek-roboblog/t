#!/bin/bash
# Port-forward do serwisów
#
# UŻYCIE:
#   ./scripts/ui.sh webui   # http://localhost:7860
#   ./scripts/ui.sh vllm    # http://localhost:8000
#   ./scripts/ui.sh mlflow  # http://localhost:5000

set -e

NAMESPACE="llm-basic"

# Kolory
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

case "${1:-}" in
    webui)
        info "Port-forward do LLaMA-Factory WebUI..."
        echo "Otwórz: http://localhost:7860"
        echo "Ctrl+C aby zatrzymać"
        echo ""
        kubectl port-forward svc/llama-webui 7860:7860 -n ${NAMESPACE}
        ;;
    vllm)
        info "Port-forward do vLLM API..."
        echo "Otwórz: http://localhost:8000"
        echo "API:    http://localhost:8000/v1/chat/completions"
        echo "Docs:   http://localhost:8000/docs"
        echo "Ctrl+C aby zatrzymać"
        echo ""
        kubectl port-forward svc/vllm 8000:8000 -n ${NAMESPACE}
        ;;
    mlflow)
        info "Port-forward do MLflow..."
        echo "Otwórz: http://localhost:5000"
        echo "Ctrl+C aby zatrzymać"
        echo ""
        kubectl port-forward svc/mlflow 5000:5000 -n ${NAMESPACE}
        ;;
    *)
        echo "Usage: $0 {webui|vllm|mlflow}"
        echo ""
        echo "Services:"
        echo "  webui  - LLaMA-Factory WebUI (port 7860)"
        echo "  vllm   - vLLM API (port 8000)"
        echo "  mlflow - MLflow UI (port 5000)"
        exit 1
        ;;
esac
