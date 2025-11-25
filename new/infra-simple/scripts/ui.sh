#!/bin/bash
# Port-forward do UI
# Użycie: ./ui.sh [webui|inference|mlflow]

set -e

SERVICE=${1:-webui}

echo "=========================================="
echo "  Port Forward"
echo "=========================================="

case "$SERVICE" in
    webui)
        echo "LLaMA-Factory WebUI -> http://localhost:7860"
        echo "Naciśnij Ctrl+C aby zakończyć"
        echo ""
        kubectl -n llm-training port-forward svc/llama-webui 7860:7860
        ;;
    inference)
        echo "vLLM API -> http://localhost:8000"
        echo "Naciśnij Ctrl+C aby zakończyć"
        echo ""
        kubectl -n llm-training port-forward svc/vllm-inference 8000:8000
        ;;
    mlflow)
        echo "MLFlow -> http://localhost:5000"
        echo "Naciśnij Ctrl+C aby zakończyć"
        echo ""
        # Zakładamy że MLFlow jest w namespace mlflow
        kubectl -n mlflow port-forward svc/mlflow 5000:5000 2>/dev/null || \
        kubectl -n llm-training port-forward svc/mlflow 5000:5000 2>/dev/null || \
        echo "BŁĄD: Nie znaleziono MLFlow service"
        ;;
    *)
        echo "Użycie: $0 [webui|inference|mlflow]"
        exit 1
        ;;
esac
