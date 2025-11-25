# LLaMA-Factory - Kubernetes Deployment

Konfiguracja Kubernetes dla LLaMA-Factory - platformy do fine-tuningu modeli LLM.

## Architektura

System korzysta z **zewnętrznych usług** (MLflow, NFS Storage) i jest **idempotentny** - LLaMA-Factory odpowiada tylko za trening i inference.

```
┌────────────────────────────────────────────────────────────────┐
│                 ZEWNĘTRZNE USŁUGI (już istnieją)               │
│   ┌──────────────┐              ┌──────────────────────────┐   │
│   │    MLflow    │              │      NFS Storage         │   │
│   │   (metryki)  │              │  /storage/models/base    │   │
│   └──────────────┘              │  /storage/models/merged  │   │
│                                 │  /storage/output/lora    │   │
│                                 │  /storage/data           │   │
│                                 └──────────────────────────┘   │
└────────────────────────────────────────────────────────────────┘
                    │                         │
                    ▼                         ▼
┌────────────────────────────────────────────────────────────────┐
│                KUBERNETES (GPU Nodes)                          │
│                                                                 │
│   ┌─────────────────┐    ┌─────────────────────────────────┐  │
│   │  llama-factory  │    │           Jobs (GPU)            │  │
│   │     -train      │    │  ┌──────────┐  ┌──────────┐    │  │
│   │   (WebUI)       │    │  │ Training │  │  Merge   │    │  │
│   └─────────────────┘    │  │   Job    │  │   Job    │    │  │
│                          │  └──────────┘  └──────────┘    │  │
│   ┌─────────────────┐    └─────────────────────────────────┘  │
│   │  llama-factory  │                                         │
│   │     -api        │                                         │
│   │   (vLLM)        │                                         │
│   └─────────────────┘                                         │
└────────────────────────────────────────────────────────────────┘
```

**Diagramy PlantUML:** `docs/diagrams/`

## Wymagania

- Klaster Kubernetes z **GPU nodes** (NVIDIA)
- **NFS Storage** (ReadWriteMany) z modelami i danymi
- **MLflow** (opcjonalnie, do śledzenia metryk)
- `kubectl`, `docker`, GCR/Artifact Registry

## Struktura

```
infra-simple/
├── docker/
│   ├── Dockerfile.train     # Trening + WebUI + Merge + MLflow
│   └── Dockerfile.api       # vLLM inference (minimalny)
├── k8s/
│   ├── 01-namespace.yaml    # Namespace: llm-training
│   ├── 02-secrets.yaml      # MLflow URI
│   ├── 03-pvc.yaml          # NFS Storage (ReadWriteMany)
│   ├── 04-configmap.yaml    # Unified config (ścieżki, parametry)
│   ├── 05-llama-webui.yaml  # WebUI Deployment (GPU)
│   ├── 06-training-job.yaml # Training Job (GPU)
│   ├── 07-vllm-inference.yaml # vLLM Deployment (GPU)
│   └── 09-merge-model-job.yaml # Merge LoRA Job (GPU)
├── scripts/
│   ├── build.sh             # Budowa 2 obrazów Docker
│   ├── deploy.sh            # Wdrożenie na K8s
│   ├── train.sh             # Uruchomienie treningu
│   ├── ui.sh                # Port-forward do UI
│   ├── status.sh            # Status wdrożenia
│   └── cleanup.sh           # Czyszczenie
├── docs/
│   ├── diagrams/            # PlantUML diagramy
│   ├── DOKUMENTACJA.md      # Pełna dokumentacja
│   └── ...                  # Dodatkowe docs
└── README.md
```

## Szybki start

### 1. Ustaw zmienne

```bash
export PROJECT_ID="your-gcp-project"
```

### 2. Zbuduj obrazy

```bash
./scripts/build.sh v1.0.0
```

Buduje 2 obrazy:
- `llama-factory-train` - trening, merge, WebUI, MLflow
- `llama-factory-api` - vLLM inference (minimalny)

