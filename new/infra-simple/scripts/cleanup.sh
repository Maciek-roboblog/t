#!/bin/bash
# Czyszczenie zasobów
# Użycie: ./cleanup.sh [all|jobs|inference]

set -e

ACTION=${1:-jobs}

echo "=========================================="
echo "  Cleanup"
echo "=========================================="

case "$ACTION" in
    all)
        echo "UWAGA: Usuniesz WSZYSTKIE zasoby w namespace llm-training!"
        read -p "Kontynuować? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            kubectl delete namespace llm-training
            echo "Namespace usunięty"
        fi
        ;;
    jobs)
        echo "Usuwam zakończone joby..."
        kubectl -n llm-training delete jobs --field-selector status.successful=1 2>/dev/null || true
        kubectl -n llm-training delete jobs --field-selector status.failed=1 2>/dev/null || true
        echo "Gotowe"
        ;;
    inference)
        echo "Usuwam vLLM inference..."
        kubectl -n llm-training delete deployment vllm-inference 2>/dev/null || true
        kubectl -n llm-training delete svc vllm-inference 2>/dev/null || true
        echo "Gotowe"
        ;;
    *)
        echo "Użycie: $0 [all|jobs|inference]"
        exit 1
        ;;
esac
