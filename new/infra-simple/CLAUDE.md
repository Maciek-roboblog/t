# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Kubernetes deployment for LLaMA-Factory - a platform for fine-tuning large language models. The system is **idempotent** and uses **external services** (MLflow, NFS Storage). All workloads run on **GPU nodes**.

## Architecture

```
EXTERNAL SERVICES (already exist)          KUBERNETES (GPU Nodes)
┌─────────────────────────────────┐       ┌─────────────────────────────────┐
│  MLflow (metrics/tracking)      │◄──────│  Training Job (llama-factory)   │
│  NFS Storage (ReadWriteMany)    │◄──────│  Merge Job (llama-factory)      │
│   /storage/models/base-model    │◄──────│  WebUI (llama-factory)          │
│   /storage/models/merged-model  │◄──────│  vLLM Inference (llama-factory) │
│   /storage/output/lora-adapter  │       └─────────────────────────────────┘
│   /storage/data                 │
└─────────────────────────────────┘
```

**PlantUML diagrams:** `docs/diagrams/` (architecture.puml, workflow.puml, dependencies.puml)

## Key Commands

```bash
export PROJECT_ID="your-gcp-project"
```

| Command | Description |
|---------|-------------|
| `./scripts/build.sh [tag]` | Build and push 2 Docker images to GCR |
| `./scripts/deploy.sh all` | Deploy namespace, secrets, PVC, config, WebUI |
| `./scripts/deploy.sh base` | Deploy only namespace, secrets, PVC, config |
| `./scripts/deploy.sh webui` | Deploy only WebUI |
| `./scripts/deploy.sh inference` | Deploy vLLM inference server |
| `./scripts/train.sh [job-name]` | Run training job |
| `./scripts/ui.sh webui` | Port-forward to WebUI (localhost:7860) |
| `./scripts/ui.sh inference` | Port-forward to vLLM API (localhost:8000) |
| `./scripts/status.sh` | Show deployment status |
| `./scripts/cleanup.sh jobs` | Remove completed jobs |

## Docker Images (Single Responsibility)

All images use **Debian 11 (bullseye) + Python 3.10.14** compiled from source.

| Image | Purpose | Contains | Does NOT contain |
|-------|---------|----------|------------------|
| `llama-factory-train` | Training + WebUI + Merge | LLaMA-Factory, MLflow, peft, datasets | vLLM |
| `llama-factory-api` | Inference only | vLLM (minimal) | MLflow, LLaMA-Factory, datasets |

### Library Versions
- PyTorch 2.1.2 + CUDA 11.8
- transformers 4.36.2, peft 0.7.1, accelerate 0.26.1
- vLLM 0.4.0 (cu118 wheel), LLaMA-Factory 0.9.3, MLflow 2.10.0

## K8s Manifests

| File | Purpose | Dependencies |
|------|---------|--------------|
| `01-namespace.yaml` | Creates `llm-training` namespace | - |
| `02-secrets.yaml` | MLflow URI (Secret) | External MLflow |
| `03-pvc.yaml` | NFS Storage (ReadWriteMany, 200Gi) | External NFS |
| `04-configmap.yaml` | Unified config (paths, params) | - |
| `05-llama-webui.yaml` | WebUI Deployment (GPU) | ConfigMap, PVC |
| `06-training-job.yaml` | Training Job (GPU) | ConfigMap, PVC, Secret |
| `07-vllm-inference.yaml` | vLLM Deployment (GPU) | ConfigMap, PVC |
| `09-merge-model-job.yaml` | LoRA merge Job (GPU) | ConfigMap, PVC |

**GPU Node Selector:** All GPU workloads use `nodeSelector: nvidia.com/gpu: "true"`

## Configuration (Unified ConfigMap)

All config in `k8s/04-configmap.yaml`:

| Variable | Description | Used by |
|----------|-------------|---------|
| `BASE_MODEL_PATH` | Base model on NFS | Training, Merge |
| `LORA_OUTPUT_PATH` | LoRA adapter output | Training, Merge |
| `MERGED_MODEL_PATH` | Merged model path | Merge, Inference |
| `DATASET_PATH` | Training datasets | Training |
| `FINETUNING_TYPE` | lora/qlora/full | Training |
| `LORA_RANK` | LoRA rank (8-64) | Training |
| `SERVED_MODEL_NAME` | Model name in API | Inference |
| `MAX_MODEL_LEN` | vLLM context length | Inference |
| `TENSOR_PARALLEL_SIZE` | Multi-GPU setting | Inference |

## Workflow

1. **Prepare**: Models and datasets already on NFS (no HuggingFace download)
2. **Deploy base**: `./deploy.sh base`
3. **Train**: Via WebUI (`./ui.sh webui`) or CLI (`./train.sh`)
4. **Merge**: `kubectl apply -f k8s/09-merge-model-job.yaml`
5. **Inference**: `./deploy.sh inference`

## Important Notes

### Models Are User's Own
Models are pre-loaded on NFS storage. There is **no HuggingFace download job**. Configure paths in ConfigMap.

### vLLM Service Name
The K8s Service is named `llm-inference` (NOT `vllm`). This prevents env var conflicts - vLLM uses `VLLM_` prefix, and K8s auto-creates env vars from service names. See: https://docs.vllm.ai/en/stable/configuration/env_vars/

### NFS Storage Structure
```
/storage/
├── models/
│   ├── base-model/      # Pre-loaded base model
│   └── merged-model/    # Output from merge job
├── output/
│   └── lora-adapter/    # Output from training
└── data/                # Training datasets
```

### Dataset Format
JSON array with instruction/input/output:
```json
[{"instruction": "Question", "input": "", "output": "Answer"}]
```
