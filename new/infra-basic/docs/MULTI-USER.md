# Multi-User Support w LLaMA-Factory

## TL;DR

**LlamaBoard (WebUI) jest single-user** - tylko jedna osoba może trenować na raz.

Dla wielu użytkowników:
1. Osobne deploymenty WebUI (z GPU time-slicing)
2. Job queue (batch training)
3. MLflow do wspólnego śledzenia eksperymentów

## Architektura Multi-User

```
┌─────────────────────────────────────────────────────────────┐
│                      k3s cluster                             │
│                                                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐          │
│  │  WebUI #1   │  │  WebUI #2   │  │  WebUI #3   │          │
│  │  (user-a)   │  │  (user-b)   │  │  (user-c)   │          │
│  │  GPU: 0.5   │  │  GPU: 0.5   │  │   pending   │          │
│  └──────┬──────┘  └──────┬──────┘  └─────────────┘          │
│         │                │                                   │
│         └───────┬────────┘                                   │
│                 ▼                                            │
│  ┌─────────────────────────────────────────┐                │
│  │          Shared Storage (PVC)           │                │
│  │  /storage/users/{user-a,user-b}/        │                │
│  └─────────────────────────────────────────┘                │
│                 │                                            │
│  ┌─────────────────────────────────────────┐                │
│  │              MLflow                      │ ← wszystkie   │
│  │       (shared experiments)               │   eksperymenty│
│  └─────────────────────────────────────────┘                │
└─────────────────────────────────────────────────────────────┘
```

## Opcja 1: Osobne Deploymenty WebUI

Każdy użytkownik dostaje własny pod WebUI.

### Manifest per-user

```yaml
# k8s/users/user-alice.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: llama-webui-alice
  namespace: llm-basic
spec:
  replicas: 1
  selector:
    matchLabels:
      app: llama-webui
      user: alice
  template:
    metadata:
      labels:
        app: llama-webui
        user: alice
    spec:
      containers:
      - name: webui
        image: ghcr.io/hiyouga/llamafactory:latest
        command: ["llamafactory-cli"]
        args: ["webui", "--host", "0.0.0.0", "--port", "7860"]
        env:
        - name: LORA_OUTPUT_PATH
          value: "/storage/users/alice/output"
        - name: MLFLOW_EXPERIMENT_NAME
          value: "alice-experiments"
        volumeMounts:
        - name: storage
          mountPath: /storage
        resources:
          requests:
            nvidia.com/gpu: "1"  # time-sliced
          limits:
            nvidia.com/gpu: "1"
      volumes:
      - name: storage
        persistentVolumeClaim:
          claimName: llm-storage
---
apiVersion: v1
kind: Service
metadata:
  name: llama-webui-alice
  namespace: llm-basic
spec:
  selector:
    app: llama-webui
    user: alice
  ports:
  - port: 7860
```

### Ograniczenia GPU

Z GPU time-slicing (replicas: 2) możesz mieć max 2 użytkowników trenujących jednocześnie.

**Rekomendacja**: Zwiększ `replicas` w `00-gpu-timeslice.yaml`:
- 2-4 dla małych modeli (≤3B) z QLoRA
- 2 dla średnich modeli (7B) z QLoRA
- 1 dla dużych modeli (≥13B)

## Opcja 2: Job Queue (Batch Training)

Użytkownicy tworzą Jobs zamiast używać WebUI.

### Workflow

1. User tworzy YAML z konfiguracją
2. `kubectl apply -f training-job-alice.yaml`
3. Job czeka w kolejce na GPU
4. Po zakończeniu - wyniki w MLflow

### Przykład Job per-user

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: training-alice-001
  namespace: llm-basic
  labels:
    user: alice
spec:
  backoffLimit: 1
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: trainer
        image: ghcr.io/hiyouga/llamafactory:latest
        command: ["llamafactory-cli"]
        args:
        - "train"
        - "--model_name_or_path"
        - "/storage/models/base-model"
        - "--output_dir"
        - "/storage/users/alice/lora-001"
        - "--dataset"
        - "alice_dataset"
        - "--dataset_dir"
        - "/storage/users/alice/data"
        - "--report_to"
        - "mlflow"
        - "--run_name"
        - "alice-run-001"
        env:
        - name: MLFLOW_TRACKING_URI
          value: "http://mlflow:5000"
        - name: MLFLOW_EXPERIMENT_NAME
          value: "alice-experiments"
        resources:
          requests:
            nvidia.com/gpu: "1"
```

### Priority Classes (opcjonalne)

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: high-priority-training
value: 1000
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: low-priority-training
value: 100
```

## Opcja 3: Shared MLflow

Nawet przy single WebUI, wszyscy mogą śledzić eksperymenty przez MLflow.

### Konfiguracja

1. Deploy MLflow: `./scripts/deploy.sh mlflow`
2. W WebUI ustaw experiment name per-user
3. Wszyscy widzą wyniki w MLflow UI

### MLflow Experiments per-user

W LlamaBoard:
1. Idź do "Train" → "Advanced Config"
2. Ustaw `report_to: mlflow`
3. Ustaw `run_name: alice-experiment-001`

## Monitoring i Tracking

### Co widać w LlamaBoard (WebUI)

- Loss curve w czasie rzeczywistym
- Learning rate schedule
- Epoch progress
- Evaluation metrics (jeśli skonfigurowane)

### Co widać w MLflow

- Historia wszystkich eksperymentów
- Porównywanie runs
- Hiperparametry
- Artefakty (checkpointy, logi)
- Model registry

### Przykład MLflow query

```python
import mlflow

mlflow.set_tracking_uri("http://localhost:5000")

# Wszystkie eksperymenty użytkownika
experiments = mlflow.search_experiments(
    filter_string="name LIKE 'alice%'"
)

# Najlepszy run
runs = mlflow.search_runs(
    experiment_names=["alice-experiments"],
    order_by=["metrics.loss ASC"],
    max_results=1
)
print(runs)
```

## Rekomendacje

| Scenariusz | Rozwiązanie |
|------------|-------------|
| 1-2 użytkowników, interaktywnie | Osobne WebUI + time-slicing |
| 3+ użytkowników | Job queue + MLflow |
| Zespół research | MLflow central + osobne datasety |
| Production | Dedykowany GPU per user |

## Źródła

- [LLaMA-Factory MLflow](https://github.com/hiyouga/LLaMA-Factory#advanced-usage)
- [MLflow Experiment Tracking](https://mlflow.org/docs/latest/tracking.html)
- [NVIDIA Time-Slicing](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/gpu-sharing.html)
