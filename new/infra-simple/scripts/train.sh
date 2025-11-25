#!/bin/bash
# Uruchomienie treningu
# Użycie: ./train.sh [job-name]

set -e

JOB_NAME=${1:-llama-train-$(date +%Y%m%d-%H%M%S)}
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
K8S_DIR="${SCRIPT_DIR}/../k8s"

# Sprawdź PROJECT_ID
if [ -z "$PROJECT_ID" ]; then
    echo "BŁĄD: Ustaw zmienną PROJECT_ID"
    exit 1
fi

echo "=========================================="
echo "  Uruchamianie treningu"
echo "=========================================="
echo "Job: ${JOB_NAME}"
echo ""

# Przygotuj manifest z unikalną nazwą
TEMP_FILE=$(mktemp)
trap "rm -f $TEMP_FILE" EXIT

sed "s/PROJECT_ID/${PROJECT_ID}/g" "${K8S_DIR}/06-training-job.yaml" | \
sed "s/name: llama-train/name: ${JOB_NAME}/g" > "$TEMP_FILE"

# Uruchom job
kubectl apply -f "$TEMP_FILE"

echo ""
echo "Job uruchomiony. Śledź postęp:"
echo "  kubectl -n llm-training logs -f job/${JOB_NAME}"
echo ""
echo "Sprawdź status:"
echo "  kubectl -n llm-training get jobs"
