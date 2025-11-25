#!/bin/bash
# Budowa obrazów Docker
# Użycie: ./build.sh [tag]

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
echo "  Budowa obrazów LLaMA-Factory"
echo "=========================================="
echo "Registry: ${REGISTRY}"
echo "Tag: ${TAG}"
echo ""

# Autoryzacja (jeśli GCR)
echo "[1/3] Autoryzacja Docker..."
gcloud auth configure-docker eu.gcr.io --quiet 2>/dev/null || true

# Budowa
echo "[2/3] Budowanie obrazów..."
echo ""

echo ">>> llama-factory-train"
docker build \
    -f "${DOCKER_DIR}/Dockerfile.train" \
    -t "${REGISTRY}/llama-factory-train:${TAG}" \
    "${DOCKER_DIR}"

echo ""
echo ">>> llama-factory-api"
docker build \
    -f "${DOCKER_DIR}/Dockerfile.api" \
    -t "${REGISTRY}/llama-factory-api:${TAG}" \
    "${DOCKER_DIR}"

# Push
echo ""
echo "[3/3] Push do registry..."
docker push "${REGISTRY}/llama-factory-train:${TAG}"
docker push "${REGISTRY}/llama-factory-api:${TAG}"

echo ""
echo "=========================================="
echo "  GOTOWE!"
echo "=========================================="
echo "Obrazy:"
echo "  ${REGISTRY}/llama-factory-train:${TAG}"
echo "  ${REGISTRY}/llama-factory-api:${TAG}"
