#!/bin/bash
# Skrypt do port-forward dla UI
# Użycie: ./port-forward.sh <service> [workspace]

set -euo pipefail

SERVICE=${1:-}
WORKSPACE=${2:-}

usage() {
    echo "Użycie: $0 <service> [workspace]"
    echo ""
    echo "Serwisy:"
    echo "  webui      - LLaMA-Factory WebUI (wymaga workspace)"
    echo "  streamlit  - Konsola Streamlit (llm-shared)"
    echo "  mlflow     - MLFlow (wymaga workspace lub 'common')"
    echo ""
    echo "Przykłady:"
    echo "  $0 webui team-alpha"
    echo "  $0 streamlit"
    echo "  $0 mlflow common"
    echo "  $0 mlflow team-alpha"
}

if [[ -z "$SERVICE" ]]; then
    usage
    exit 1
fi

case "$SERVICE" in
    webui)
        if [[ -z "$WORKSPACE" ]]; then
            echo "BŁĄD: webui wymaga nazwy workspace'u"
            usage
            exit 1
        fi
        NAMESPACE="llm-workspace-${WORKSPACE}"
        SVC="llama-factory-webui"
        LOCAL_PORT=7860
        REMOTE_PORT=7860
        ;;
    streamlit)
        NAMESPACE="llm-shared"
        SVC="prompt-console"
        LOCAL_PORT=8501
        REMOTE_PORT=80
        ;;
    mlflow)
        if [[ -z "$WORKSPACE" ]]; then
            echo "BŁĄD: mlflow wymaga nazwy workspace'u lub 'common'"
            usage
            exit 1
        fi
        if [[ "$WORKSPACE" == "common" ]]; then
            NAMESPACE="llm-shared"
            SVC="mlflow-common"
        else
            NAMESPACE="llm-workspace-${WORKSPACE}"
            SVC="mlflow"
        fi
        LOCAL_PORT=5000
        REMOTE_PORT=5000
        ;;
    *)
        echo "BŁĄD: Nieznany serwis: $SERVICE"
        usage
        exit 1
        ;;
esac

echo "=== Port Forward ==="
echo "Namespace: ${NAMESPACE}"
echo "Service: ${SVC}"
echo "URL: http://localhost:${LOCAL_PORT}"
echo ""
echo "Naciśnij Ctrl+C aby zakończyć"
echo ""

kubectl -n "$NAMESPACE" port-forward "svc/${SVC}" "${LOCAL_PORT}:${REMOTE_PORT}"
