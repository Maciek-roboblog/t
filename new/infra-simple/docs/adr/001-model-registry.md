# ADR-001: Model Registry - Udostępnianie modeli dla vLLM

## Status
**Propozycja** - do wyboru przez zespół

## Kontekst

LLaMA-Factory (trening) i vLLM (inference) to **oddzielne usługi**. Po treningu/merge model musi być dostępny dla zewnętrznego serwera vLLM.

```
LLaMA-Factory          ???           vLLM (zewnętrzny)
     │                  │                  │
     │  export model    │   load model     │
     └─────────────────►│◄─────────────────┘
                    Model Storage
```

**Rozmiary modeli (2025):**
- 7B model: ~14 GB (FP16)
- 13B model: ~26 GB (FP16)
- 70B model: ~140 GB (FP16)

## Opcje

---

### Opcja 1: NFS/PVC (Shared Storage)

```
LLaMA-Factory  ──────►  NFS (/storage/models/merged)  ◄──────  vLLM
                           ReadWriteMany
```

**Ocena:**

| Aspekt | Ocena | Uwagi |
|--------|-------|-------|
| **Złożoność** | ⭐ Niska | Już mamy PVC |
| **Latencja** | ⭐⭐⭐ Natychmiastowa | Brak download |
| **Wersjonowanie** | ❌ Brak | Nadpisywanie |
| **Multi-cluster** | ❌ Nie | Tylko lokalny klaster |
| **Koszt** | ⭐⭐ | NFS: $500-1500/TB/miesiąc (szybki) |
| **Skalowalność** | ⭐ | Bottleneck przy wielu nodes (~2.5 GB/s) |

**Implementacja (obecna):**
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: llama-storage
spec:
  accessModes: [ReadWriteMany]
  storageClassName: nfs-client
  resources:
    requests:
      storage: 200Gi
```

**vLLM:**
```bash
vllm serve --model /storage/models/merged-model
```

**Kiedy wybrać:**
- ✅ Pojedynczy klaster
- ✅ Szybki development
- ✅ Modele < 50GB
- ❌ Wiele instancji vLLM (bottleneck)
- ❌ Potrzeba wersjonowania

**Źródła:**
- [NFS to JuiceFS: LLM Storage Platform](https://juicefs.com/en/blog/user-stories/ai-storage-platform-large-language-model-training-inference)
- [Kubernetes Storage Solutions 2025](https://thamizhelango.medium.com/the-complete-guide-to-kubernetes-storage-solutions-navigating-block-file-and-object-storage-in-1b81312a75f1)

---

### Opcja 2: Object Storage (GCS/S3)

```
LLaMA-Factory  ──►  GCS/S3 Bucket  ◄──  vLLM
                   gs://models/
```

**Ocena:**

| Aspekt | Ocena | Uwagi |
|--------|-------|-------|
| **Złożoność** | ⭐⭐ Średnia | Upload/download logic |
| **Latencja** | ⭐ | Download: minuty dla dużych modeli |
| **Wersjonowanie** | ⭐⭐ | Object versioning |
| **Multi-cluster** | ⭐⭐⭐ | Globalny dostęp |
| **Koszt** | ⭐⭐⭐ | ~$20/TB/miesiąc + egress |
| **Skalowalność** | ⭐⭐⭐ | 10x lepsza niż NFS przy scale-out |

**Three-Tier Architecture (best practice 2025):**
```
┌─────────────────────────────────────────────────────────────┐
│  HOT TIER     │  Local NVMe cache    │  ~2.5 GB/s/node    │
├───────────────┼──────────────────────┼────────────────────┤
│  WARM TIER    │  Distributed cache   │  P2P między nodes  │
├───────────────┼──────────────────────┼────────────────────┤
│  COLD TIER    │  Object Storage      │  GCS/S3 backup     │
└─────────────────────────────────────────────────────────────┘
```

**Implementacja (LLaMA-Factory export):**
```python
# Po treningu/merge - upload do GCS
from google.cloud import storage

