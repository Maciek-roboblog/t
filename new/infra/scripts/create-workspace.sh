#!/bin/bash
# Skrypt do tworzenia nowego workspace'u
# Użycie: ./create-workspace.sh <workspace-name> [environment]

set -euo pipefail

WORKSPACE_NAME=${1:-}
ENVIRONMENT=${2:-dev}

if [[ -z "$WORKSPACE_NAME" ]]; then
    echo "Użycie: $0 <workspace-name> [environment]"
    echo "  workspace-name: nazwa workspace'u (np. team-gamma)"
    echo "  environment: dev lub prod (domyślnie: dev)"
    exit 1
fi

NAMESPACE="llm-workspace-${WORKSPACE_NAME}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
OVERLAY_DIR="${INFRA_DIR}/k8s/overlays/${WORKSPACE_NAME}"

echo "=== Tworzenie workspace'u: ${WORKSPACE_NAME} ==="
echo "Environment: ${ENVIRONMENT}"
echo "Namespace: ${NAMESPACE}"

# 1. Sprawdź czy overlay już istnieje
if [[ -d "$OVERLAY_DIR" ]]; then
    echo "UWAGA: Overlay już istnieje: ${OVERLAY_DIR}"
    read -p "Czy chcesz kontynuować? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# 2. Utwórz katalog overlay
echo "[1/5] Tworzenie katalogu overlay..."
mkdir -p "$OVERLAY_DIR"

# 3. Generuj kustomization.yaml
echo "[2/5] Generowanie kustomization.yaml..."
cat > "${OVERLAY_DIR}/kustomization.yaml" << EOF
# Kustomization - ${WORKSPACE_NAME} workspace
# Wygenerowano automatycznie: $(date -Iseconds)
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: ${NAMESPACE}

resources:
  - ../../base/workspace-template

patches:
  - target:
      kind: Namespace
      name: llm-workspace-template
    patch: |
      - op: replace
        path: /metadata/name
        value: ${NAMESPACE}
      - op: replace
        path: /metadata/labels/workspace
        value: ${WORKSPACE_NAME}

  - target:
      kind: Secret
      name: mlflow-secret
    patch: |
      - op: replace
        path: /stringData/MLFLOW_TRACKING_URI
        value: "http://mlflow.${NAMESPACE}.svc.cluster.local:5000"

images:
  - name: llama-factory-train
    newName: eu.gcr.io/\${PROJECT_ID}/llama-factory-train
    newTag: v1.0.0
  - name: llama-factory-api
    newName: eu.gcr.io/\${PROJECT_ID}/llama-factory-api
    newTag: v1.0.0

configMapGenerator:
  - name: workspace-config
    behavior: merge
    literals:
      - WORKSPACE_NAME=${WORKSPACE_NAME}
      - MLFLOW_DB_HOST=\${MLFLOW_DB_HOST}

secretGenerator:
  - name: mlflow-db-secret
    behavior: replace
    literals:
      - POSTGRES_USER=mlflow
      - POSTGRES_PASSWORD=CHANGE_ME_${WORKSPACE_NAME^^}_PASSWORD
    type: Opaque

commonLabels:
  workspace: ${WORKSPACE_NAME}
  environment: ${ENVIRONMENT}

commonAnnotations:
  owner: ${WORKSPACE_NAME}@company.com
  created-by: create-workspace.sh
EOF

# 4. Walidacja
echo "[3/5] Walidacja konfiguracji..."
if command -v kustomize &> /dev/null; then
    kustomize build "$OVERLAY_DIR" > /dev/null
    echo "  ✓ Kustomize build OK"
else
    echo "  ⚠ Kustomize nie znaleziony - pominięto walidację"
fi

# 5. Dodaj do Terraform (Workload Identity)
echo "[4/5] Informacja o Terraform..."
echo "  Dodaj '${WORKSPACE_NAME}' do zmiennej workspace_names w:"
echo "  terraform/environments/${ENVIRONMENT}/terraform.tfvars"

# 6. Instrukcje
echo "[5/5] Workspace utworzony!"
echo ""
echo "=== Następne kroki ==="
echo "1. Uzupełnij hasło w: ${OVERLAY_DIR}/kustomization.yaml"
echo "2. Zamień \${PROJECT_ID} i \${MLFLOW_DB_HOST} na właściwe wartości"
echo "3. Dodaj workspace do Terraform: workspace_names = [..., \"${WORKSPACE_NAME}\"]"
echo "4. Uruchom: terraform apply"
echo "5. Deploy: kubectl apply -k ${OVERLAY_DIR}"
echo ""
echo "Lub użyj: ./deploy-workspace.sh ${WORKSPACE_NAME}"
