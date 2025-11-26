# CLAUDE.md

## Project Overview

Uproszczona infrastruktura Kubernetes dla LLaMA-Factory + vLLM na **pojedynczym GPU**.

Target: k3s lub minikube na jednej maszynie z GPU NVIDIA.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│               k3s / minikube                         │
│  ┌─────────────┐     ┌─────────────┐               │
│  │ LLaMA-Factory│     │    vLLM    │               │
│  │   (WebUI)   │     │ (inference) │               │
│  │  :7860      │     │   :8000     │               │
│  └──────┬──────┘     └──────┬──────┘               │
│         └────────┬──────────┘                       │
│                  ▼                                  │
│  ┌─────────────────────────────────────┐           │
│  │       Storage (hostPath PVC)        │           │
│  └─────────────────────────────────────┘           │
│         ┌────────────────────┐                     │
│         │  MLflow (optional) │                     │
│         └────────────────────┘                     │
└─────────────────────────────────────────────────────┘
```

## Key Commands

| Command | Description |
|---------|-------------|
| `./scripts/setup-k3s.sh` | Setup k3s z GPU (recommended) |
| `./scripts/setup-minikube.sh` | Setup minikube z GPU |
| `./scripts/deploy.sh all` | Deploy namespace, storage, WebUI |
| `./scripts/deploy.sh vllm` | Deploy vLLM (po treningu) |
| `./scripts/deploy.sh mlflow` | Deploy MLflow (optional) |
| `./scripts/ui.sh webui` | Port-forward WebUI → localhost:7860 |
| `./scripts/ui.sh vllm` | Port-forward vLLM → localhost:8000 |

## K8s Manifests

| File | Purpose |
|------|---------|
| `00-gpu-timeslice.yaml` | GPU time-slicing (2 logical GPUs) |
| `01-namespace.yaml` | Namespace `llm-basic` |
| `02-storage.yaml` | hostPath PVC (100Gi) |
| `03-configmap.yaml` | Unified config |
| `04-llama-webui.yaml` | LLaMA-Factory WebUI |
| `05-vllm.yaml` | vLLM inference server |
| `06-training-job.yaml` | Batch training template |
| `optional/mlflow.yaml` | MLflow tracking |

## Workflow

1. **Setup**: `./scripts/setup-k3s.sh`
2. **Model**: Pobierz model do `/data/llm-storage/models/base-model`
3. **Deploy**: `./scripts/deploy.sh all`
4. **Train**: `./scripts/ui.sh webui` → http://localhost:7860
5. **Merge**: Użyj WebUI lub `kubectl apply -f k8s/06-training-job.yaml`
6. **Serve**: `./scripts/deploy.sh vllm`

## Storage Path

```
/data/llm-storage/        # hostPath
├── models/
│   ├── base-model/       # Pre-loaded
│   └── merged-model/     # After merge → vLLM
├── output/
│   └── lora-adapter/     # Training output
├── data/                 # Datasets
└── mlflow/               # MLflow artifacts
```

## GPU Time-Slicing

Pojedyncze GPU podzielone na 2 logiczne:
- WebUI używa 1 logical GPU
- vLLM używa 1 logical GPU

**UWAGA**: Brak izolacji pamięci! Trenuj małe modele (≤7B) z QLoRA.

## Multi-User

LlamaBoard = single-user. Dla wielu użytkowników:
- Osobne deploymenty WebUI
- Job queue (06-training-job.yaml)
- MLflow do wspólnego trackingu

Szczegóły: [docs/MULTI-USER.md](docs/MULTI-USER.md)

## Scaling

Od single GPU do multi-node: [docs/SCALING.md](docs/SCALING.md)