def upload_model_to_gcs(local_path, bucket_name, model_name, version):
    client = storage.Client()
    bucket = client.bucket(bucket_name)

    for file in os.listdir(local_path):
        blob = bucket.blob(f"{model_name}/{version}/{file}")
        blob.upload_from_filename(f"{local_path}/{file}")

    print(f"Model uploaded to gs://{bucket_name}/{model_name}/{version}/")
```

**vLLM:**
```bash
# Opcja A: vLLM pobiera bezpośrednio (wolne)
vllm serve --model gs://models-bucket/merged-model/v1

# Opcja B: Pobierz do cache + serwuj (zalecane)
gsutil -m cp -r gs://models-bucket/merged-model/v1 /cache/model/
vllm serve --model /cache/model
```

**Kiedy wybrać:**
- ✅ Multi-cluster / multi-region
- ✅ Disaster recovery
- ✅ Wiele instancji vLLM (scale-out)
- ✅ Archiwizacja wersji
- ❌ Latencja krytyczna (cold start)

**Źródła:**
- [Three-Tier Storage Architecture for LLM Inference](https://nilesh-agarwal.com/three-tier-storage-architecture-for-fast-llm-inference-in-the-cloud/)
- [High-Performance Model Weight Storage](https://nilesh-agarwal.com/storage-in-cloud-for-llms-2/)

---

### Opcja 3: MLflow Model Registry

```
LLaMA-Factory  ──►  MLflow Registry  ◄──  vLLM
                    models:/merged/Production
```

**Ocena:**

| Aspekt | Ocena | Uwagi |
|--------|-------|-------|
| **Złożoność** | ⭐⭐⭐ | MLflow setup + integracja |
| **Latencja** | ⭐⭐ | Download z artifact store |
| **Wersjonowanie** | ⭐⭐⭐ | Pełne: v1, v2, stages |
| **Multi-cluster** | ⭐⭐⭐ | Przez artifact store |
| **Koszt** | ⭐⭐ | MLflow infra + artifact storage |
| **Audyt/Lineage** | ⭐⭐⭐ | Pełny tracking |

**MLflow Model Lifecycle:**
```
┌─────────────────────────────────────────────────────────────┐
│                    MLflow Model Registry                     │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   Model: llama-finetuned                                    │
│   │                                                          │
│   ├── Version 1 (Archived)                                  │
│   │   └── Metrics: loss=0.45, dataset=v1                    │
│   │                                                          │
│   ├── Version 2 (Staging)                                   │
│   │   └── Metrics: loss=0.32, dataset=v2                    │
│   │                                                          │
│   └── Version 3 (Production) ◄── Alias: @production        │
│       └── Metrics: loss=0.28, dataset=v3                    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**Implementacja (LLaMA-Factory):**
```python
import mlflow
from mlflow.tracking import MlflowClient

# Po treningu
with mlflow.start_run(run_name="finetune-llama3-v3"):
    # Log parametrów
    mlflow.log_params({
        "base_model": "llama-3-8b",
        "lora_rank": 8,
        "learning_rate": 2e-4,
        "dataset": "customer_service_v3"
    })

    # Log metryk
    mlflow.log_metrics({
        "final_loss": 0.28,
        "eval_accuracy": 0.92
    })

    # Rejestracja modelu
    mlflow.transformers.log_model(
        transformers_model={"model": model, "tokenizer": tokenizer},
        artifact_path="model",
        registered_model_name="llama-finetuned"
    )

# Promuj do Production
client = MlflowClient()
client.set_registered_model_alias(
    name="llama-finetuned",
    alias="production",
    version=3
)
```

**vLLM load z MLflow:**
```python
import mlflow

# Pobierz model z MLflow
model_uri = "models:/llama-finetuned@production"
local_path = mlflow.artifacts.download_artifacts(model_uri)

# Serwuj przez vLLM
# vllm serve --model {local_path}
```

**Kiedy wybrać:**
- ✅ Już macie MLflow
- ✅ Potrzeba pełnego wersjonowania
- ✅ Audyt i compliance
- ✅ A/B testing modeli
- ✅ Rollback do poprzedniej wersji
- ❌ Prosta infrastruktura

