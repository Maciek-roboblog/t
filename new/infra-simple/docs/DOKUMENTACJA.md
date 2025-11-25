# LLaMA-Factory - Kompletna Dokumentacja Wdrozeniowa

## Spis tresci

1. [Wprowadzenie](#wprowadzenie)
2. [Architektura rozwiazania](#architektura-rozwiazania)
3. [Wymagania systemowe](#wymagania-systemowe)
4. [Struktura projektu](#struktura-projektu)
5. [Komponenty systemu](#komponenty-systemu)
6. [Proces wdrozenia](#proces-wdrozenia)
7. [Workflow treningu](#workflow-treningu)
8. [Integracja z MLFlow](#integracja-z-mlflow)
9. [Bezpieczenstwo](#bezpieczenstwo)
10. [Monitorowanie](#monitorowanie)

---

## Wprowadzenie

### Czym jest LLaMA-Factory?

LLaMA-Factory to zintegrowana platforma do fine-tuningu duzych modeli jezykowych (LLM). Umozliwia:

- **Fine-tuning** roznych architektur LLM (LLaMA, Mistral, Qwen, itd.)
- **Rozne metody treningu**: LoRA, QLoRA, Full Fine-tuning
- **WebUI** do konfiguracji i monitorowania
- **Eksport modeli** do formatu gotowego do inference

### Cel tego wdrozenia

Niniejsza konfiguracja zapewnia:

1. **Prostote** - minimalna ilosc narzedzi i zaleznosci
2. **Integracje z istniejaca infrastruktura** - MLFlow, Jenkins, istniejacy klaster K8s
3. **Gotowe do produkcji** - vLLM jako silnik inference z OpenAI-compatible API
4. **Powtarzalnosc** - wszystko jako Infrastructure as Code

---

## Architektura rozwiazania

### Diagram ogolny

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           KLASTER KUBERNETES (GKE)                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                     NAMESPACE: llm-training                           │   │
│  │                                                                        │   │
│  │   ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐  │   │
│  │   │  LLaMA-Factory  │    │   Training Job  │    │  vLLM Inference │  │   │
│  │   │     WebUI       │    │    (GPU Pod)    │    │    (GPU Pod)    │  │   │
│  │   │   Port: 7860    │    │                 │    │   Port: 8000    │  │   │
│  │   └────────┬────────┘    └────────┬────────┘    └────────┬────────┘  │   │
│  │            │                      │                      │            │   │
│  │            └──────────────────────┴──────────────────────┘            │   │
│  │                                   │                                    │   │
│  │                         ┌─────────┴─────────┐                         │   │
│  │                         │   PVC: llama-     │                         │   │
│  │                         │     storage       │                         │   │
│  │                         │    (100Gi SSD)    │                         │   │
│  │                         └───────────────────┘                         │   │
│  │                                                                        │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
                │                    │                    │
                ▼                    ▼                    ▼
         ┌──────────┐         ┌──────────┐         ┌──────────┐
         │  MLFlow  │         │  Jenkins │         │   GCR    │
         │ (metrics)│         │ (CI/CD)  │         │ (images) │
         └──────────┘         └──────────┘         └──────────┘
```

### Przeplyw danych

```
┌──────────────────────────────────────────────────────────────────────────┐
│                         PRZEPLYW DANYCH                                   │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                           │
│   1. PRZYGOTOWANIE                                                        │
│      ┌─────────┐         ┌─────────┐         ┌─────────┐                │
│      │HuggingFace│ ───▶ │ Download │ ───▶ │  PVC:   │                │
│      │  / MLFlow │       │   Job    │       │ /models │                │
│      └─────────┘         └─────────┘         └─────────┘                │
│                                                                           │
│   2. FINE-TUNING                                                          │
│      ┌─────────┐         ┌─────────┐         ┌─────────┐                │
│      │  PVC:   │ ───▶ │ Training │ ───▶ │  PVC:   │                │
│      │ /models │       │   Job    │       │ /output │                │
│      │ /data   │       │  + GPU   │       │ (LoRA)  │                │
│      └─────────┘         └─────────┘         └─────────┘                │
│                                   │                                      │
│                                   ▼                                      │
│                            ┌─────────┐                                  │
│                            │ MLFlow  │                                  │
│                            │(metryki)│                                  │
│                            └─────────┘                                  │
│                                                                           │
│   3. MERGE (jesli LoRA)                                                  │
│      ┌─────────┐         ┌─────────┐         ┌─────────┐                │
│      │  Base   │ ───▶ │  Merge  │ ───▶ │ Merged  │                │
│      │ + LoRA  │       │   Job   │       │  Model  │                │
│      └─────────┘         └─────────┘         └─────────┘                │
│                                                                           │
│   4. INFERENCE                                                            │
│      ┌─────────┐         ┌─────────┐         ┌─────────┐                │
│      │ Merged  │ ───▶ │  vLLM   │ ───▶ │OpenAI   │                │
│      │  Model  │       │  Server │       │  API    │                │
│      └─────────┘         └─────────┘         └─────────┘                │
│                                                                           │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## Wymagania systemowe

### Klaster Kubernetes

| Komponent | Minimalne | Rekomendowane |
|-----------|-----------|---------------|
| Wersja K8s | 1.25+ | 1.28+ |
| GPU Nodes | 1x NVIDIA T4 | 1x NVIDIA A100 40GB |
| CPU Nodes | 4 vCPU, 16GB RAM | 8 vCPU, 32GB RAM |
| Storage | 100GB SSD | 500GB SSD |

### Wymagania GPU

**Dla treningu (w zaleznosci od modelu):**

| Model | LoRA | QLoRA | Full Fine-tune |
|-------|------|-------|----------------|
| 7B params | 1x A100 40GB | 1x T4 16GB | 4x A100 80GB |
| 13B params | 2x A100 40GB | 1x A100 40GB | 8x A100 80GB |
| 70B params | 4x A100 80GB | 2x A100 40GB | 16x A100 80GB |

**Dla inference (vLLM):**

| Model | Minimalne GPU | Rekomendowane |
|-------|---------------|---------------|
| 7B params | 1x T4 16GB | 1x A100 40GB |
| 13B params | 1x A100 40GB | 1x A100 80GB |
| 70B params | 2x A100 80GB | 4x A100 80GB |

### Zewnetrzne zaleznosci

- **Google Cloud Platform** - GKE, GCR/Artifact Registry
- **MLFlow** - serwer do sledzenia eksperymentow (opcjonalnie)
- **Jenkins** - do automatyzacji CI/CD (opcjonalnie)
- **kubectl** - skonfigurowany z dostepem do klastra
- **Docker** - do budowy obrazow

---

## Struktura projektu

```
infra-simple/
├── docker/                      # Obrazy Docker
│   ├── Dockerfile.train         # Obraz treningowy (LLaMA-Factory + WebUI)
│   └── Dockerfile.api           # Obraz inference (vLLM)
│
├── k8s/                         # Manifesty Kubernetes (numerowane)
│   ├── 01-namespace.yaml        # Namespace llm-training
│   ├── 02-secrets.yaml          # Secrety (MLFlow, HF token)
│   ├── 03-pvc.yaml              # PersistentVolumeClaim (100Gi)
│   ├── 04-configmap.yaml        # Konfiguracja treningu
│   ├── 05-llama-webui.yaml      # Deployment WebUI
│   ├── 06-training-job.yaml     # Job treningowy
│   ├── 07-vllm-inference.yaml   # Deployment vLLM
│   ├── 08-download-model-job.yaml  # Job pobierania modelu
│   └── 09-merge-model-job.yaml  # Job mergowania LoRA
│
├── scripts/                     # Skrypty pomocnicze
│   ├── build.sh                 # Budowa i push obrazow
│   ├── deploy.sh                # Wdrozenie na K8s
│   ├── train.sh                 # Uruchomienie treningu
│   ├── ui.sh                    # Port-forward do UI
│   ├── status.sh                # Status wdrozenia
│   └── cleanup.sh               # Czyszczenie zasobow
│
├── docs/                        # Dokumentacja
│   ├── DOKUMENTACJA.md          # Ten plik
│   ├── PARAMETRY-LORA.md        # Szczegoly LoRA/QLoRA
│   ├── FORMATY-DANYCH.md        # Formaty datasetow
│   ├── VLLM-KONFIGURACJA.md     # Konfiguracja vLLM
│   └── TROUBLESHOOTING.md       # Rozwiazywanie problemow
│
└── README.md                    # Szybki start
```

---

## Komponenty systemu

### 1. Obrazy Docker

#### Dockerfile.train

Obraz do treningu i WebUI oparty na Debian 12:

```dockerfile
FROM debian:12
# Python 3.11 + PyTorch 2.2 + CUDA 11.8
# transformers 4.37, datasets 2.17, accelerate, peft
# LLaMA-Factory 0.9.3, MLFlow 2.10
```

**Zawartosc:**
- LLaMA-Factory z WebUI (`llamafactory-cli webui`)
- Wsparcie dla treningu LoRA/QLoRA/Full
- Integracja z MLFlow
- Narzedzia CLI (`llamafactory-cli train`, `export`)

#### Dockerfile.api

Obraz do inference oparty na Debian 12:

```dockerfile
FROM debian:12
# Python 3.11 + PyTorch 2.2 + CUDA 11.8
# vLLM 0.4.0, transformers 4.37
# LLaMA-Factory (do merge), MLFlow
```

**Zawartosc:**
- vLLM server z OpenAI-compatible API
- Wsparcie dla duzych modeli
- PagedAttention dla efektywnego inference

### 2. Manifesty Kubernetes

#### 01-namespace.yaml

Tworzy dedykowany namespace `llm-training`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: llm-training
  labels:
    app: llama-factory
```

#### 02-secrets.yaml

Przechowuje wrazliwe dane:

```yaml
# MLFlow configuration
mlflow-config:
  MLFLOW_TRACKING_URI: http://mlflow.mlflow.svc:5000

# HuggingFace token (dla gated models)
hf-token:
  token: hf_xxx...
```

#### 03-pvc.yaml

Storage na modele, dane i outputy:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: llama-storage
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 100Gi
  storageClassName: standard-rwo  # GKE SSD
```

**Struktura na PVC:**
```
/
├── models/           # Modele bazowe i zmergowane
│   ├── base-model/   # Model bazowy (np. LLaMA-3-8B)
│   └── merged-model/ # Po merge LoRA
├── output/           # Outputy treningu
│   └── lora-model/   # Adaptery LoRA
└── data/             # Datasety
    └── my_dataset.json
```

#### 04-configmap.yaml

Konfiguracja treningu (szczegoly w PARAMETRY-LORA.md):

```yaml
data:
  train.yaml: |
    model_name_or_path: /models/base-model
    finetuning_type: lora
    lora_rank: 8
    # ... pelna konfiguracja
```

#### 05-llama-webui.yaml

Deployment WebUI do interaktywnej konfiguracji:

- Port: 7860
- GPU: 1x (dla podgladu/testow)
- Dostep przez port-forward

#### 06-training-job.yaml

Job treningowy:

- Typ: Kubernetes Job (jednorazowe uruchomienie)
- GPU: 1x (konfigurowalne)
- Automatyczna rejestracja w MLFlow
- TTL: 24h po zakonczeniu

#### 07-vllm-inference.yaml

Deployment serwera inference:

- vLLM z OpenAI-compatible API
- Port: 8000
- Health checks (liveness/readiness)
- Shared memory dla vLLM (8Gi)

#### 08-download-model-job.yaml

Job do pobierania modelu bazowego:

- Z HuggingFace (z tokenem)
- Lub z MLFlow (jesli zarejestrowany)

#### 09-merge-model-job.yaml

Job do mergowania LoRA z modelem bazowym:

- Uzywa `llamafactory-cli export`
- Rejestruje wynik w MLFlow

### 3. Skrypty

| Skrypt | Opis | Uzycie |
|--------|------|--------|
| `build.sh` | Buduje i pushuje obrazy Docker | `./build.sh v1.0.0` |
| `deploy.sh` | Wdraza manifesty K8s | `./deploy.sh all|base|webui|inference` |
| `train.sh` | Uruchamia job treningowy | `./train.sh [job-name]` |
| `ui.sh` | Port-forward do UI | `./ui.sh webui|inference|mlflow` |
| `status.sh` | Pokazuje status wdrozenia | `./status.sh` |
| `cleanup.sh` | Czysci zasoby | `./cleanup.sh all|jobs|inference` |

---

## Proces wdrozenia

### Krok 1: Przygotowanie srodowiska

```bash
# 1. Sklonuj repozytorium
cd infra-simple

# 2. Ustaw zmienne
export PROJECT_ID="twoj-projekt-gcp"

# 3. Sprawdz polaczenie z klastrem
kubectl cluster-info
kubectl get nodes -l "nvidia.com/gpu"
```

### Krok 2: Budowa obrazow

```bash
cd scripts
./build.sh v1.0.0
```

**Co robi skrypt:**
1. Autoryzuje Docker z GCR
2. Buduje `llama-factory-train:v1.0.0`
3. Buduje `llama-factory-api:v1.0.0`
4. Pushuje do `eu.gcr.io/${PROJECT_ID}/`

### Krok 3: Konfiguracja secrets

Edytuj `k8s/02-secrets.yaml`:

```yaml
# MLFlow - ustaw prawdziwy adres
MLFLOW_TRACKING_URI: http://mlflow.mlflow.svc:5000

# HuggingFace token - wymagany dla gated models (LLaMA 3, etc.)
# Uzyskaj na: https://huggingface.co/settings/tokens
token: hf_xxxxxxxxxxxxxxxxxx
```

### Krok 4: Wdrozenie bazy

```bash
./deploy.sh base
```

**Tworzy:**
- Namespace `llm-training`
- Secrets (MLFlow, HF token)
- PVC (100Gi storage)
- ConfigMap z konfiguracją treningu

### Krok 5: Pobranie modelu bazowego

```bash
# Edytuj 08-download-model-job.yaml - wybierz zrodlo
kubectl apply -f ../k8s/08-download-model-job.yaml

# Sledz postep
kubectl -n llm-training logs -f job/download-model
```

### Krok 6: Wgranie datasetu

```bash
# Utworz pod pomocniczy
kubectl -n llm-training run uploader --image=busybox \
  --restart=Never \
  --overrides='{"spec":{"containers":[{
    "name":"uploader",
    "image":"busybox",
    "command":["sleep","3600"],
    "volumeMounts":[{"name":"data","mountPath":"/data"}]
  }],"volumes":[{
    "name":"data",
    "persistentVolumeClaim":{"claimName":"llama-storage"}
  }]}}'

# Skopiuj dane
kubectl -n llm-training cp ./my_dataset.json uploader:/data/data/my_dataset.json

# Usun pod
kubectl -n llm-training delete pod uploader
```

### Krok 7: Wdrozenie WebUI (opcjonalnie)

```bash
./deploy.sh webui
./ui.sh webui
# Otworz http://localhost:7860
```

### Krok 8: Trening

**Metoda A - przez WebUI:**
1. Otworz http://localhost:7860
2. Skonfiguruj trening w interfejsie
3. Kliknij "Start"

**Metoda B - przez CLI:**
```bash
# Edytuj k8s/04-configmap.yaml z parametrami
./train.sh my-training-job

# Sledz postep
kubectl -n llm-training logs -f job/my-training-job
```

### Krok 9: Merge LoRA (jesli uzywales LoRA)

```bash
kubectl apply -f ../k8s/09-merge-model-job.yaml
kubectl -n llm-training logs -f job/merge-lora
```

### Krok 10: Wdrozenie inference

```bash
./deploy.sh inference
./ui.sh inference
# API dostepne na http://localhost:8000
```

### Krok 11: Test API

```bash
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama-finetuned",
    "messages": [{"role": "user", "content": "Czesc!"}],
    "max_tokens": 100
  }'
```

---

## Workflow treningu

### Diagram workflow

```
┌────────────────────────────────────────────────────────────────────────────┐
│                           WORKFLOW TRENINGU                                 │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐ │
│   │PRZYGOT. │───▶│ TRENING │───▶│ EWALUA- │───▶│  MERGE  │───▶│INFERENCE│ │
│   │         │    │         │    │  CJA    │    │ (LoRA)  │    │         │ │
│   └─────────┘    └─────────┘    └─────────┘    └─────────┘    └─────────┘ │
│       │              │              │              │              │        │
│       ▼              ▼              ▼              ▼              ▼        │
│   ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐ │
│   │- Model  │    │- LoRA   │    │- MLFlow │    │- llamafa│    │- vLLM   │ │
│   │  bazowy │    │- QLoRA  │    │  metrics│    │  ctory  │    │  server │ │
│   │- Dataset│    │- Full   │    │- logs   │    │  export │    │- OpenAI │ │
│   │- Config │    │         │    │         │    │         │    │  API    │ │
│   └─────────┘    └─────────┘    └─────────┘    └─────────┘    └─────────┘ │
│                                                                             │
└────────────────────────────────────────────────────────────────────────────┘
```

### Typy fine-tuningu

| Metoda | Pamiec GPU | Jakosc | Czas | Przypadek uzycia |
|--------|------------|--------|------|------------------|
| **LoRA** | Niska (~8GB dla 7B) | Dobra | Szybki | Wiekszość przypadkow |
| **QLoRA** | Bardzo niska (~4GB) | Dobra | Sredni | Ograniczone zasoby |
| **Full** | Bardzo wysoka | Najlepsza | Dlugi | Maksymalna jakosc |

### Wybor metody

```
                    ┌─────────────────────────────┐
                    │    Czy masz duzo GPU RAM?   │
                    └─────────────┬───────────────┘
                                  │
                    ┌─────────────┴───────────────┐
                    │                             │
                    ▼                             ▼
              ┌─────────┐                   ┌─────────┐
              │   TAK   │                   │   NIE   │
              │ (>40GB) │                   │ (<24GB) │
              └────┬────┘                   └────┬────┘
                   │                              │
         ┌─────────┴─────────┐           ┌───────┴───────┐
         │                   │           │               │
         ▼                   ▼           ▼               ▼
   ┌──────────┐       ┌──────────┐ ┌──────────┐   ┌──────────┐
   │   Full   │       │   LoRA   │ │  QLoRA   │   │   LoRA   │
   │Fine-tune │       │ (szybki) │ │(4-bit)   │   │(zmniejsz │
   └──────────┘       └──────────┘ └──────────┘   │  model)  │
                                                   └──────────┘
```

---

## Integracja z MLFlow

### Konfiguracja

MLFlow jest uzywany do:
1. Sledzenia eksperymentow (metryki, parametry)
2. Przechowywania artefaktow (adaptery LoRA, modele)
3. Rejestru modeli (wersjonowanie)

### Automatyczne logowanie

Trening automatycznie loguje do MLFlow:

```yaml
# W train.yaml
report_to: mlflow
```

**Logowane dane:**
- Parametry treningu (lr, batch_size, epochs, etc.)
- Metryki (loss, eval_loss)
- Artefakty (adapter LoRA)

### Struktura eksperymentow

```
MLFlow
└── Experiments
    └── llama-finetune
        ├── Run: lora-model-20240115
        │   ├── Parameters
        │   │   ├── lora_rank: 8
        │   │   ├── learning_rate: 1e-4
        │   │   └── ...
        │   ├── Metrics
        │   │   ├── loss: [1.5, 1.2, 0.9, ...]
        │   │   └── eval_loss: [1.4, 1.1, 0.85, ...]
        │   └── Artifacts
        │       └── model/
        │           ├── adapter_config.json
        │           └── adapter_model.bin
        │
        └── Run: merged-model-20240115
            └── Artifacts
                └── model/
                    ├── config.json
                    ├── model.safetensors
                    └── tokenizer.json
```

### Rejestracja modelu

Po merge, model jest rejestrowany:

```python
mlflow.register_model(
    'runs:/<run_id>/model',
    'llama-finetuned'
)
```

**Wersjonowanie:**
- `llama-finetuned/1` - pierwsza wersja
- `llama-finetuned/2` - po re-treningu
- `llama-finetuned/Production` - alias do aktualnej wersji produkcyjnej

---

## Bezpieczenstwo

### Secrets management

```yaml
# NIGDY nie commituj prawdziwych wartosci!
# Uzyj:
# 1. kubectl create secret generic
# 2. External Secrets Operator
# 3. HashiCorp Vault
```

### Sieci

```
┌─────────────────────────────────────────────────────────────┐
│                    BEZPIECZENSTWO SIECI                      │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   ┌─────────────┐                         ┌─────────────┐   │
│   │   Uzytkow.  │                         │   vLLM      │   │
│   │             │──── port-forward ──────▶│   :8000     │   │
│   └─────────────┘                         └─────────────┘   │
│         │                                        │          │
│         │ (lokalne)                              │          │
│         ▼                                        ▼          │
│   ┌─────────────┐                         ┌─────────────┐   │
│   │   WebUI     │                         │   Gateway   │   │
│   │   :7860     │                         │  (produkcja)│   │
│   └─────────────┘                         └─────────────┘   │
│                                                              │
│   ZALECENIA:                                                │
│   - Uzyj port-forward dla dostepu deweloperskiego          │
│   - W produkcji: Gateway z autentykacja                    │
│   - NetworkPolicy dla izolacji namespace                   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Workload Identity (GKE)

Dla dostepu do GCP bez kluczy:

```yaml
# ServiceAccount z Workload Identity
apiVersion: v1
kind: ServiceAccount
metadata:
  name: llama-factory
  annotations:
    iam.gke.io/gcp-service-account: llama@project.iam.gserviceaccount.com
```

---

## Monitorowanie

### Status wdrozenia

```bash
./status.sh
```

Pokazuje:
- Pods w namespace
- Services
- Jobs (trwające/zakonczone)
- PVC usage
- GPU nodes

### Logi

```bash
# Logi WebUI
kubectl -n llm-training logs -f deploy/llama-webui

# Logi treningu
kubectl -n llm-training logs -f job/<nazwa-joba>

# Logi vLLM
kubectl -n llm-training logs -f deploy/vllm-inference
```

### Metryki GPU

```bash
# Na nodzie GPU
nvidia-smi

# Przez kubectl
kubectl -n llm-training exec -it <pod> -- nvidia-smi
```

### Alerty (zalecane)

Skonfiguruj alerty dla:
- GPU memory > 90%
- Training job failed
- vLLM health check failed
- PVC usage > 80%

---

## Dalsze kroki

1. **Zapoznaj sie z dodatkowymi dokumentami:**
   - [PARAMETRY-LORA.md](PARAMETRY-LORA.md) - szczegolowa konfiguracja treningu
   - [FORMATY-DANYCH.md](FORMATY-DANYCH.md) - przygotowanie datasetow
   - [VLLM-KONFIGURACJA.md](VLLM-KONFIGURACJA.md) - optymalizacja inference
   - [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - rozwiazywanie problemow

2. **Automatyzacja z Jenkins:**
   - Zobacz przyklad pipeline w README.md

3. **Skalowanie:**
   - Multi-GPU training (tensor parallelism)
   - Wiele replik vLLM

---

*Dokumentacja wygenerowana dla LLaMA-Factory infra-simple v1.0*
