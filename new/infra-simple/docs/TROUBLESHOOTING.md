# Troubleshooting - Rozwiazywanie problemow

## Spis tresci

1. [Problemy z GPU](#problemy-z-gpu)
2. [Problemy z pamiecia (OOM)](#problemy-z-pamiecia-oom)
3. [Problemy z treningiem](#problemy-z-treningiem)
4. [Problemy z vLLM (zewnętrzny)](#problemy-z-vllm-zewnętrzny)
5. [Problemy z Kubernetes](#problemy-z-kubernetes)
6. [Problemy z MLFlow](#problemy-z-mlflow)
7. [Problemy z danymi](#problemy-z-danymi)
8. [Diagnostyka ogolna](#diagnostyka-ogolna)

---

## Problemy z GPU

### Pod nie startuje - brak GPU

**Objaw:**
```
0/3 nodes are available: 3 Insufficient nvidia.com/gpu
```

**Przyczyny i rozwiazania:**

![Troubleshooting GPU](diagrams/troubleshoot-gpu.puml)

**Diagnostyka:**

```bash
# Sprawdz GPU nodes
kubectl get nodes -o json | jq '.items[].status.capacity | select(."nvidia.com/gpu")'

# Sprawdz alokacje GPU
kubectl describe nodes | grep -A5 "Allocated resources"

# Sprawdz eventy poda
kubectl -n llm-training describe pod <nazwa-poda>
```

### CUDA error: device-side assert triggered

**Objaw:**
```
RuntimeError: CUDA error: device-side assert triggered
```

**Rozwiazania:**

1. **Sprawdz kompatybilnosc CUDA:**
```bash
# W podzie
python -c "import torch; print(torch.cuda.is_available()); print(torch.version.cuda)"
```

2. **Zrestartuj pod** (czasem wystarczy):
```bash
kubectl -n llm-training delete pod <nazwa>
```

3. **Sprawdz wersje PyTorch/CUDA:**
```dockerfile
# Dockerfile.train - uzywamy CUDA 11.8
pip install torch==2.2.0 --extra-index-url https://download.pytorch.org/whl/cu118
```

### GPU nie jest widoczne

**Objaw:**
```python
>>> import torch
>>> torch.cuda.is_available()
False
```

**Rozwiazania:**

```bash
# 1. Sprawdz nvidia-smi w podzie
kubectl -n llm-training exec -it <pod> -- nvidia-smi

# 2. Sprawdz CUDA_VISIBLE_DEVICES
kubectl -n llm-training exec -it <pod> -- printenv | grep CUDA

# 3. Sprawdz czy resources.limits zawiera GPU
kubectl -n llm-training get pod <pod> -o yaml | grep -A5 resources

# 4. Upewnij sie ze obraz ma CUDA
kubectl -n llm-training exec -it <pod> -- nvcc --version
```

---

## Problemy z pamiecia (OOM)

### CUDA out of memory

**Objaw:**
```
torch.cuda.OutOfMemoryError: CUDA out of memory. Tried to allocate X GiB
```

**Diagram diagnostyczny:**

![CUDA OOM Troubleshooting](diagrams/troubleshoot-oom.puml)

**Rozwiazania krok po kroku:**

```yaml
# 1. Wlacz QLoRA (jesli LoRA)
quantization_bit: 4

# 2. Zmniejsz batch size
per_device_train_batch_size: 1
gradient_accumulation_steps: 16  # Efektywny batch = 16

# 3. Zmniejsz cutoff_len
cutoff_len: 1024  # Zamiast 2048

# 4. Wlacz gradient checkpointing
gradient_checkpointing: true

# 5. Zmniejsz rank LoRA
lora_rank: 4  # Zamiast 8

# 6. Wylacz niepotrzebne feature'y
flash_attn: null  # Wylacz Flash Attention jesli brak wsparcia
```

**Sprawdzenie zuzycia pamieci:**

```bash
# W trakcie treningu
watch -n 1 'kubectl -n llm-training exec <pod> -- nvidia-smi'

# Lub w pythonie
kubectl -n llm-training exec -it <pod> -- python -c "
import torch
print(f'Allocated: {torch.cuda.memory_allocated()/1e9:.2f} GB')
print(f'Reserved: {torch.cuda.memory_reserved()/1e9:.2f} GB')
"
```

### OOMKilled przez Kubernetes

**Objaw:**
```
State: Terminated
Reason: OOMKilled
Exit Code: 137
```

**Rozwiazania:**

```yaml
# Zwieksz limity pamieci RAM
resources:
  requests:
    memory: "32Gi"
  limits:
    memory: "64Gi"

# Lub zmniejsz wymagania aplikacji
# - mniejszy model
# - mniejszy batch
```

---

## Problemy z treningiem

### Loss = NaN

**Objaw:**
```
Step 100: loss = nan
```

**Przyczyny i rozwiazania:**

| Przyczyna | Rozwiazanie |
|-----------|-------------|
| Za wysoki learning rate | Zmniejsz do 5e-5 lub 1e-5 |
| Overflow w FP16 | Uzyj bf16 (jesli Ampere+) |
| Zle dane | Waliduj dataset |
| Gradient explosion | Dodaj max_grad_norm |

```yaml
# Bezpieczna konfiguracja
learning_rate: 5.0e-5  # Nizszy LR
bf16: true             # Zamiast fp16
max_grad_norm: 1.0     # Gradient clipping
warmup_ratio: 0.1      # Warmup
```

### Trening nie postepuje (loss stoi)

**Objaw:**
```
Step 1: loss = 2.5
Step 100: loss = 2.5
Step 500: loss = 2.5
```

**Rozwiazania:**

```yaml
# 1. Zwieksz learning rate
learning_rate: 2.0e-4  # Wyzszy LR

# 2. Zwieksz lora_rank
lora_rank: 16  # Zamiast 8

# 3. Sprawdz czy dane sie laduja
# Dodaj logi:
logging_steps: 1
```

**Diagnostyka:**

```bash
# Sprawdz czy dane laduja sie poprawnie
kubectl -n llm-training logs job/<job> | grep "Loading dataset"

# Sprawdz gradient norm
kubectl -n llm-training logs job/<job> | grep "grad_norm"
```

### Slow training

**Objaw:** Kazdy step trwa bardzo dlugo.

**Rozwiazania:**

![Przyspieszenie Treningu](diagrams/troubleshoot-training.puml)

---

## Problemy z vLLM (zewnętrzny)

> **UWAGA:** vLLM jest zewnętrzną usługą - NIE wdrażamy go z tego repozytorium.
> Ta sekcja dotyczy problemów z integracją modeli wytrenowanych przez LLaMA-Factory z zewnętrznym serwerem vLLM.

### Model nie jest widoczny dla vLLM

**Objaw:** Zewnętrzny vLLM nie widzi zmergowanego modelu.

**Rozwiazania:**

```bash
# 1. Sprawdz czy model zostal zmergowany
kubectl -n llm-training exec -it deploy/llama-webui -- ls -la /storage/models/merged-model/

# 2. Jesli brak - uruchom merge job
kubectl apply -f k8s/09-merge-model-job.yaml
kubectl -n llm-training logs -f job/merge-lora

# 3. Sprawdz czy vLLM ma dostep do tego samego NFS
# Na serwerze vLLM:
ls -la /storage/models/merged-model/
```

### vLLM zwraca bledne odpowiedzi po fine-tuningu

**Objaw:** Model odpowiada bzdury lub powtarza sie.

**Przyczyny:**

| Przyczyna | Rozwiazanie |
|-----------|-------------|
| Model nie zmergowany | Uruchom merge job |
| Zly template w vLLM | Uzij tego samego template co w treningu |
| LoRA nie zintegrowane | Sprawdz czy uzyto `llamafactory-cli export` |

**Weryfikacja modelu:**

```bash
# Sprawdz czy model ma wszystkie pliki
ls -la /storage/models/merged-model/
# Powinny byc: config.json, tokenizer.json, model*.safetensors

# Sprawdz config.json
cat /storage/models/merged-model/config.json | head -20
```

### Checklist integracji vLLM

![Checklist vLLM](diagrams/vllm-checklist.puml)

| Krok | Weryfikacja |
|------|-------------|
| Trening ukonczony | LoRA adapter w `/storage/output/lora-adapter` |
| Merge job ukonczony | Model w `/storage/models/merged-model` |
| Model kompletny | Pliki: `config.json`, `*.safetensors` |
| vLLM ma dostep | Dostep do NFS `/storage/models/merged-model` |
| Template zgodny | vLLM uzywa tego samego template co trening |
| Trust remote code | `--trust-remote-code` jesli potrzebne |

### Przykladowa konfiguracja vLLM (zewnętrzna)

```bash
# Na zewnętrznym serwerze vLLM
vllm serve /storage/models/merged-model \
  --host 0.0.0.0 \
  --port 8000 \
  --trust-remote-code \
  --gpu-memory-utilization 0.9
```

---

## Problemy z Kubernetes

### PVC nie montuje sie

**Objaw:**
```
Warning  FailedMount  Unable to attach or mount volumes
```

**Rozwiazania:**

```bash
# 1. Sprawdz czy PVC istnieje
kubectl -n llm-training get pvc

# 2. Sprawdz storage class
kubectl get storageclass

# 3. Sprawdz eventy PVC
kubectl -n llm-training describe pvc llama-storage

# 4. Jesli Pending - sprawdz czy storage class pozwala na dynamiczny provisioning
```

### Pod w stanie Pending

**Objaw:**
```
NAME                         READY   STATUS    AGE
llama-webui-xxx              0/1     Pending   10m
```

**Diagnostyka:**

```bash
# Sprawdz eventy
kubectl -n llm-training describe pod <pod>

# Typowe przyczyny:
# - Insufficient cpu/memory/gpu
# - No matching nodes (tolerations/affinity)
# - PVC not bound
```

**Rozwiazania:**

```yaml
# 1. Sprawdz resource requests
resources:
  requests:
    cpu: "2"      # Zmniejsz jesli za duze
    memory: "8Gi"

# 2. Sprawdz tolerations
tolerations:
- key: "nvidia.com/gpu"
  operator: "Exists"
  effect: "NoSchedule"

# 3. Sprawdz node selector
nodeSelector:
  cloud.google.com/gke-accelerator: nvidia-tesla-t4
```

### ImagePullBackOff

**Objaw:**
```
Warning  Failed  Failed to pull image "eu.gcr.io/project/image:tag"
```

**Rozwiazania:**

```bash
# 1. Sprawdz czy obraz istnieje
gcloud container images list --repository=eu.gcr.io/PROJECT_ID

# 2. Sprawdz auth
gcloud auth configure-docker eu.gcr.io

# 3. Sprawdz imagePullSecrets
kubectl -n llm-training get secrets
```

---

## Problemy z MLFlow

### Nie mozna polaczyc z MLFlow

**Objaw:**
```
ConnectionError: HTTPConnectionPool(host='mlflow', port=5000)
```

**Rozwiazania:**

```bash
# 1. Sprawdz czy MLFlow dziala
kubectl -n mlflow get pods

# 2. Sprawdz service
kubectl -n mlflow get svc

# 3. Sprawdz URL w secret
kubectl -n llm-training get secret mlflow-config -o yaml

# 4. Test polaczenia z poda
kubectl -n llm-training exec -it <pod> -- curl http://mlflow.mlflow.svc:5000/health
```

### Artefakty nie zapisuja sie

**Objaw:**
```
mlflow.exceptions.MlflowException: Could not write to artifact store
```

**Rozwiazania:**

```bash
# 1. Sprawdz backend store
kubectl -n mlflow logs deploy/mlflow | grep "artifact"

# 2. Sprawdz permissions (GCS/S3)
gsutil ls gs://mlflow-artifacts/

# 3. Sprawdz Workload Identity
kubectl -n llm-training describe sa llama-factory
```

---

## Problemy z danymi

### Dataset nie laduje sie

**Objaw:**
```
FileNotFoundError: Dataset 'my_dataset' not found
```

**Rozwiazania:**

```bash
# 1. Sprawdz czy plik istnieje
kubectl -n llm-training exec -it deploy/llama-webui -- ls -la /storage/data/

# 2. Sprawdz konfiguracje sciezki w ConfigMap
kubectl -n llm-training get configmap llm-config -o yaml | grep DATASET_PATH

# 3. Upewnij sie ze dataset jest we wlasciwym formacie (JSON)
# Szczegoly w docs/FORMATY-DANYCH.md
```

### Bledy formatu danych

**Objaw:**
```
json.decoder.JSONDecodeError: Expecting value
```

**Rozwiazania:**

```bash
# 1. Waliduj JSON
python -m json.tool my_dataset.json > /dev/null

# 2. Sprawdz encoding
file my_dataset.json
# Powinno byc: UTF-8

# 3. Uzyj walidatora (z FORMATY-DANYCH.md)
python validate_dataset.py my_dataset.json
```

---

## Diagnostyka ogolna

### Komendy diagnostyczne

```bash
# Status wszystkiego
./scripts/status.sh

# Logi wszystkich podow
kubectl -n llm-training logs -l app=llama-webui --tail=100

# Eventy w namespace
kubectl -n llm-training get events --sort-by='.lastTimestamp'

# Resource usage
kubectl -n llm-training top pods

# Describe problematycznego poda
kubectl -n llm-training describe pod <nazwa>
```

### Debug pod

Jesli potrzebujesz interaktywnego debugowania:

```bash
# Utworz debug pod
kubectl -n llm-training run debug --rm -it \
  --image=eu.gcr.io/PROJECT_ID/llama-factory-train:latest \
  --overrides='{
    "spec": {
      "containers": [{
        "name": "debug",
        "image": "eu.gcr.io/PROJECT_ID/llama-factory-train:latest",
        "stdin": true,
        "tty": true,
        "command": ["/bin/bash"],
        "volumeMounts": [{
          "name": "storage",
          "mountPath": "/data"
        }],
        "resources": {
          "limits": {"nvidia.com/gpu": "1"}
        }
      }],
      "volumes": [{
        "name": "storage",
        "persistentVolumeClaim": {"claimName": "llama-storage"}
      }]
    }
  }'
```

### Checklist diagnostyczny

![Checklist Diagnostyczny](diagrams/troubleshoot-checklist.puml)

| Kategoria | Punkt kontrolny | Komenda |
|-----------|-----------------|---------|
| **PODSTAWY** | kubectl połączenie | `kubectl cluster-info` |
| | Namespace istnieje | `kubectl get ns llm-training` |
| | Secrets utworzone | `kubectl -n llm-training get secrets` |
| | PVC jest Bound | `kubectl -n llm-training get pvc` |
| **GPU** | GPU nodes istnieją | `kubectl get nodes -l nvidia.com/gpu` |
| | NVIDIA plugin działa | `kubectl -n kube-system get pods \| grep nvidia` |
| | Pody mają tolerations | Sprawdź spec w YAML |
| | Resources nvidia.com/gpu | Sprawdź limits w YAML |
| **STORAGE** | Model bazowy na PVC | `ls /storage/models/` |
| | Dataset na PVC | `ls /storage/data/` |
| | Ścieżki poprawne | Porównaj z ConfigMap |
| **SIEĆ** | Services utworzone | `kubectl -n llm-training get svc` |
| | Port-forward działa | `./scripts/ui.sh webui` |
| | MLflow dostępny | `./scripts/ui.sh mlflow` |
| **OBRAZY** | Obrazy w registry | `gcloud container images list` |
| | Tag poprawny | Sprawdź w deployment YAML |
| | Auth działa | `gcloud auth configure-docker` |

### Przydatne aliasy

Dodaj do `~/.bashrc`:

```bash
# LLaMA-Factory aliases
alias kllm='kubectl -n llm-training'
alias llm-logs='kubectl -n llm-training logs -f'
alias llm-pods='kubectl -n llm-training get pods -w'
alias llm-status='./scripts/status.sh'

# Szybki dostep
alias llm-webui='kubectl -n llm-training port-forward svc/llama-webui 7860:7860'
# vLLM jest zewnetrzna usluga - nie ma aliasu do port-forward
```

---

## Kontakt i wsparcie

Jesli powyzsze rozwiazania nie pomagaja:

1. **Sprawdz logi** - wiekszość problemow widac w logach
2. **Sprawdz dokumentacje** - LLaMA-Factory, vLLM, Kubernetes
3. **GitHub Issues** - [LLaMA-Factory](https://github.com/hiyouga/LLaMA-Factory/issues), [vLLM](https://github.com/vllm-project/vllm/issues)
4. **Zglos problem** - z pelnym opisem, logami i konfiguracją

---

*Troubleshooting guide dla LLaMA-Factory*
