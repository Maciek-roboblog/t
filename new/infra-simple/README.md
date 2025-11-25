# LLaMA-Factory - Proste wdrożenie

Minimalna konfiguracja do wdrożenia LLaMA-Factory na istniejącym klastrze Kubernetes.

## Wymagania

- Klaster Kubernetes z GPU (NVIDIA)
- `kubectl` skonfigurowany
- `docker` do budowania obrazów
- Istniejący MLFlow (opcjonalnie)
- GCR/Artifact Registry do obrazów

## Struktura

```
infra-simple/
├── docker/
│   ├── Dockerfile.train     # Obraz do treningu + WebUI
│   └── Dockerfile.api       # Obraz do inference (vLLM)
├── k8s/
│   ├── 01-namespace.yaml    # Namespace
│   ├── 02-secrets.yaml      # MLFlow config, HF token
│   ├── 03-pvc.yaml          # Storage na modele
│   ├── 04-configmap.yaml    # Konfiguracja treningu
│   ├── 05-llama-webui.yaml  # WebUI deployment
│   ├── 06-training-job.yaml # Job treningowy
│   ├── 07-vllm-inference.yaml # vLLM inference
│   ├── 08-download-model-job.yaml # Pobranie modelu
│   └── 09-merge-model-job.yaml    # Merge LoRA
├── scripts/
│   ├── build.sh             # Budowa obrazów
│   ├── deploy.sh            # Wdrożenie
│   ├── train.sh             # Uruchomienie treningu
│   ├── ui.sh                # Port-forward do UI
│   ├── status.sh            # Status wdrożenia
│   └── cleanup.sh           # Czyszczenie
└── README.md
```

## Szybki start

### 1. Ustaw zmienne

```bash
export PROJECT_ID="twoj-projekt-gcp"
```

### 2. Zbuduj obrazy

```bash
cd scripts
./build.sh v1.0.0
```

### 3. Skonfiguruj secrets

Edytuj `k8s/02-secrets.yaml`:
- `MLFLOW_TRACKING_URI` - adres twojego MLFlow
- `token` - token HuggingFace (opcjonalnie)

### 4. Wdróż

```bash
./deploy.sh all
```

### 5. Otwórz WebUI

```bash
./ui.sh webui
# -> http://localhost:7860
```

## Workflow

```
┌─────────────────────────────────────────────────────────────┐
│                     WORKFLOW TRENINGU                        │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. PRZYGOTOWANIE                                           │
│     └─> ./deploy.sh base                                    │
│     └─> Pobierz model: kubectl apply -f 08-download-...     │
│     └─> Wgraj dataset do PVC                                │
│                                                              │
│  2. FINE-TUNING (wybierz jeden sposób)                      │
│     ├─> WebUI: ./ui.sh webui -> konfiguruj w przeglądarce  │
│     └─> CLI:   ./train.sh                                   │
│                                                              │
│  3. MERGE (po treningu LoRA)                                │
│     └─> kubectl apply -f 09-merge-model-job.yaml            │
│                                                              │
│  4. INFERENCE                                                │
│     └─> ./deploy.sh inference                               │
│     └─> ./ui.sh inference -> http://localhost:8000          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Komendy

| Komenda | Opis |
|---------|------|
| `./build.sh [tag]` | Buduj obrazy Docker |
| `./deploy.sh all` | Wdróż wszystko |
| `./deploy.sh base` | Tylko namespace, PVC, secrets |
| `./deploy.sh webui` | Tylko WebUI |
| `./deploy.sh inference` | Tylko vLLM |
| `./train.sh` | Uruchom job treningowy |
| `./ui.sh webui` | Port-forward do WebUI |
| `./ui.sh inference` | Port-forward do vLLM API |
| `./status.sh` | Pokaż status |
| `./cleanup.sh jobs` | Usuń zakończone joby |

## Testowanie API

Po wdrożeniu inference:

```bash
# Port-forward
./ui.sh inference &

# Test
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama-finetuned",
    "messages": [{"role": "user", "content": "Cześć!"}],
    "max_tokens": 100
  }'
```

## Konfiguracja treningu

Edytuj `k8s/04-configmap.yaml` lub użyj WebUI:

```yaml
# Główne parametry
model_name_or_path: /models/base-model  # Ścieżka do modelu
finetuning_type: lora                    # lora, qlora, full
lora_rank: 8                             # Rank LoRA (8-64)

# Dataset
dataset: my_dataset                       # Nazwa datasetu
template: llama3                          # Template promptów

# Training
per_device_train_batch_size: 1
num_train_epochs: 3
learning_rate: 1.0e-4
```

## Wgrywanie danych

Dataset musi być w formacie JSON:

```json
[
  {
    "instruction": "Pytanie",
    "input": "",
    "output": "Odpowiedź"
  }
]
```

Wgraj do PVC:

```bash
# Utwórz pod pomocniczy
kubectl -n llm-training run uploader --image=busybox --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"uploader","image":"busybox","command":["sleep","3600"],"volumeMounts":[{"name":"data","mountPath":"/data"}]}],"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"llama-storage"}}]}}'

# Skopiuj dane
kubectl -n llm-training cp ./my_dataset.json uploader:/data/data/my_dataset.json

# Usuń pod
kubectl -n llm-training delete pod uploader
```

## Troubleshooting

### Pod nie startuje (GPU)

```bash
# Sprawdź eventy
kubectl -n llm-training describe pod <nazwa>

# Sprawdź GPU nodes
kubectl get nodes -l nvidia.com/gpu
```

### OOM (Out of Memory)

Zmniejsz w configmap:
- `per_device_train_batch_size: 1`
- `cutoff_len: 1024`
- Lub użyj `finetuning_type: qlora`

### vLLM nie startuje

```bash
# Logi
kubectl -n llm-training logs deploy/vllm-inference

# Sprawdź czy model istnieje
kubectl -n llm-training exec -it deploy/llama-webui -- ls -la /models/
```

## Integracja z Jenkins

Przykładowy pipeline:

```groovy
pipeline {
    agent any
    environment {
        PROJECT_ID = 'your-project'
    }
    stages {
        stage('Build') {
            steps {
                sh './scripts/build.sh ${BUILD_NUMBER}'
            }
        }
        stage('Train') {
            steps {
                sh './scripts/train.sh train-${BUILD_NUMBER}'
                sh 'kubectl -n llm-training wait --for=condition=complete job/train-${BUILD_NUMBER} --timeout=3600s'
            }
        }
        stage('Deploy') {
            steps {
                sh './scripts/deploy.sh inference'
            }
        }
    }
}
```

## Dokumentacja

W folderze `docs/` znajduje sie szczegolowa dokumentacja:

| Dokument | Opis |
|----------|------|
| [DOKUMENTACJA.md](docs/DOKUMENTACJA.md) | Kompletny przewodnik wdrozeniowy |
| [PARAMETRY-LORA.md](docs/PARAMETRY-LORA.md) | Szczegoly konfiguracji LoRA/QLoRA |
| [FORMATY-DANYCH.md](docs/FORMATY-DANYCH.md) | Przygotowanie datasetow (Alpaca, ShareGPT) |
| [VLLM-KONFIGURACJA.md](docs/VLLM-KONFIGURACJA.md) | Optymalizacja vLLM inference |
| [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Rozwiazywanie problemow |

## Zrodla

- [LLaMA-Factory](https://github.com/hiyouga/LLaMA-Factory)
- [vLLM Kubernetes](https://docs.vllm.ai/en/latest/deployment/k8s/)
- [LLaMA-Factory K8s PR](https://github.com/hiyouga/LLaMA-Factory/pull/8861)
