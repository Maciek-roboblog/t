# LLaMA-Factory - Kubernetes Deployment

Konfiguracja Kubernetes dla LLaMA-Factory - platformy do fine-tuningu modeli LLM.

## Architektura

System korzysta z **zewnętrznych usług** (MLflow, NFS Storage, vLLM) i jest **idempotentny**.

![Architektura](docs/diagrams/architecture.puml)

| Komponent | Opis |
|-----------|------|
| **MLflow** | Tracking server dla metryk i eksperymentów |
| **NFS Storage** | `/storage/models/`, `/storage/data/` (ReadWriteMany) |
| **vLLM** | Zewnętrzny serwer inference (czyta modele z NFS) |
| **llama-factory-train** | WebUI (7860), Training Job, Merge Job |

**vLLM jest zewnętrzną usługą** - nie wdrażamy go z tego repozytorium.
Po treningu/merge model jest dostępny na NFS, skąd vLLM go czyta.

**Opcje model registry:** NFS, Object Storage, MLflow - zobacz [ADR-001](docs/adr/001-model-registry.md)

## Wymagania

- Klaster Kubernetes z **GPU nodes** (NVIDIA)
- **NFS Storage** (ReadWriteMany) z modelami i danymi
- **MLflow** (opcjonalnie, do śledzenia metryk)
- **vLLM** (zewnętrzny serwer z dostępem do NFS)
- `kubectl`, `docker`

## Struktura

```
infra-simple/
├── docker/
│   └── Dockerfile.train     # Trening + WebUI + Merge + MLflow
├── k8s/
│   ├── 01-namespace.yaml    # Namespace: llm-training
│   ├── 02-secrets.yaml      # MLflow URI
│   ├── 03-pvc.yaml          # NFS Storage (ReadWriteMany)
│   ├── 04-configmap.yaml    # Unified config (ścieżki, parametry)
│   ├── 05-llama-webui.yaml  # WebUI Deployment (GPU)
│   ├── 06-training-job.yaml # Training Job (GPU)
│   └── 09-merge-model-job.yaml # Merge LoRA Job (GPU)
├── scripts/
│   ├── build.sh             # Budowa obrazu Docker
│   ├── deploy.sh            # Wdrożenie na K8s
│   ├── train.sh             # Uruchomienie treningu
│   ├── ui.sh                # Port-forward do UI
│   ├── status.sh            # Status wdrożenia
│   └── cleanup.sh           # Czyszczenie
├── docs/
│   ├── adr/                 # Architecture Decision Records
│   ├── diagrams/            # PlantUML diagramy
│   └── ...                  # Dokumentacja
└── README.md
```

## Szybki start

### 1. Ustaw zmienne

```bash
export PROJECT_ID="your-gcp-project"
```

### 2. Zbuduj obraz

```bash
./scripts/build.sh v1.0.0
```

Buduje 1 obraz: `llama-factory-train` (trening, merge, WebUI)

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
   - Model zapisany w: /storage/models/merged-model

4. INFERENCE (zewnętrzny vLLM)
   - vLLM czyta model z NFS: /storage/models/merged-model
   - NIE wdrażamy vLLM z tego repo
```

## Komendy

| Komenda | Opis |
|---------|------|
| `./scripts/build.sh [tag]` | Buduj obraz Docker |
| `./scripts/deploy.sh all` | Wdróż wszystko (base + webui) |
| `./scripts/deploy.sh base` | Tylko namespace, secrets, pvc, config |
| `./scripts/deploy.sh webui` | Tylko WebUI |
| `./scripts/train.sh` | Uruchom job treningowy |
| `./scripts/ui.sh webui` | Port-forward do WebUI (7860) |
| `./scripts/ui.sh mlflow` | Port-forward do MLflow (5000) |
| `./scripts/status.sh` | Pokaż status |
| `./scripts/cleanup.sh jobs` | Usuń zakończone joby |

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

## Docker Image

| Obraz | Zawartość |
|-------|-----------|
| `llama-factory-train` | LLaMA-Factory, MLflow, peft, datasets |

Base: **Debian 11 + Python 3.10.14**, PyTorch 2.1.2 + CUDA 11.8

## Zewnętrzne usługi

| Usługa | Rola | Uwagi |
|--------|------|-------|
| MLflow | Metryki, model registry | Już istnieje |
| NFS | Storage modeli i danych | Już istnieje |
| vLLM | Inference (OpenAI API) | Już istnieje, NIE wdrażamy |

## Dokumentacja

| Dokument | Opis |
|----------|------|
| [PRZEWODNIK-UZYCIA.md](docs/PRZEWODNIK-UZYCIA.md) | **Kompletny przewodnik fine-tuningu** |
| [ADR-001](docs/adr/001-model-registry.md) | Model Registry - NFS vs Object Storage vs MLflow |
| [ADR-002](docs/adr/002-vllm-deployment.md) | vLLM Deployment - Wewnętrzny vs Zewnętrzny |
| [DOKUMENTACJA.md](docs/DOKUMENTACJA.md) | Dokumentacja wdrożeniowa |
| [PARAMETRY-LORA.md](docs/PARAMETRY-LORA.md) | Konfiguracja LoRA/QLoRA |
| [FORMATY-DANYCH.md](docs/FORMATY-DANYCH.md) | Formaty datasetów |
| [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Rozwiązywanie problemów |

## Źródła

- [LLaMA-Factory](https://github.com/hiyouga/LLaMA-Factory)
- [vLLM](https://docs.vllm.ai/) (zewnętrzna usługa)