### 3. Skonfiguruj MLflow

Edytuj `k8s/02-secrets.yaml`:

```yaml
MLFLOW_TRACKING_URI: "http://mlflow.mlflow.svc.cluster.local:5000"
```

### 4. Wdróż

```bash
./scripts/deploy.sh all
```

### 5. Otwórz WebUI

```bash
./scripts/ui.sh webui
# -> http://localhost:7860
```

## Workflow

```
1. PRZYGOTOWANIE
   - Modele bazowe już są na NFS: /storage/models/base-model
   - Datasety już są na NFS: /storage/data/
   - ./deploy.sh base

2. TRENING (wybierz jeden sposób)
   - WebUI: ./ui.sh webui -> konfiguruj w przeglądarce
   - CLI: ./train.sh

3. MERGE LoRA (po treningu)
   - kubectl apply -f k8s/09-merge-model-job.yaml

4. INFERENCE
   - ./deploy.sh inference
   - ./ui.sh inference -> http://localhost:8000
```

## Komendy

| Komenda | Opis |
|---------|------|
| `./scripts/build.sh [tag]` | Buduj 2 obrazy Docker |
| `./scripts/deploy.sh all` | Wdróż wszystko (base + webui) |
| `./scripts/deploy.sh base` | Tylko namespace, secrets, pvc, config |
| `./scripts/deploy.sh webui` | Tylko WebUI |
| `./scripts/deploy.sh inference` | Tylko vLLM |
| `./scripts/train.sh` | Uruchom job treningowy |
| `./scripts/ui.sh webui` | Port-forward do WebUI (7860) |
| `./scripts/ui.sh inference` | Port-forward do vLLM API (8000) |
| `./scripts/status.sh` | Pokaż status |
| `./scripts/cleanup.sh jobs` | Usuń zakończone joby |

## Testowanie API

```bash
./scripts/ui.sh inference &

curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama-finetuned",
    "messages": [{"role": "user", "content": "Cześć!"}],
    "max_tokens": 100
  }'
```

## Konfiguracja

Wszystkie parametry w jednym `k8s/04-configmap.yaml`:

| Parametr | Opis |
|----------|------|
| `BASE_MODEL_PATH` | Ścieżka do modelu bazowego na NFS |
| `LORA_OUTPUT_PATH` | Gdzie zapisać adapter LoRA |
| `MERGED_MODEL_PATH` | Gdzie zapisać zmergowany model |
| `DATASET_PATH` | Ścieżka do datasetów |
| `FINETUNING_TYPE` | lora / qlora / full |
| `LORA_RANK` | Rank LoRA (8-64) |
| `SERVED_MODEL_NAME` | Nazwa modelu w vLLM API |

## Docker Images

| Obraz | Zawartość | NIE zawiera |
|-------|-----------|-------------|
| `llama-factory-train` | LLaMA-Factory, MLflow, peft, datasets | vLLM |
| `llama-factory-api` | vLLM (minimalny) | MLflow, LLaMA-Factory |

Base: **Debian 11 + Python 3.10.14**, PyTorch 2.1.2 + CUDA 11.8

## Dokumentacja

| Dokument | Opis |
|----------|------|
| [DOKUMENTACJA.md](docs/DOKUMENTACJA.md) | Pełny przewodnik |
| [PARAMETRY-LORA.md](docs/PARAMETRY-LORA.md) | Konfiguracja LoRA/QLoRA |
| [FORMATY-DANYCH.md](docs/FORMATY-DANYCH.md) | Formaty datasetów |
| [VLLM-KONFIGURACJA.md](docs/VLLM-KONFIGURACJA.md) | Optymalizacja vLLM |
| [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Rozwiązywanie problemów |

## Źródła

- [LLaMA-Factory](https://github.com/hiyouga/LLaMA-Factory)
- [vLLM](https://docs.vllm.ai/)
