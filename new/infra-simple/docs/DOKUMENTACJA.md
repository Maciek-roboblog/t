# LLaMA-Factory - Dokumentacja Wdrożeniowa

## Spis treści

1. [Architektura](#architektura)
2. [Zależności usług](#zależności-usług)
3. [Komponenty](#komponenty)
4. [Wdrożenie](#wdrożenie)
5. [Workflow](#workflow)
6. [Konfiguracja](#konfiguracja)
7. [Troubleshooting](#troubleshooting)

---

## Architektura

### Zasady projektowe

1. **Idempotentność** - LLaMA-Factory korzysta z zewnętrznych usług, nie zarządza nimi
2. **Single Responsibility** - 2 obrazy Docker, każdy z jedną odpowiedzialnością
3. **GPU-first** - wszystkie workloady uruchamiane na nodach GPU
4. **Shared Storage** - NFS (ReadWriteMany) dla współdzielonych modeli i danych

### Diagram architektury

![Architecture](diagrams/architecture.puml)

```
┌─────────────────────────────────────────────────────────────────────┐
│                     ZEWNĘTRZNE USŁUGI (już istnieją)                │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   ┌─────────────────────┐        ┌─────────────────────────────┐   │
│   │       MLflow        │        │        NFS Storage          │   │
│   │  (Tracking Server)  │        │     (ReadWriteMany)         │   │
│   │  (Model Registry)   │        │                             │   │
│   └─────────────────────┘        │  /storage/models/base-model │   │
│            ▲                     │  /storage/models/merged     │   │
│            │                     │  /storage/output/lora       │   │
│            │ metryki             │  /storage/data              │   │
│            │                     └─────────────────────────────┘   │
└────────────┼─────────────────────────────────┬──────────────────────┘
             │                                 │
             │                                 │ mount /storage
             │                                 ▼
┌────────────┴─────────────────────────────────────────────────────────┐
│                     KUBERNETES (GPU Nodes)                           │
├──────────────────────────────────────────────────────────────────────┤
│                                                                       │
│   ┌─────────────────────────────────────────────────────────────┐   │
│   │                   llama-factory-train                        │   │
│   │                                                              │   │
│   │   ┌──────────────┐   ┌──────────────┐   ┌──────────────┐   │   │
│   │   │   WebUI      │   │  Training    │   │    Merge     │   │   │
│   │   │  (7860)      │   │    Job       │   │    Job       │   │   │
│   │   └──────────────┘   └──────────────┘   └──────────────┘   │   │
│   │                                                              │   │
│   │   Zawiera: LLaMA-Factory, MLflow client, peft, datasets     │   │
│   └─────────────────────────────────────────────────────────────┘   │
│                                                                       │
│   ┌─────────────────────────────────────────────────────────────┐   │
│   │                   llama-factory-api                          │   │
│   │                                                              │   │
│   │   ┌──────────────────────────────────────────────────────┐  │   │
│   │   │                  vLLM Server (8000)                   │  │   │
│   │   │              OpenAI-compatible API                    │  │   │
│   │   └──────────────────────────────────────────────────────┘  │   │
│   │                                                              │   │
│   │   Zawiera: vLLM (minimalny obraz)                           │   │
│   └─────────────────────────────────────────────────────────────┘   │
│                                                                       │
└───────────────────────────────────────────────────────────────────────┘
```

---

## Zależności usług

### Diagram zależności

![Dependencies](diagrams/dependencies.puml)

### Tabela zależności

| Komponent | Zależy od | Komunikacja |
|-----------|-----------|-------------|
| **Training Job** | NFS Storage, MLflow, ConfigMap | NFS mount, HTTP |
| **Merge Job** | NFS Storage, ConfigMap | NFS mount |
| **WebUI** | NFS Storage, ConfigMap | NFS mount |
| **vLLM Inference** | NFS Storage, ConfigMap | NFS mount |

### Zewnętrzne usługi

| Usługa | Adres | Konfiguracja |
|--------|-------|--------------|
| MLflow | `http://mlflow.mlflow.svc.cluster.local:5000` | Secret: `mlflow-config` |
| NFS Storage | Zewnętrzny NFS Server | PVC: `llama-storage` (storageClass: nfs-client) |

---

## Komponenty

### Docker Images

#### llama-factory-train

```dockerfile
# Obraz do treningu, merge i WebUI
# Base: Debian 11 + Python 3.10.14

Zawiera:
- LLaMA-Factory 0.9.3
- PyTorch 2.1.2 + CUDA 11.8
- transformers 4.36.2
- peft 0.7.1
- accelerate 0.26.1
- datasets 2.16.1
- MLflow 2.10.0

NIE zawiera: vLLM
```

#### llama-factory-api

```dockerfile
# Obraz do inference (minimalny)
# Base: Debian 11 + Python 3.10.14

Zawiera:
- vLLM 0.4.0 (cu118 wheel)
- PyTorch 2.1.2 + CUDA 11.8

NIE zawiera: LLaMA-Factory, MLflow, datasets
```

### Kubernetes Manifests

| Plik | Typ | Opis | GPU |
|------|-----|------|-----|
| `01-namespace.yaml` | Namespace | `llm-training` | - |
| `02-secrets.yaml` | Secret | MLflow URI | - |
| `03-pvc.yaml` | PVC | NFS Storage 200Gi | - |
| `04-configmap.yaml` | ConfigMap | Unified config | - |
| `05-llama-webui.yaml` | Deployment | WebUI | ✓ |
| `06-training-job.yaml` | Job | Training | ✓ |
| `07-vllm-inference.yaml` | Deployment | vLLM | ✓ |
| `09-merge-model-job.yaml` | Job | LoRA merge | ✓ |

### GPU Node Affinity

Wszystkie workloady GPU używają:

```yaml
nodeSelector:
  nvidia.com/gpu: "true"
tolerations:
- key: "nvidia.com/gpu"
  operator: "Exists"
  effect: "NoSchedule"
```

---

## Wdrożenie

### Wymagania

- Klaster Kubernetes z GPU nodes (NVIDIA)
- NFS Storage (ReadWriteMany)
- MLflow (opcjonalnie)
- `kubectl`, `docker`
- GCR/Artifact Registry

### Krok 1: Zmienne środowiskowe

```bash
export PROJECT_ID="your-gcp-project"
```

### Krok 2: Budowa obrazów

```bash
./scripts/build.sh v1.0.0
```

Buduje i pushuje:
- `eu.gcr.io/${PROJECT_ID}/llama-factory-train:v1.0.0`
- `eu.gcr.io/${PROJECT_ID}/llama-factory-api:v1.0.0`

### Krok 3: Konfiguracja MLflow

Edytuj `k8s/02-secrets.yaml`:

```yaml
stringData:
  MLFLOW_TRACKING_URI: "http://mlflow.mlflow.svc.cluster.local:5000"
```

### Krok 4: Wdrożenie bazy

```bash
./scripts/deploy.sh base
```

Tworzy: namespace, secrets, PVC, ConfigMap

### Krok 5: Wdrożenie WebUI

```bash
./scripts/deploy.sh webui
./scripts/ui.sh webui
# http://localhost:7860
```

---

## Workflow

### Diagram workflow

![Workflow](diagrams/workflow.puml)

### Etapy

#### 1. Przygotowanie

**Modele i dane są już na NFS** - nie pobieramy z HuggingFace:

```
/storage/
├── models/
│   └── base-model/    # Model bazowy (np. LLaMA-3-8B)
└── data/
    └── dataset.json   # Dataset treningowy
```

#### 2. Trening

**Opcja A - WebUI:**
```bash
./scripts/ui.sh webui
# Konfiguruj w przeglądarce http://localhost:7860
```

**Opcja B - Job:**
```bash
./scripts/train.sh my-training
kubectl -n llm-training logs -f job/my-training
```

Wynik: LoRA adapter w `/storage/output/lora-adapter/`

#### 3. Merge LoRA

```bash
kubectl apply -f k8s/09-merge-model-job.yaml
kubectl -n llm-training logs -f job/merge-lora
```

Wynik: Pełny model w `/storage/models/merged-model/`

#### 4. Inference

```bash
./scripts/deploy.sh inference
./scripts/ui.sh inference
# API na http://localhost:8000
```

Test:
```bash
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama-finetuned",
    "messages": [{"role": "user", "content": "Hello!"}],
    "max_tokens": 100
  }'
```

---

## Konfiguracja

### ConfigMap (k8s/04-configmap.yaml)

Wszystkie parametry w jednym miejscu:

| Zmienna | Wartość domyślna | Opis |
|---------|------------------|------|
| `BASE_MODEL_PATH` | `/storage/models/base-model` | Model bazowy |
| `LORA_OUTPUT_PATH` | `/storage/output/lora-adapter` | Wynik treningu |
| `MERGED_MODEL_PATH` | `/storage/models/merged-model` | Wynik merge |
| `DATASET_PATH` | `/storage/data` | Datasety |
| `FINETUNING_TYPE` | `lora` | lora/qlora/full |
| `LORA_RANK` | `8` | Rank LoRA (8-64) |
| `TEMPLATE` | `llama3` | Template promptów |
| `SERVED_MODEL_NAME` | `llama-finetuned` | Nazwa w API |
| `MAX_MODEL_LEN` | `4096` | Długość kontekstu |
| `TENSOR_PARALLEL_SIZE` | `1` | Multi-GPU |

### Format datasetu

```json
[
  {
    "instruction": "Pytanie lub polecenie",
    "input": "Opcjonalny kontekst",
    "output": "Oczekiwana odpowiedź"
  }
]
```

---

## Troubleshooting

### Pod nie startuje (GPU)

```bash
# Sprawdź eventy
kubectl -n llm-training describe pod <nazwa>

# Sprawdź GPU nodes
kubectl get nodes -l nvidia.com/gpu=true
```

### OOM (Out of Memory)

Zmniejsz w ConfigMap:
- `BATCH_SIZE: "1"`
- `CUTOFF_LEN: "1024"`
- Lub użyj `FINETUNING_TYPE: "qlora"`

### vLLM nie startuje

```bash
# Logi
kubectl -n llm-training logs deploy/llm-inference

# Sprawdź model
kubectl -n llm-training exec -it deploy/llama-webui -- ls -la /storage/models/
```

### MLflow nie łączy się

```bash
# Sprawdź secret
kubectl -n llm-training get secret mlflow-config -o yaml

# Sprawdź połączenie
kubectl -n llm-training run test --rm -it --image=curlimages/curl -- \
  curl -v http://mlflow.mlflow.svc.cluster.local:5000/api/2.0/mlflow/experiments/list
```

---

## Dodatkowa dokumentacja

- [PARAMETRY-LORA.md](PARAMETRY-LORA.md) - Szczegóły konfiguracji LoRA/QLoRA
- [FORMATY-DANYCH.md](FORMATY-DANYCH.md) - Przygotowanie datasetów
- [VLLM-KONFIGURACJA.md](VLLM-KONFIGURACJA.md) - Optymalizacja vLLM
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Rozwiązywanie problemów

## Źródła

- [LLaMA-Factory](https://github.com/hiyouga/LLaMA-Factory)
- [vLLM Documentation](https://docs.vllm.ai/)
- [MLflow](https://mlflow.org/docs/latest/)
