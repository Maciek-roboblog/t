# LLaMA-Factory + vLLM Basic Setup

Uproszczona infrastruktura do fine-tuningu LLM dla **pojedynczego GPU** z k3s/minikube.

## Architektura

```
┌─────────────────────────────────────────────────────────────┐
│                      k3s / minikube                          │
│  ┌─────────────────┐   ┌─────────────────┐                  │
│  │  LLaMA-Factory  │   │     vLLM        │                  │
│  │     WebUI       │   │   Inference     │                  │
│  │   (training)    │   │   (serving)     │                  │
│  │   Port: 7860    │   │   Port: 8000    │                  │
│  └────────┬────────┘   └────────┬────────┘                  │
│           │                     │                            │
│           └──────────┬──────────┘                            │
│                      ▼                                       │
│  ┌─────────────────────────────────────────┐                │
│  │           Shared Storage (PVC)          │                │
│  │  /storage/models  /storage/output       │                │
│  └─────────────────────────────────────────┘                │
│                      │                                       │
│  ┌─────────────────────────────────────────┐                │
│  │              MLflow                      │ ← tracking    │
│  │           (optional)                     │                │
│  └─────────────────────────────────────────┘                │
└─────────────────────────────────────────────────────────────┘
```

## Wymagania

- **Hardware**: 1x GPU NVIDIA (min. 8GB VRAM dla małych modeli, 24GB+ dla 7B)
- **OS**: Ubuntu 22.04+ / Debian 12+
- **Software**:
  - NVIDIA Driver 535+
  - NVIDIA Container Toolkit
  - k3s lub minikube

## Szybki start (k3s)

```bash
# 1. Instalacja k3s z GPU
./scripts/setup-k3s.sh

# 2. Deploy całości
./scripts/deploy.sh all

# 3. Dostęp do WebUI
./scripts/ui.sh webui    # http://localhost:7860

# 4. Dostęp do vLLM API
./scripts/ui.sh vllm     # http://localhost:8000
```

## GPU Time-Slicing (pojedyncze GPU)

Ten setup używa **NVIDIA GPU time-slicing** aby umożliwić współdzielenie jednego GPU między:
- LLaMA-Factory (training) - wymaga GPU
- vLLM (inference) - wymaga GPU

**Uwaga**: Time-slicing nie zapewnia izolacji pamięci! Przy jednoczesnym treningu i inference:
- Trenuj małe modele (≤7B) lub używaj QLoRA
- Inference rób na osobnym modelu lub w przerwach treningu

## Tracking eksperymentów

LLaMA-Factory wspiera:
- **LlamaBoard** (wbudowany) - podgląd w WebUI
- **MLflow** - pełne logowanie eksperymentów
- **TensorBoard** - wykresy
- **Weights & Biases** - chmurowy tracking

### MLflow (opcjonalny)

```bash
# Uruchom MLflow lokalnie
mlflow server --host 0.0.0.0 --port 5000

# Lub w k3s
kubectl apply -f k8s/optional/mlflow.yaml
./scripts/ui.sh mlflow   # http://localhost:5000
```

## Multi-user

LlamaBoard (WebUI) jest **single-user** - jedna sesja treningu na raz.

Dla wielu użytkowników:
1. **Separate deployments** - każdy user własny pod (z GPU time-slicing)
2. **Job queue** - użyj 06-training-job.yaml jako szablonu
3. **MLflow** - wszyscy użytkownicy mogą śledzić eksperymenty

Zobacz: [docs/MULTI-USER.md](docs/MULTI-USER.md)

## Skalowanie

| Scenariusz | Rozwiązanie |
|------------|-------------|
| Więcej GPU | Dodaj nody, usuń time-slicing |
| Więcej userów | Osobne pody + job queue |
| Większe modele | Tensor parallelism (vLLM) |
| Production | Użyj pełnej wersji infra-simple |

## Pliki

```
infra-basic/
├── k8s/
│   ├── 00-gpu-timeslice.yaml    # GPU time-slicing config
│   ├── 01-namespace.yaml
│   ├── 02-storage.yaml          # hostPath (bez NFS)
│   ├── 03-configmap.yaml
│   ├── 04-llama-webui.yaml      # LLaMA-Factory + LlamaBoard
│   ├── 05-vllm.yaml             # vLLM inference server
│   └── 06-training-job.yaml     # Template dla batch training
├── scripts/
│   ├── setup-k3s.sh             # Instalacja k3s z GPU
│   ├── setup-minikube.sh        # Alternatywa: minikube
│   ├── deploy.sh                # Deploy manifests
│   └── ui.sh                    # Port-forward helper
├── docker/
│   └── Dockerfile               # Unified image
└── docs/
    ├── MULTI-USER.md
    └── SCALING.md
```

## Źródła

- [LLaMA-Factory](https://github.com/hiyouga/LLaMA-Factory) - fine-tuning framework
- [vLLM Production Stack](https://github.com/vllm-project/production-stack) - K8s deployment
- [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/gpu-sharing.html) - time-slicing
- [K3s GPU Guide](https://github.com/UntouchedWagons/K3S-NVidia) - k3s + NVIDIA
