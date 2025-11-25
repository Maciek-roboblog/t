#!/bin/bash
# Status wdrożenia
# Użycie: ./status.sh

echo "=========================================="
echo "  Status LLaMA-Factory"
echo "=========================================="
echo ""

echo ">>> Pods"
kubectl -n llm-training get pods -o wide 2>/dev/null || echo "Namespace nie istnieje"
echo ""

echo ">>> Services"
kubectl -n llm-training get svc 2>/dev/null || true
echo ""

echo ">>> Jobs"
kubectl -n llm-training get jobs 2>/dev/null || true
echo ""

echo ">>> PVC"
kubectl -n llm-training get pvc 2>/dev/null || true
echo ""

echo ">>> GPU Nodes"
kubectl get nodes -l "cloud.google.com/gke-accelerator" 2>/dev/null || \
kubectl get nodes -l "nvidia.com/gpu" 2>/dev/null || \
echo "Brak GPU nodes lub inne labele"
