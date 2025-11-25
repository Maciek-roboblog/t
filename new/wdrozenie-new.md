# Przewodnik wdrożeniowy: Platforma LLM Fine-tuning

## Spis treści

1. [Prerekvizity](#1-prerekvizity)
2. [Faza 1: Przygotowanie infrastruktury](#2-faza-1-przygotowanie-infrastruktury)
3. [Faza 2: Wdrożenie warstwy wspólnej](#3-faza-2-wdrożenie-warstwy-wspólnej)
4. [Faza 3: Wdrożenie workspace'u](#4-faza-3-wdrożenie-workspaceu)
5. [Faza 4: Konfiguracja CI/CD](#5-faza-4-konfiguracja-cicd)
6. [Weryfikacja wdrożenia](#6-weryfikacja-wdrożenia)
7. [Operacje dzień-2](#7-operacje-dzień-2)
8. [Troubleshooting](#8-troubleshooting)

---

## 1. Prerekvizity

### 1.1. Wymagania infrastrukturalne

```plantuml
@startuml
!theme plain
skinparam defaultTextAlignment center

rectangle "Wymagania" {
  rectangle "GKE Cluster" #LightBlue {
    (GPU Node Pool\nA100 x min. 2)
    (Standard Node Pool\nx min. 3)
  }

  rectangle "GCP Services" #LightGreen {
    (Artifact Registry)
    (Cloud Storage)
    (Cloud SQL\nPostgreSQL)
  }

  rectangle "Narzędzia" #LightYellow {
    (kubectl)
    (gcloud)
    (helm)
    (docker)
  }
}

@enduml
```

#### Checklist prerekvizytów

- [ ] Klaster GKE z GPU node pool (A100 lub L4)
- [ ] NVIDIA GPU Operator zainstalowany
- [ ] Artifact Registry skonfigurowany
- [ ] Cloud SQL (PostgreSQL) dla MLFlow
- [ ] GCS bucket dla artefaktów MLFlow
- [ ] Dostęp `kubectl` do klastra
- [ ] Uprawnienia do tworzenia namespace'ów i Workload Identity

### 1.2. Weryfikacja klastra

```bash
# Sprawdź dostęp do klastra
kubectl cluster-info

# Sprawdź GPU nodes
kubectl get nodes -l cloud.google.com/gke-accelerator=nvidia-tesla-a100

# Sprawdź NVIDIA device plugin
kubectl get pods -n kube-system | grep nvidia

# Oczekiwany output: nvidia-gpu-device-plugin-* Running
```

### 1.3. Zmienne środowiskowe

Utwórz plik `env.sh` z konfiguracją:

```bash
#!/bin/bash

# GCP
export PROJECT_ID="your-gcp-project"
export REGION="europe-west4"
export ZONE="europe-west4-a"

# Registry
export REGISTRY="eu.gcr.io/${PROJECT_ID}"

# Nazwy obrazów
export TRAIN_IMAGE="${REGISTRY}/llama-factory-train:v1.0.0"
export API_IMAGE="${REGISTRY}/llama-factory-api:v1.0.0"
export CONSOLE_IMAGE="${REGISTRY}/prompt-console:v1.0.0"

# MLFlow
export MLFLOW_DB_HOST="10.0.0.5"  # Cloud SQL private IP
export MLFLOW_DB_NAME="mlflow"
export MLFLOW_BUCKET="gs://${PROJECT_ID}-mlflow"

# Workspace do wdrożenia
export WORKSPACE_NAME="team-alpha"
export NAMESPACE="llm-workspace-${WORKSPACE_NAME}"
```

```bash
source env.sh
```

---

## 2. Faza 1: Przygotowanie infrastruktury

### 2.1. Diagram procesu

```plantuml
@startuml
!theme plain
|Operator|
start
:Budowa obrazów Docker;
:Push do Artifact Registry;
:Utworzenie namespace'ów;
:Konfiguracja Workload Identity;
:Utworzenie GCS buckets;
stop
@enduml
```

### 2.2. Krok 1: Budowa obrazów Docker

#### Dockerfile treningowy (`Dockerfile.train`)

```dockerfile
FROM debian:12

ENV DEBIAN_FRONTEND=noninteractive

# System + Python 3.11
RUN apt-get update && apt-get install -y \
    python3.11 python3.11-venv python3-pip \
    build-essential git curl wget ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN ln -sf /usr/bin/python3.11 /usr/bin/python && \
    ln -sf /usr/bin/pip3 /usr/bin/pip

# PyTorch + CUDA 11.8
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir \
      torch==2.2.0 torchvision==0.17.0 torchaudio==2.2.0 \
      --extra-index-url https://download.pytorch.org/whl/cu118 && \
    pip install --no-cache-dir \
      transformers==4.37.0 datasets==2.17.0

# LLaMA-Factory + MLFlow
RUN pip install --no-cache-dir \
    "llamafactory[torch,metrics]==0.9.3" \
    mlflow==2.10.0

WORKDIR /app
ENTRYPOINT ["/bin/bash"]
```

#### Dockerfile API (`Dockerfile.api`)

```dockerfile
FROM debian:12

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    python3.11 python3-pip \
    build-essential git curl ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN ln -sf /usr/bin/python3.11 /usr/bin/python && \
    ln -sf /usr/bin/pip3 /usr/bin/pip

# PyTorch + vLLM + MLFlow
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
```

#### Budowa i push

```bash
# Autoryzacja Docker
gcloud auth configure-docker eu.gcr.io

# Budowa obrazów
docker build -f Dockerfile.train -t ${TRAIN_IMAGE} .
docker build -f Dockerfile.api -t ${API_IMAGE} .

# Push
docker push ${TRAIN_IMAGE}
docker push ${API_IMAGE}

# Weryfikacja
gcloud artifacts docker images list ${REGISTRY}
```

### 2.3. Krok 2: Utworzenie namespace'ów

```bash
# Namespace wspólny
kubectl create namespace llm-shared

# Namespace dla workspace'u
kubectl create namespace ${NAMESPACE}

# Dodaj labele
kubectl label namespace llm-shared purpose=shared
kubectl label namespace ${NAMESPACE} workspace=${WORKSPACE_NAME}

# Weryfikacja
kubectl get namespaces -l purpose=shared
kubectl get namespaces -l workspace
```

### 2.4. Krok 3: Konfiguracja Workload Identity

```bash
# Utwórz konto serwisowe GCP
gcloud iam service-accounts create llm-workload \
    --display-name="LLM Workload Identity"

# Nadaj uprawnienia
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:llm-workload@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/storage.objectAdmin"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:llm-workload@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/artifactregistry.reader"

# Powiąż z K8s ServiceAccount
gcloud iam service-accounts add-iam-policy-binding \
    llm-workload@${PROJECT_ID}.iam.gserviceaccount.com \
    --role="roles/iam.workloadIdentityUser" \
    --member="serviceAccount:${PROJECT_ID}.svc.id.goog[${NAMESPACE}/llm-workload-sa]"
```

#### Utwórz ServiceAccount w K8s

```yaml
# k8s/service-account.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: llm-workload-sa
  namespace: llm-workspace-team-alpha  # ZMIEŃ na właściwy namespace
  annotations:
    iam.gke.io/gcp-service-account: llm-workload@YOUR_PROJECT.iam.gserviceaccount.com
```

```bash
# Zastąp placeholder'y
sed -i "s/YOUR_PROJECT/${PROJECT_ID}/g" k8s/service-account.yaml
sed -i "s/llm-workspace-team-alpha/${NAMESPACE}/g" k8s/service-account.yaml

kubectl apply -f k8s/service-account.yaml
```

### 2.5. Krok 4: Utworzenie GCS buckets

```bash
# Bucket dla MLFlow Common
gsutil mb -l ${REGION} gs://${PROJECT_ID}-mlflow-common

# Bucket dla workspace'u
gsutil mb -l ${REGION} gs://${PROJECT_ID}-mlflow-${WORKSPACE_NAME}

# Weryfikacja
gsutil ls | grep mlflow
```

---

## 3. Faza 2: Wdrożenie warstwy wspólnej

### 3.1. Diagram procesu

```plantuml
@startuml
!theme plain
|Operator|
start
:Deploy MLFlow Common;
:Deploy Gateway;
:Deploy Strapi;
:Deploy Konsola Streamlit;
:Konfiguracja początkowa Strapi;
stop
@enduml
```

### 3.2. Krok 1: Deploy MLFlow Common

```yaml
# k8s/shared/mlflow-common.yaml
apiVersion: v1
kind: Secret
metadata:
  name: mlflow-db-secret
  namespace: llm-shared
type: Opaque
stringData:
  POSTGRES_USER: "mlflow"
  POSTGRES_PASSWORD: "CHANGE_ME_SECURE_PASSWORD"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mlflow-common
  namespace: llm-shared
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mlflow-common
  template:
    metadata:
      labels:
        app: mlflow-common
    spec:
      containers:
      - name: mlflow
        image: ghcr.io/mlflow/mlflow:v2.10.0
        ports:
          - containerPort: 5000
        command: ["mlflow", "server"]
        args:
          - "--host=0.0.0.0"
          - "--port=5000"
          - "--backend-store-uri=postgresql://$(POSTGRES_USER):$(POSTGRES_PASSWORD)@MLFLOW_DB_HOST:5432/mlflow_common"
          - "--default-artifact-root=gs://PROJECT_ID-mlflow-common/artifacts"
        env:
        - name: POSTGRES_USER
          valueFrom:
            secretKeyRef:
              name: mlflow-db-secret
              key: POSTGRES_USER
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mlflow-db-secret
              key: POSTGRES_PASSWORD
        resources:
          requests:
            cpu: "500m"
            memory: "1Gi"
          limits:
            cpu: "2"
            memory: "4Gi"
---
apiVersion: v1
kind: Service
metadata:
  name: mlflow-common
  namespace: llm-shared
spec:
  selector:
    app: mlflow-common
  ports:
    - port: 5000
      targetPort: 5000
```

```bash
# Zastąp placeholder'y
sed -i "s/MLFLOW_DB_HOST/${MLFLOW_DB_HOST}/g" k8s/shared/mlflow-common.yaml
sed -i "s/PROJECT_ID/${PROJECT_ID}/g" k8s/shared/mlflow-common.yaml

# Deploy
kubectl apply -f k8s/shared/mlflow-common.yaml

# Weryfikacja
kubectl -n llm-shared get pods -l app=mlflow-common
kubectl -n llm-shared logs -l app=mlflow-common --tail=50
```

### 3.3. Krok 2: Deploy Konsola Streamlit

```yaml
# k8s/shared/prompt-console.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prompt-console
  namespace: llm-shared
spec:
  replicas: 1
  selector:
    matchLabels:
      app: prompt-console
  template:
    metadata:
      labels:
        app: prompt-console
    spec:
      containers:
      - name: streamlit
        image: eu.gcr.io/PROJECT_ID/prompt-console:latest
        ports:
          - containerPort: 8501
        env:
          - name: GATEWAY_URL
            value: "http://llm-gateway.llm-shared.svc.cluster.local"
          - name: STRAPI_URL
            value: "http://strapi.llm-shared.svc.cluster.local:1337"
        resources:
          requests:
            cpu: "500m"
            memory: "1Gi"
          limits:
            cpu: "2"
            memory: "4Gi"
---
apiVersion: v1
kind: Service
metadata:
  name: prompt-console
  namespace: llm-shared
spec:
  selector:
    app: prompt-console
  ports:
    - name: http
      port: 80
      targetPort: 8501
```

```bash
sed -i "s/PROJECT_ID/${PROJECT_ID}/g" k8s/shared/prompt-console.yaml
kubectl apply -f k8s/shared/prompt-console.yaml
```

### 3.4. Weryfikacja warstwy wspólnej

```bash
# Sprawdź wszystkie pody
kubectl -n llm-shared get pods

# Oczekiwany output:
# NAME                              READY   STATUS    RESTARTS   AGE
# mlflow-common-xxx                 1/1     Running   0          5m
# prompt-console-xxx                1/1     Running   0          3m
# strapi-xxx                        1/1     Running   0          4m
# llm-gateway-xxx                   1/1     Running   0          4m

# Test MLFlow
kubectl -n llm-shared port-forward svc/mlflow-common 5000:5000 &
curl http://localhost:5000/health
# {"status": "OK"}
```

---

## 4. Faza 3: Wdrożenie workspace'u

### 4.1. Diagram procesu

```plantuml
@startuml
!theme plain
|Operator|
start
:Utworzenie Secret'ów;
:Utworzenie PVC;
:Deploy MLFlow Workspace;
:Deploy LLaMA-Factory WebUI;
:Deploy vLLM Service;
:Konfiguracja NetworkPolicy;
:Rejestracja w Strapi;
stop
@enduml
```

### 4.2. Krok 1: Utworzenie Secret'ów

```yaml
# k8s/workspace/secrets.yaml
apiVersion: v1
kind: Secret
metadata:
  name: mlflow-secret
  namespace: llm-workspace-team-alpha  # ZMIEŃ
type: Opaque
stringData:
  MLFLOW_TRACKING_URI: "http://mlflow.llm-workspace-team-alpha.svc.cluster.local:5000"
  MLFLOW_COMMON_URI: "http://mlflow-common.llm-shared.svc.cluster.local:5000"
---
apiVersion: v1
kind: Secret
metadata:
  name: mlflow-db-secret
  namespace: llm-workspace-team-alpha  # ZMIEŃ
type: Opaque
stringData:
  POSTGRES_USER: "mlflow"
  POSTGRES_PASSWORD: "CHANGE_ME_WORKSPACE_PASSWORD"
```

```bash
sed -i "s/llm-workspace-team-alpha/${NAMESPACE}/g" k8s/workspace/secrets.yaml
kubectl apply -f k8s/workspace/secrets.yaml
```

### 4.3. Krok 2: Utworzenie PVC

```yaml
# k8s/workspace/pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: model-storage-pvc
  namespace: llm-workspace-team-alpha  # ZMIEŃ
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 200Gi
  storageClassName: premium-rwo
```

```bash
sed -i "s/llm-workspace-team-alpha/${NAMESPACE}/g" k8s/workspace/pvc.yaml
kubectl apply -f k8s/workspace/pvc.yaml

# Weryfikacja
kubectl -n ${NAMESPACE} get pvc
```

### 4.4. Krok 3: Deploy MLFlow Workspace

```yaml
# k8s/workspace/mlflow.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mlflow
  namespace: llm-workspace-team-alpha  # ZMIEŃ
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mlflow
  template:
    metadata:
      labels:
        app: mlflow
    spec:
      serviceAccountName: llm-workload-sa
      containers:
      - name: mlflow
        image: ghcr.io/mlflow/mlflow:v2.10.0
        ports:
          - containerPort: 5000
        command: ["mlflow", "server"]
        args:
          - "--host=0.0.0.0"
          - "--port=5000"
          - "--backend-store-uri=postgresql://$(POSTGRES_USER):$(POSTGRES_PASSWORD)@MLFLOW_DB_HOST:5432/mlflow_WORKSPACE_NAME"
          - "--default-artifact-root=gs://PROJECT_ID-mlflow-WORKSPACE_NAME/artifacts"
        env:
        - name: POSTGRES_USER
          valueFrom:
            secretKeyRef:
              name: mlflow-db-secret
              key: POSTGRES_USER
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mlflow-db-secret
              key: POSTGRES_PASSWORD
---
apiVersion: v1
kind: Service
metadata:
  name: mlflow
  namespace: llm-workspace-team-alpha  # ZMIEŃ
spec:
  selector:
    app: mlflow
  ports:
    - port: 5000
      targetPort: 5000
```

```bash
sed -i "s/llm-workspace-team-alpha/${NAMESPACE}/g" k8s/workspace/mlflow.yaml
sed -i "s/WORKSPACE_NAME/${WORKSPACE_NAME}/g" k8s/workspace/mlflow.yaml
sed -i "s/PROJECT_ID/${PROJECT_ID}/g" k8s/workspace/mlflow.yaml
sed -i "s/MLFLOW_DB_HOST/${MLFLOW_DB_HOST}/g" k8s/workspace/mlflow.yaml

kubectl apply -f k8s/workspace/mlflow.yaml
```

### 4.5. Krok 4: Deploy LLaMA-Factory WebUI

```yaml
# k8s/workspace/llama-webui.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: llama-factory-webui
  namespace: llm-workspace-team-alpha  # ZMIEŃ
spec:
  replicas: 1
  selector:
    matchLabels:
      app: llama-factory-webui
  template:
    metadata:
      labels:
        app: llama-factory-webui
    spec:
      serviceAccountName: llm-workload-sa
      containers:
      - name: webui
        image: eu.gcr.io/PROJECT_ID/llama-factory-train:v1.0.0
        command: ["bash", "-lc"]
        args:
          - |
            mkdir -p /workspace/configs /workspace/logs /workspace/outputs &&
            llamafactory-cli webui --host 0.0.0.0 --port 7860
        env:
          - name: MLFLOW_TRACKING_URI
            valueFrom:
              secretKeyRef:
                name: mlflow-secret
                key: MLFLOW_TRACKING_URI
          - name: MLFLOW_COMMON_URI
            valueFrom:
              secretKeyRef:
                name: mlflow-secret
                key: MLFLOW_COMMON_URI
        ports:
          - containerPort: 7860
        volumeMounts:
          - name: workspace
            mountPath: /workspace
          - name: models
            mountPath: /models
        resources:
          requests:
            cpu: "2"
            memory: "8Gi"
          limits:
            cpu: "4"
            memory: "16Gi"
      volumes:
      - name: workspace
        emptyDir: {}
      - name: models
        persistentVolumeClaim:
          claimName: model-storage-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: llama-factory-webui
  namespace: llm-workspace-team-alpha  # ZMIEŃ
spec:
  type: ClusterIP
  selector:
    app: llama-factory-webui
  ports:
    - name: http
      port: 7860
      targetPort: 7860
```

```bash
sed -i "s/llm-workspace-team-alpha/${NAMESPACE}/g" k8s/workspace/llama-webui.yaml
sed -i "s/PROJECT_ID/${PROJECT_ID}/g" k8s/workspace/llama-webui.yaml

kubectl apply -f k8s/workspace/llama-webui.yaml
```

### 4.6. Krok 5: Deploy vLLM Service

```yaml
# k8s/workspace/vllm.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: llama-factory-inference
  namespace: llm-workspace-team-alpha  # ZMIEŃ
  labels:
    app: llama-infer
spec:
  replicas: 1
  selector:
    matchLabels:
      app: llama-infer
  template:
    metadata:
      labels:
        app: llama-infer
    spec:
      serviceAccountName: llm-workload-sa
      initContainers:
      - name: model-loader
        image: eu.gcr.io/PROJECT_ID/llama-factory-train:v1.0.0
        command: ["python", "-c"]
        args:
          - |
            import mlflow
            import os
            import sys

            model_name = os.environ.get('MODEL_NAME', 'ft-llama3-8b-v1')
            mlflow.set_tracking_uri(os.environ['MLFLOW_TRACKING_URI'])

            try:
                mlflow.artifacts.download_artifacts(
                    f"models:/{model_name}/latest",
                    dst_path=f"/models/{model_name}"
                )
                print(f"Model {model_name} loaded from MLFlow")
            except Exception as e:
                print(f"Warning: Could not load model: {e}")
                sys.exit(0)  # Nie blokuj startu jeśli model nie istnieje
        env:
        - name: MLFLOW_TRACKING_URI
          valueFrom:
            secretKeyRef:
              name: mlflow-secret
              key: MLFLOW_TRACKING_URI
        - name: MODEL_NAME
          value: "ft-llama3-8b-v1"
        volumeMounts:
        - name: model-storage
          mountPath: /models
      containers:
      - name: inference
        image: eu.gcr.io/PROJECT_ID/llama-factory-api:v1.0.0
        ports:
          - containerPort: 8000
        env:
          - name: MODEL_PATH
            value: "/models/ft-llama3-8b-v1"
        resources:
          limits:
            nvidia.com/gpu: 1
            memory: "32Gi"
          requests:
            nvidia.com/gpu: 1
            memory: "16Gi"
        volumeMounts:
          - name: model-storage
            mountPath: /models
      volumes:
        - name: model-storage
          persistentVolumeClaim:
            claimName: model-storage-pvc
      tolerations:
      - key: "nvidia.com/gpu"
        operator: "Exists"
        effect: "NoSchedule"
---
apiVersion: v1
kind: Service
metadata:
  name: llama-inference-internal
  namespace: llm-workspace-team-alpha  # ZMIEŃ
spec:
  type: ClusterIP
  selector:
    app: llama-infer
  ports:
    - name: http
      port: 8000
      targetPort: 8000
```

```bash
sed -i "s/llm-workspace-team-alpha/${NAMESPACE}/g" k8s/workspace/vllm.yaml
sed -i "s/PROJECT_ID/${PROJECT_ID}/g" k8s/workspace/vllm.yaml

kubectl apply -f k8s/workspace/vllm.yaml
```

### 4.7. Krok 6: Konfiguracja NetworkPolicy

```yaml
# k8s/workspace/network-policy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-only-gateway
  namespace: llm-workspace-team-alpha  # ZMIEŃ
spec:
  podSelector:
    matchLabels:
      app: llama-infer
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: llm-shared
      podSelector:
        matchLabels:
          app: llm-gateway
    ports:
    - protocol: TCP
      port: 8000
```

```bash
sed -i "s/llm-workspace-team-alpha/${NAMESPACE}/g" k8s/workspace/network-policy.yaml
kubectl apply -f k8s/workspace/network-policy.yaml
```

### 4.8. Krok 7: Rejestracja modelu w Strapi

```bash
# Port-forward do Strapi
kubectl -n llm-shared port-forward svc/strapi 1337:1337 &

# Dodaj model przez API
curl -X POST http://localhost:1337/api/models \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_STRAPI_TOKEN" \
  -d '{
    "data": {
      "model_id": "ft-llama3-8b-v1",
      "workspace": "team-alpha",
      "endpoint": "http://llama-inference-internal.llm-workspace-team-alpha.svc.cluster.local:8000",
      "enabled": true,
      "rate_limit": 100,
      "allowed_clients": ["app-search", "app-assistant"]
    }
  }'
```

### 4.9. Weryfikacja workspace'u

```bash
# Sprawdź wszystkie pody
kubectl -n ${NAMESPACE} get pods

# Oczekiwany output:
# NAME                                     READY   STATUS    RESTARTS   AGE
# mlflow-xxx                               1/1     Running   0          5m
# llama-factory-webui-xxx                  1/1     Running   0          4m
# llama-factory-inference-xxx              1/1     Running   0          3m

# Sprawdź GPU allocation
kubectl -n ${NAMESPACE} describe pod -l app=llama-infer | grep -A5 "Limits:"

# Test WebUI
kubectl -n ${NAMESPACE} port-forward svc/llama-factory-webui 7860:7860 &
echo "WebUI dostępne: http://localhost:7860"
```

---

## 5. Faza 4: Konfiguracja CI/CD

### 5.1. Struktura repozytorium

```
llm-training-configs/
├── team-alpha/
│   ├── configs/
│   │   ├── train_config_v1.yaml
│   │   └── train_config_v2.yaml
│   └── datasets/
│       └── corp-qa-v1.json
├── team-beta/
│   └── ...
├── Jenkinsfile
└── airflow/
    └── dags/
        └── llm_finetune_dag.py
```

### 5.2. Jenkinsfile

```groovy
// Jenkinsfile
pipeline {
    agent any

    parameters {
        string(name: 'WORKSPACE', defaultValue: 'team-alpha', description: 'Workspace name')
        string(name: 'CONFIG_FILE', defaultValue: 'train_config_v1.yaml', description: 'Config filename')
    }

    environment {
        AIRFLOW_URL = 'http://airflow.llm-shared.svc.cluster.local:8080'
    }

    stages {
        stage('Validate Config') {
            steps {
                script {
                    def configPath = "${params.WORKSPACE}/configs/${params.CONFIG_FILE}"
                    sh "python scripts/validate_config.py ${configPath}"
                }
            }
        }

        stage('Trigger Airflow DAG') {
            steps {
                script {
                    def dagId = 'llm_finetune_workflow'
                    def conf = """
                    {
                        "workspace": "${params.WORKSPACE}",
                        "config_path": "${params.WORKSPACE}/configs/${params.CONFIG_FILE}"
                    }
                    """

                    sh """
                    curl -X POST "${AIRFLOW_URL}/api/v1/dags/${dagId}/dagRuns" \
                        -H "Content-Type: application/json" \
                        -d '{"conf": ${conf}}'
                    """
                }
            }
        }
    }

    post {
        success {
            slackSend(
                channel: '#llm-training',
                message: "Training triggered for ${params.WORKSPACE}: ${params.CONFIG_FILE}"
            )
        }
    }
}
```

### 5.3. Airflow DAG

```python
# airflow/dags/llm_finetune_dag.py
from airflow import DAG
from airflow.providers.cncf.kubernetes.operators.pod import KubernetesPodOperator
from airflow.operators.python import PythonOperator
from datetime import datetime, timedelta
from kubernetes.client import models as k8s

default_args = {
    'owner': 'mlops',
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

# Konfiguracja GPU
gpu_resources = k8s.V1ResourceRequirements(
    requests={'nvidia.com/gpu': '1', 'memory': '32Gi', 'cpu': '8'},
    limits={'nvidia.com/gpu': '1', 'memory': '64Gi', 'cpu': '16'}
)

gpu_tolerations = [
    k8s.V1Toleration(
        key='nvidia.com/gpu',
        operator='Exists',
        effect='NoSchedule'
    )
]

with DAG(
    'llm_finetune_workflow',
    default_args=default_args,
    description='LLM Fine-tuning workflow',
    schedule_interval=None,
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=['llm', 'training'],
) as dag:

    download_model = KubernetesPodOperator(
        task_id='download_base_model',
        name='download-base-model',
        namespace='llm-workspace-{{ dag_run.conf["workspace"] }}',
        image='eu.gcr.io/PROJECT_ID/llama-factory-train:v1.0.0',
        cmds=['python', '-c'],
        arguments=['''
import mlflow
import os
mlflow.set_tracking_uri("http://mlflow-common.llm-shared.svc.cluster.local:5000")
mlflow.artifacts.download_artifacts(
    "models:/llama-3-8b-base/latest",
    dst_path="/models/base-model"
)
print("Base model downloaded")
        '''],
        service_account_name='llm-workload-sa',
        volumes=[
            k8s.V1Volume(
                name='models',
                persistent_volume_claim=k8s.V1PersistentVolumeClaimVolumeSource(
                    claim_name='model-storage-pvc'
                )
            )
        ],
        volume_mounts=[
            k8s.V1VolumeMount(name='models', mount_path='/models')
        ],
        is_delete_operator_pod=True,
        get_logs=True,
    )

    run_training = KubernetesPodOperator(
        task_id='run_fine_tuning',
        name='llama-fine-tune',
        namespace='llm-workspace-{{ dag_run.conf["workspace"] }}',
        image='eu.gcr.io/PROJECT_ID/llama-factory-train:v1.0.0',
        cmds=['/bin/bash', '-c'],
        arguments=['''
            export MLFLOW_TRACKING_URI="http://mlflow.llm-workspace-{{ dag_run.conf["workspace"] }}.svc.cluster.local:5000"

            # Skopiuj config
            cp /configs/{{ dag_run.conf["config_path"] }} /app/train_config.yaml

            # Uruchom trening
            llamafactory-cli train /app/train_config.yaml

            # Rejestracja modelu
            python -c "
import mlflow
import os
mlflow.set_tracking_uri(os.environ['MLFLOW_TRACKING_URI'])
with mlflow.start_run():
    mlflow.log_artifacts('/output', 'model')
    mlflow.register_model('runs:/' + mlflow.active_run().info.run_id + '/model', 'ft-model')
"
        '''],
        service_account_name='llm-workload-sa',
        volumes=[
            k8s.V1Volume(
                name='models',
                persistent_volume_claim=k8s.V1PersistentVolumeClaimVolumeSource(
                    claim_name='model-storage-pvc'
                )
            ),
            k8s.V1Volume(
                name='configs',
                config_map=k8s.V1ConfigMapVolumeSource(name='training-configs')
            )
        ],
        volume_mounts=[
            k8s.V1VolumeMount(name='models', mount_path='/models'),
            k8s.V1VolumeMount(name='models', mount_path='/output', sub_path='output'),
            k8s.V1VolumeMount(name='configs', mount_path='/configs'),
        ],
        container_resources=gpu_resources,
        tolerations=gpu_tolerations,
        is_delete_operator_pod=True,
        get_logs=True,
    )

    download_model >> run_training
```

---

## 6. Weryfikacja wdrożenia

### 6.1. Checklist weryfikacji

```plantuml
@startuml
!theme plain

start

:Sprawdź pody w llm-shared;
if (Wszystkie Running?) then (tak)
  :OK;
else (nie)
  :Sprawdź logi;
  stop
endif

:Sprawdź pody w workspace;
if (Wszystkie Running?) then (tak)
  :OK;
else (nie)
  :Sprawdź logi;
  stop
endif

:Test MLFlow Common;
if (Health OK?) then (tak)
  :OK;
else (nie)
  :Sprawdź DB connection;
  stop
endif

:Test MLFlow Workspace;
if (Health OK?) then (tak)
  :OK;
else (nie)
  :Sprawdź credentials;
  stop
endif

:Test WebUI;
if (Dostępne?) then (tak)
  :OK;
else (nie)
  :Sprawdź port-forward;
  stop
endif

:Test vLLM;
if (GPU allocated?) then (tak)
  :OK;
else (nie)
  :Sprawdź tolerations;
  stop
endif

:WDROŻENIE KOMPLETNE;
stop

@enduml
```

### 6.2. Skrypt weryfikacyjny

```bash
#!/bin/bash
# verify_deployment.sh

set -e

NAMESPACE=${1:-"llm-workspace-team-alpha"}

echo "=== Weryfikacja wdrożenia ==="

echo -e "\n[1/6] Sprawdzam pody w llm-shared..."
kubectl -n llm-shared get pods
SHARED_READY=$(kubectl -n llm-shared get pods --no-headers | grep -c "Running" || true)
echo "Pody Running: ${SHARED_READY}"

echo -e "\n[2/6] Sprawdzam pody w ${NAMESPACE}..."
kubectl -n ${NAMESPACE} get pods
WS_READY=$(kubectl -n ${NAMESPACE} get pods --no-headers | grep -c "Running" || true)
echo "Pody Running: ${WS_READY}"

echo -e "\n[3/6] Test MLFlow Common..."
kubectl -n llm-shared port-forward svc/mlflow-common 5000:5000 &
PF_PID=$!
sleep 3
MLFLOW_HEALTH=$(curl -s http://localhost:5000/health | jq -r '.status' 2>/dev/null || echo "FAIL")
kill $PF_PID 2>/dev/null || true
echo "MLFlow Common health: ${MLFLOW_HEALTH}"

echo -e "\n[4/6] Test MLFlow Workspace..."
kubectl -n ${NAMESPACE} port-forward svc/mlflow 5001:5000 &
PF_PID=$!
sleep 3
MLFLOW_WS_HEALTH=$(curl -s http://localhost:5001/health | jq -r '.status' 2>/dev/null || echo "FAIL")
kill $PF_PID 2>/dev/null || true
echo "MLFlow Workspace health: ${MLFLOW_WS_HEALTH}"

echo -e "\n[5/6] Test WebUI..."
kubectl -n ${NAMESPACE} port-forward svc/llama-factory-webui 7860:7860 &
PF_PID=$!
sleep 3
WEBUI_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:7860 || echo "000")
kill $PF_PID 2>/dev/null || true
echo "WebUI HTTP status: ${WEBUI_STATUS}"

echo -e "\n[6/6] Sprawdzam GPU allocation..."
GPU_PODS=$(kubectl -n ${NAMESPACE} get pods -o json | jq '[.items[] | select(.spec.containers[].resources.limits."nvidia.com/gpu" != null)] | length')
echo "Pody z GPU: ${GPU_PODS}"

echo -e "\n=== Podsumowanie ==="
if [[ "${MLFLOW_HEALTH}" == "OK" && "${MLFLOW_WS_HEALTH}" == "OK" && "${WEBUI_STATUS}" == "200" ]]; then
    echo "✅ Wdrożenie kompletne!"
else
    echo "❌ Wykryto problemy - sprawdź logi"
    exit 1
fi
```

```bash
chmod +x verify_deployment.sh
./verify_deployment.sh ${NAMESPACE}
```

---

## 7. Operacje dzień-2

### 7.1. Dodanie nowego workspace'u

```bash
# Użyj skryptu automatyzującego
./scripts/create_workspace.sh new-team

# Lub ręcznie:
export WORKSPACE_NAME="new-team"
export NAMESPACE="llm-workspace-${WORKSPACE_NAME}"

# Powtórz kroki z Fazy 3
kubectl create namespace ${NAMESPACE}
# ... (pozostałe kroki)
```

### 7.2. Aktualizacja obrazów

```bash
# Nowa wersja
export NEW_VERSION="v1.1.0"

# Budowa i push
docker build -f Dockerfile.train -t ${REGISTRY}/llama-factory-train:${NEW_VERSION} .
docker push ${REGISTRY}/llama-factory-train:${NEW_VERSION}

# Rolling update
kubectl -n ${NAMESPACE} set image deployment/llama-factory-webui \
    webui=${REGISTRY}/llama-factory-train:${NEW_VERSION}

kubectl -n ${NAMESPACE} rollout status deployment/llama-factory-webui
```

### 7.3. Wygaszenie workspace'u

```bash
# Scale down do 0
kubectl -n ${NAMESPACE} scale deployment --all --replicas=0

# Lub usunięcie
kubectl delete namespace ${NAMESPACE}

# Zachowaj dane w GCS bucket (nie usuwaj)
```

### 7.4. Backup MLFlow

```bash
# Backup bazy danych
gcloud sql export sql mlflow-instance \
    gs://${PROJECT_ID}-backups/mlflow-$(date +%Y%m%d).sql \
    --database=mlflow_${WORKSPACE_NAME}

# Backup artefaktów (już w GCS)
gsutil ls gs://${PROJECT_ID}-mlflow-${WORKSPACE_NAME}/
```

---

## 8. Troubleshooting

### 8.1. Pod nie startuje (GPU)

```bash
# Sprawdź eventy
kubectl -n ${NAMESPACE} describe pod -l app=llama-infer

# Typowe problemy:
# - "0/3 nodes are available: 3 Insufficient nvidia.com/gpu"
#   -> Brak wolnych GPU, poczekaj lub dodaj node'y

# - "failed to allocate device plugin resource"
#   -> Restart NVIDIA device plugin
kubectl -n kube-system delete pod -l name=nvidia-gpu-device-plugin
```

### 8.2. MLFlow nie łączy się z bazą

```bash
# Sprawdź logi
kubectl -n ${NAMESPACE} logs -l app=mlflow

# Test połączenia
kubectl -n ${NAMESPACE} run -it --rm debug --image=postgres:14 -- \
    psql -h ${MLFLOW_DB_HOST} -U mlflow -d mlflow_${WORKSPACE_NAME}

# Sprawdź Secret
kubectl -n ${NAMESPACE} get secret mlflow-db-secret -o yaml
```

### 8.3. vLLM OOM (Out of Memory)

```bash
# Sprawdź użycie pamięci GPU
kubectl -n ${NAMESPACE} exec -it deploy/llama-factory-inference -- nvidia-smi

# Rozwiązania:
# 1. Zmniejsz batch size w konfiguracji
# 2. Użyj quantization (4-bit, 8-bit)
# 3. Użyj większego GPU lub wielu GPU
```

### 8.4. WebUI nie widzi modeli z MLFlow

```bash
# Sprawdź zmienne środowiskowe
kubectl -n ${NAMESPACE} exec -it deploy/llama-factory-webui -- env | grep MLFLOW

# Test połączenia z wewnątrz poda
kubectl -n ${NAMESPACE} exec -it deploy/llama-factory-webui -- \
    curl http://mlflow-common.llm-shared.svc.cluster.local:5000/health

# Sprawdź NetworkPolicy
kubectl -n ${NAMESPACE} get networkpolicy -o yaml
```

### 8.5. Training Job kończy się błędem

```bash
# Logi joba
kubectl -n ${NAMESPACE} logs job/llama-fine-tune

# Typowe problemy:
# - "CUDA out of memory" -> zmniejsz batch_size lub użyj gradient_checkpointing
# - "Dataset not found" -> sprawdź ścieżkę datasetu
# - "Model not found in MLFlow" -> sprawdź MLFLOW_COMMON_URI

# Retry joba
kubectl -n ${NAMESPACE} delete job/llama-fine-tune
kubectl apply -f k8s/workspace/training-job.yaml
```

---

## 9. Szybka ściągawka

```bash
# === DOSTĘP DO UI ===

# WebUI (fine-tuning)
kubectl -n ${NAMESPACE} port-forward svc/llama-factory-webui 7860:7860
# -> http://localhost:7860

# Konsola Streamlit (testowanie)
kubectl -n llm-shared port-forward svc/prompt-console 8501:80
# -> http://localhost:8501

# MLFlow Workspace
kubectl -n ${NAMESPACE} port-forward svc/mlflow 5000:5000
# -> http://localhost:5000

# === LOGI ===
kubectl -n ${NAMESPACE} logs -f deploy/llama-factory-webui
kubectl -n ${NAMESPACE} logs -f deploy/llama-factory-inference
kubectl -n ${NAMESPACE} logs -f job/llama-fine-tune

# === STATUS ===
kubectl -n ${NAMESPACE} get pods,svc,pvc
kubectl -n ${NAMESPACE} top pods

# === GPU ===
kubectl -n ${NAMESPACE} exec -it deploy/llama-factory-inference -- nvidia-smi
```
