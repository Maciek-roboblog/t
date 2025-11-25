#!/bin/bash
# Skrypt do weryfikacji wdrożenia
# Użycie: ./verify-deployment.sh [workspace-name]

set -euo pipefail

WORKSPACE_NAME=${1:-}

echo "=== Weryfikacja wdrożenia LLM Platform ==="
echo ""

# Funkcja sprawdzająca namespace
check_namespace() {
    local ns=$1
    local name=$2

    echo "[$name]"

    # Sprawdź pody
    local pods=$(kubectl -n "$ns" get pods --no-headers 2>/dev/null || echo "")
    local running=$(echo "$pods" | grep -c "Running" || echo "0")
    local total=$(echo "$pods" | wc -l | tr -d ' ')

    if [[ -z "$pods" ]]; then
        echo "  ⚠ Namespace nie istnieje lub brak podów"
        return 1
    fi

    echo "  Pody: ${running}/${total} Running"

    # Lista podów z problemami
    local problematic=$(echo "$pods" | grep -v "Running" | grep -v "Completed" || echo "")
    if [[ -n "$problematic" ]]; then
        echo "  ⚠ Pody z problemami:"
        echo "$problematic" | while read line; do
            echo "    - $line"
        done
    fi

    # Sprawdź PVC
    local pvc=$(kubectl -n "$ns" get pvc --no-headers 2>/dev/null | head -1 || echo "")
    if [[ -n "$pvc" ]]; then
        local pvc_status=$(echo "$pvc" | awk '{print $2}')
        echo "  PVC: ${pvc_status}"
    fi

    echo ""
}

# Sprawdź llm-shared
check_namespace "llm-shared" "Namespace: llm-shared (wspólne)"

# Sprawdź workspace jeśli podany
if [[ -n "$WORKSPACE_NAME" ]]; then
    check_namespace "llm-workspace-${WORKSPACE_NAME}" "Namespace: llm-workspace-${WORKSPACE_NAME}"
else
    # Sprawdź wszystkie workspace'y
    workspaces=$(kubectl get namespaces -l purpose=workspace --no-headers 2>/dev/null | awk '{print $1}' || echo "")

    if [[ -n "$workspaces" ]]; then
        while read ns; do
            ws_name=$(echo "$ns" | sed 's/llm-workspace-//')
            check_namespace "$ns" "Namespace: $ns"
        done <<< "$workspaces"
    else
        echo "Brak workspace'ów"
    fi
fi

# Test MLFlow Common
echo "[Test: MLFlow Common]"
if kubectl -n llm-shared get svc mlflow-common &>/dev/null; then
    # Port-forward w tle
    kubectl -n llm-shared port-forward svc/mlflow-common 15000:5000 &>/dev/null &
    PF_PID=$!
    sleep 2

    health=$(curl -s http://localhost:15000/health 2>/dev/null | grep -o '"status":"[^"]*"' || echo "")
    kill $PF_PID 2>/dev/null || true

    if [[ "$health" == *"OK"* ]]; then
        echo "  ✓ MLFlow Common: OK"
    else
        echo "  ⚠ MLFlow Common: Brak odpowiedzi"
    fi
else
    echo "  ⚠ MLFlow Common: Service nie istnieje"
fi

echo ""
echo "=== Weryfikacja zakończona ==="