**Źródła:**
- [MLflow Model Registry](https://mlflow.org/docs/latest/ml/model-registry/)
- [MLflow LLM/GenAI](https://mlflow.org/docs/latest/llms/index.html)
- [AI/ML on Kubernetes: MLflow + KServe + vLLM](https://dzone.com/articles/ai-ml-kubernetes-mlflow-kserve-vllm)

---

## Porównanie szczegółowe

| Kryterium | NFS/PVC | Object Storage | MLflow Registry |
|-----------|---------|----------------|-----------------|
| Setup time | Minuty | Godziny | Dni |
| Latencja (model load) | ~0s | Minuty | Minuty |
| Throughput (50 nodes) | ~2.5 GB/s | ~25 GB/s | Zależy od backend |
| Wersjonowanie | ❌ | Object versioning | Pełne |
| Rollback | Manual | Manual | 1-click |
| Lineage | ❌ | ❌ | ✅ |
| A/B testing | ❌ | Manual | ✅ |
| Koszt (100TB) | ~$50-150k/rok | ~$2.4k/rok | ~$3k/rok + infra |
| **Już mamy** | ✅ PVC | ❓ GCS? | ✅ MLflow |

---

## Architektura hybrydowa (rekomendowana dla produkcji)

```
┌─────────────────────────────────────────────────────────────────┐
│                         PRODUCTION                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   LLaMA-Factory                                                 │
│        │                                                         │
│        │ 1. Train + Merge                                       │
│        ▼                                                         │
│   ┌─────────────┐     2. Register      ┌─────────────────────┐ │
│   │ NFS (temp)  │ ──────────────────► │   MLflow Registry    │ │
│   │ /storage/   │                      │   (wersjonowanie)    │ │
│   └─────────────┘                      │   + GCS artifacts    │ │
│                                         └──────────┬──────────┘ │
│                                                     │            │
│                              3. Promote to Production            │
│                                                     ▼            │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │                    vLLM Cluster                          │   │
│   │  ┌─────────┐  ┌─────────┐  ┌─────────┐                 │   │
│   │  │ Node 1  │  │ Node 2  │  │ Node 3  │  ...            │   │
│   │  │ NVMe    │  │ NVMe    │  │ NVMe    │  (local cache)  │   │
│   │  └─────────┘  └─────────┘  └─────────┘                 │   │
│   │       │             │             │                      │   │
│   │       └─────────────┴─────────────┘                      │   │
│   │              4. Download from MLflow/GCS                 │   │
│   │                 (cache locally on NVMe)                  │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Rekomendacja

### Dla prostego startu: **Opcja 1 (NFS/PVC)**
- Pojedynczy klaster
- < 3 instancje vLLM
- Nie potrzeba wersjonowania

### Dla produkcji z audytem: **Opcja 3 (MLflow Registry)**
- Już macie MLflow ✅
- Pełne wersjonowanie i rollback
- Compliance i audyt
- A/B testing modeli

### Dla scale-out: **Hybrydowa (MLflow + Object Storage)**
- MLflow jako registry (metadata, wersje)
- GCS/S3 jako artifact backend
- Local NVMe cache na vLLM nodes

---

## Decyzja

**[DO UZUPEŁNIENIA]**

Wybrana opcja: ________________

Uzasadnienie: ________________

---

## Konsekwencje

*Uzupełnić po decyzji*

---

## Źródła

- [MLflow Model Registry](https://mlflow.org/docs/latest/ml/model-registry/)
- [Three-Tier Storage Architecture for LLM Inference](https://nilesh-agarwal.com/three-tier-storage-architecture-for-fast-llm-inference-in-the-cloud/)
- [NFS to JuiceFS: LLM Storage Platform](https://juicefs.com/en/blog/user-stories/ai-storage-platform-large-language-model-training-inference)
- [AI/ML on Kubernetes with vLLM](https://dzone.com/articles/ai-ml-kubernetes-mlflow-kserve-vllm)
- [llm-d: Kubernetes-native LLM Inference](https://github.com/llm-d/llm-d)

---

*ADR utworzony: 2025-11-25*
