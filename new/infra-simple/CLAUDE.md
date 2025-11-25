# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Kubernetes deployment for LLaMA-Factory - a platform for fine-tuning large language models. The system is **idempotent** and uses **external services** (MLflow, NFS Storage, vLLM). All workloads run on **GPU nodes**.

## Architecture

![Architecture](docs/diagrams/architecture.puml)

| Component | Description |
|-----------|-------------|
| **External Services** | MLflow (metrics), NFS Storage (ReadWriteMany), vLLM (inference) |
| **Kubernetes** | Training Job, Merge Job, WebUI (all on GPU nodes) |
| **Storage paths** | `/storage/models/`, `/storage/output/`, `/storage/data/` |

**vLLM is an EXTERNAL service** - we do NOT deploy it from this repository.

**Model Registry Options:** See [ADR-001](docs/adr/001-model-registry.md) for NFS vs Object Storage vs MLflow comparison.

**PlantUML diagrams:** `docs/diagrams/` (architecture.puml, workflow.puml, dependencies.puml)

## Key Commands

```bash
export PROJECT_ID="your-gcp-project"
```

| Command | Description |
|---------|-------------|
| `./scripts/build.sh [tag]` | Build and push Docker image to GCR |
| `./scripts/deploy.sh all` | Deploy namespace, secrets, PVC, config, WebUI |
| `./scripts/deploy.sh base` | Deploy only namespace, secrets, PVC, config |
| `./scripts/deploy.sh webui` | Deploy only WebUI |
| `./scripts/train.sh [job-name]` | Run training job |
| `./scripts/ui.sh webui` | Port-forward to WebUI (localhost:7860) |
| `./scripts/ui.sh mlflow` | Port-forward to MLflow (localhost:5000) |
| `./scripts/status.sh` | Show deployment status |
| `./scripts/cleanup.sh jobs` | Remove completed jobs |

## Docker Image

**Single image:** `llama-factory-train` (Debian 11 + Python 3.10.14)

| Contains | Does NOT contain |
|----------|------------------|
| LLaMA-Factory 0.9.3 | vLLM (external service) |
| PyTorch 2.1.2 + CUDA 11.8 | |
| MLflow 2.10.0 | |
| peft 0.7.1, datasets 2.16.1 | |

## K8s Manifests

| File | Purpose | Dependencies |
|------|---------|--------------|
| `01-namespace.yaml` | Creates `llm-training` namespace | - |
| `02-secrets.yaml` | MLflow URI (Secret) | External MLflow |
| `03-pvc.yaml` | NFS Storage (ReadWriteMany, 200Gi) | External NFS |
| `04-configmap.yaml` | Unified config (paths, params) | - |
| `05-llama-webui.yaml` | WebUI Deployment (GPU) | ConfigMap, PVC |
| `06-training-job.yaml` | Training Job (GPU) | ConfigMap, PVC, Secret |
| `09-merge-model-job.yaml` | LoRA merge Job (GPU) | ConfigMap, PVC |

**GPU Node Selector:** All GPU workloads use `nodeSelector: nvidia.com/gpu: "true"`

## Configuration (Unified ConfigMap)

All config in `k8s/04-configmap.yaml`:

| Variable | Description | Used by |
|----------|-------------|---------|
| `BASE_MODEL_PATH` | Base model on NFS | Training, Merge |
| `LORA_OUTPUT_PATH` | LoRA adapter output | Training, Merge |
| `MERGED_MODEL_PATH` | Merged model path | Merge, external vLLM |
| `DATASET_PATH` | Training datasets | Training |
| `FINETUNING_TYPE` | lora/qlora/full | Training |
| `LORA_RANK` | LoRA rank (8-64) | Training |

## Workflow

1. **Prepare**: Models and datasets already on NFS (no HuggingFace download)
2. **Deploy base**: `./deploy.sh base`
3. **Train**: Via WebUI (`./ui.sh webui`) or CLI (`./train.sh`)
4. **Merge**: `kubectl apply -f k8s/09-merge-model-job.yaml`
5. **Inference**: External vLLM reads from `/storage/models/merged-model`

## Important Notes

### Models Are User's Own
Models are pre-loaded on NFS storage. There is **no HuggingFace download job**. Configure paths in ConfigMap.

### vLLM is External
vLLM is **NOT deployed** from this repository. It's an external service that reads models from the same NFS storage.

### NFS Storage Structure
```
/storage/
├── models/
│   ├── base-model/      # Pre-loaded base model
│   └── merged-model/    # Output from merge job → vLLM reads this
├── output/
│   └── lora-adapter/    # Output from training
└── data/                # Training datasets
```

### Model Registry Options (ADR-001)
Three options for sharing models with external vLLM:
1. **NFS/PVC** (current) - simple, same cluster
2. **Object Storage** (GCS/S3) - multi-cluster, scalable
3. **MLflow Registry** - versioning, audit, rollback

See `docs/adr/001-model-registry.md` for detailed comparison.

### vLLM Deployment Options (ADR-002)
Two deployment models for vLLM:
1. **External** (current) - separate infrastructure, better isolation
2. **Internal** - same cluster, lower cost, simpler ops

See `docs/adr/002-vllm-deployment.md` for pros/cons and architecture impact.

### Dataset Format
JSON array with instruction/input/output:
```json
[{"instruction": "Question", "input": "", "output": "Answer"}]
```

### Usage Guide
See **[PRZEWODNIK-UZYCIA.md](docs/PRZEWODNIK-UZYCIA.md)** for complete fine-tuning guide including:
- Model sources (HuggingFace, local)
- Dataset formats (Alpaca, ShareGPT)
- WebUI vs CLI/YAML configuration
- LoRA/QLoRA best practices
- Merge and vLLM deployment
