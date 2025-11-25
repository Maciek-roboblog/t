#!/bin/bash
# Budowa obrazu Docker
# Użycie: ./build.sh [tag]
#
# Buduje 1 obraz:
# - llama-factory-train: trening + merge + WebUI + MLflow

set -e

TAG=${1:-latest}
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOCKER_DIR="${SCRIPT_DIR}/../docker"

# Sprawdź PROJECT_ID
if [ -z "$PROJECT_ID" ]; then
    echo "BŁĄD: Ustaw zmienną PROJECT_ID"
    echo "  export PROJECT_ID=your-gcp-project"
    exit 1
fi

REGISTRY="eu.gcr.io/${PROJECT_ID}"

echo "=========================================="
echo "  Budowa obrazu LLaMA-Factory"
echo "=========================================="
echo "Registry: ${REGISTRY}"
echo "Tag: ${TAG}"
echo ""
echo "Obraz:"
echo "  - llama-factory-train (trening + merge + WebUI)"
echo ""
echo "UWAGA: vLLM inference używa zewnętrznego serwera"
echo ""

# Autoryzacja (jeśli GCR)
echo "[1/2] Autoryzacja Docker..."
gcloud auth configure-docker eu.gcr.io --quiet 2>/dev/null || true

# Budowa
echo "[2/2] Budowanie i push..."
echo ""

echo ">>> llama-factory-train (trening + merge + WebUI + MLflow)"
docker build \
    -f "${DOCKER_DIR}/Dockerfile.train" \
    -t "${REGISTRY}/llama-factory-train:${TAG}" \
    "${DOCKER_DIR}"

docker push "${REGISTRY}/llama-factory-train:${TAG}"

echo ""
echo "=========================================="
echo "  GOTOWE!"
echo "=========================================="
echo "Obraz: ${REGISTRY}/llama-factory-train:${TAG}"
echo ""
echo "Inference: użyj zewnętrznego vLLM serwera"
echo "  vLLM czyta modele z NFS: /storage/models/merged-model"
