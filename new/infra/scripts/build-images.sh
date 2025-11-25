#!/bin/bash
# Skrypt do budowania i pushowania obrazów Docker
# Użycie: ./build-images.sh [version]

set -euo pipefail

VERSION=${1:-"latest"}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Sprawdź zmienne środowiskowe
if [[ -z "${PROJECT_ID:-}" ]]; then
    echo "BŁĄD: Ustaw zmienną PROJECT_ID"
    echo "  export PROJECT_ID=your-gcp-project"
    exit 1
fi

REGISTRY="eu.gcr.io/${PROJECT_ID}"

echo "=== Budowanie obrazów Docker ==="
echo "Registry: ${REGISTRY}"
echo "Wersja: ${VERSION}"
echo ""

# Autoryzacja Docker
echo "[1/5] Autoryzacja Docker..."
gcloud auth configure-docker eu.gcr.io --quiet

# Utwórz tymczasowy katalog na Dockerfile'e
DOCKER_DIR=$(mktemp -d)
trap "rm -rf $DOCKER_DIR" EXIT

# Dockerfile.train
echo "[2/5] Tworzenie Dockerfile.train..."
cat > "${DOCKER_DIR}/Dockerfile.train" << 'EOF'
FROM debian:12

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    python3.11 python3.11-venv python3-pip \
    build-essential git curl wget ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN ln -sf /usr/bin/python3.11 /usr/bin/python && \
    ln -sf /usr/bin/pip3 /usr/bin/pip

RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir \
      torch==2.2.0 torchvision==0.17.0 torchaudio==2.2.0 \
      --extra-index-url https://download.pytorch.org/whl/cu118 && \
    pip install --no-cache-dir \
      transformers==4.37.0 datasets==2.17.0

RUN pip install --no-cache-dir \
    "llamafactory[torch,metrics]==0.9.3" \
    mlflow==2.10.0

WORKDIR /app
ENTRYPOINT ["/bin/bash"]
EOF

# Dockerfile.api
echo "[3/5] Tworzenie Dockerfile.api..."
cat > "${DOCKER_DIR}/Dockerfile.api" << 'EOF'
FROM debian:12

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    python3.11 python3-pip \
    build-essential git curl ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN ln -sf /usr/bin/python3.11 /usr/bin/python && \
    ln -sf /usr/bin/pip3 /usr/bin/pip

RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir \
      torch==2.2.0 torchvision==0.17.0 \
      --extra-index-url https://download.pytorch.org/whl/cu118 && \
    pip install --no-cache-dir \
      transformers==4.37.0 \
      vllm==0.4.0 \
      "llamafactory[torch]==0.9.3" \
      mlflow==2.10.0

WORKDIR /app
EXPOSE 8000
CMD ["llamafactory-cli", "api", "/app/config/inference.yaml", "infer_backend=vllm", "API_PORT=8000"]
EOF

# Budowa
echo "[4/5] Budowanie obrazów..."
docker build -f "${DOCKER_DIR}/Dockerfile.train" -t "${REGISTRY}/llama-factory-train:${VERSION}" "${DOCKER_DIR}"
docker build -f "${DOCKER_DIR}/Dockerfile.api" -t "${REGISTRY}/llama-factory-api:${VERSION}" "${DOCKER_DIR}"

# Taguj jako latest jeśli nie jest
if [[ "$VERSION" != "latest" ]]; then
    docker tag "${REGISTRY}/llama-factory-train:${VERSION}" "${REGISTRY}/llama-factory-train:latest"
    docker tag "${REGISTRY}/llama-factory-api:${VERSION}" "${REGISTRY}/llama-factory-api:latest"
fi

# Push
echo "[5/5] Pushowanie obrazów..."
docker push "${REGISTRY}/llama-factory-train:${VERSION}"
docker push "${REGISTRY}/llama-factory-api:${VERSION}"

if [[ "$VERSION" != "latest" ]]; then
    docker push "${REGISTRY}/llama-factory-train:latest"
    docker push "${REGISTRY}/llama-factory-api:latest"
fi

echo ""
echo "=== Obrazy zbudowane i opublikowane ==="
echo "  ${REGISTRY}/llama-factory-train:${VERSION}"
echo "  ${REGISTRY}/llama-factory-api:${VERSION}"
