# Checklist Reprodukowalności Fine-Tuningu

## Spis treści

1. [Dlaczego reprodukowalność?](#dlaczego-reprodukowalność)
2. [Kompletny checklist](#kompletny-checklist)
3. [Konfiguracja seedów](#konfiguracja-seedów)
4. [Wersjonowanie środowiska](#wersjonowanie-środowiska)
5. [Dokumentacja eksperymentu](#dokumentacja-eksperymentu)
6. [Audyt i compliance](#audyt-i-compliance)

---

## Dlaczego reprodukowalność?

### Problem nieodtwarzalnych wyników

> **Diagram:** Zobacz [problem-solution.puml](diagrams/problem-solution.puml) - dlaczego walidacja i reprodukowalność są kluczowe.

**Typowe scenariusze problemów:**

| Scenariusz | Problem |
|------------|---------|
| "U mnie działało" | Badacz A osiągnął 95% accuracy, badacz B tylko 82% - nie wiadomo co było inne |
| Model degradation | Model w produkcji degraduje, ale nie można odtworzyć oryginalnego treningu |
| Audyt compliance | Audytor pyta o dane treningowe - zespół nie pamięta szczegółów sprzed 6 miesięcy |

### Korzyści z reprodukowalności

> **Diagram:** Zobacz [reproducibility-components.puml](diagrams/reproducibility-components.puml) - komponenty stacku reprodukowalności.

| Obszar | Korzyści |
|--------|----------|
| **Debugowanie** | Łatwe znalezienie błędów, porównanie working vs broken konfiguracji |
| **Iteracja** | Pewność, że poprawa wynika ze zmiany nie z losowości |
| **Współpraca** | Każdy może odtworzyć wyniki, łatwe przekazanie projektu |
| **Produkcja** | Pewność deploymentu, możliwość rollback |
| **Compliance** | Pełny audit trail, zgodność z GDPR/AI Act |

---

## Kompletny checklist

### Przed treningiem

**DANE:**
- [ ] Dataset zapisany w wersjonowanym storage
- [ ] Hash/checksum datasetu obliczony i zapisany
- [ ] Train/val/test split wykonany deterministycznie (seed!)
- [ ] Preprocessing udokumentowany (skrypty w repo)
- [ ] Data augmentation (jeśli stosowana) z seedem

**MODEL BAZOWY:**
- [ ] Dokładna wersja/commit modelu bazowego zapisana
- [ ] Źródło modelu (HuggingFace hub, lokalna kopia)
- [ ] Hash wag modelu (opcjonalnie)

**ŚRODOWISKO:**
- [ ] Wersje bibliotek zapisane (requirements.txt / pip freeze)
- [ ] Wersja CUDA i driver
- [ ] Typ GPU
- [ ] Docker image tag

**KONFIGURACJA:**
- [ ] Wszystkie hiperparametry w pliku YAML
- [ ] Seed globalny ustawiony
- [ ] Konfiguracja w repozytorium git

### Podczas treningu

**LOGOWANIE:**
- [ ] MLflow tracking włączony
- [ ] Parametry logowane automatycznie
- [ ] Metryki co N kroków (logging_steps)
- [ ] Validation metrics co M kroków (eval_steps)

**CHECKPOINTING:**
- [ ] Checkpointy zapisywane regularnie (save_steps)
- [ ] Limit checkpointów ustawiony (save_total_limit)
- [ ] Najlepszy checkpoint oznaczony

**ARTEFAKTY:**
- [ ] Konfiguracja treningu zapisana (training_args.json)
- [ ] Logi treningu zachowane
- [ ] GPU memory/utilization monitorowane

### Po treningu

**MODEL:**
- [ ] Adapter/model zapisany
- [ ] Hash wag modelu obliczony
- [ ] Model zarejestrowany w MLflow Model Registry
- [ ] Metadata (data treningu, czas, metryki) dołączone

**EWALUACJA:**
- [ ] Ewaluacja na test set wykonana
- [ ] Wyniki zapisane w MLflow
- [ ] Porównanie z baseline

**DOKUMENTACJA:**
- [ ] Experiment notes zapisane
- [ ] Znane problemy/obserwacje udokumentowane
- [ ] Rekomendacje dla następnych eksperymentów

**ARCHIWIZACJA:**
- [ ] Wszystkie artefakty w jednym miejscu
- [ ] Backup na zewnętrzny storage (opcjonalnie)
- [ ] Retention policy określona

---

## Konfiguracja seedów

### Seed w LLaMA-Factory

```yaml
# train.yaml - KOMPLETNA konfiguracja seedów

### GLOBAL SEED
seed: 42                    # Główny seed dla PyTorch, numpy, random

### DATA SEED
data_seed: 42               # Seed dla shufflingu danych
                            # (oddzielny dla reprodukowalności data loading)

### Opcjonalnie w kodzie Python:
# torch.backends.cudnn.deterministic = True
# torch.backends.cudnn.benchmark = False
```

### Szczegóły działania seedów

> **Diagram:** Zobacz [seed-anatomy.puml](diagrams/seed-anatomy.puml) - anatomia konfiguracji seedów.

**`seed: 42` wpływa na:**
- `torch.manual_seed(42)` - PyTorch CPU
- `torch.cuda.manual_seed_all(42)` - PyTorch GPU
- `numpy.random.seed(42)` - NumPy
- `random.seed(42)` - Python random
- `transformers.set_seed(42)` - HuggingFace

**`data_seed: 42` wpływa na:**
- DataLoader shuffle seed - kolejność batchów

**UWAGA:** Nawet z seedem wyniki mogą się różnić z powodu różnych wersji CUDA, GPU i non-deterministic operations.

**Dla PEŁNEJ reprodukowalności (wolniejsze):**
```python
torch.backends.cudnn.deterministic = True
torch.backends.cudnn.benchmark = False
torch.use_deterministic_algorithms(True)
```

### Konfiguracja w ConfigMap

```yaml
# k8s/04-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: llm-config
  namespace: llm-training
data:
  # ... inne zmienne ...

  # REPRODUCIBILITY
  SEED: "42"
  DATA_SEED: "42"
  CUDNN_DETERMINISTIC: "true"
```

### Użycie w Training Job

```yaml
# k8s/06-training-job.yaml (fragment)
args:
- |
  # Ustaw deterministyczne operacje CUDA
  if [ "${CUDNN_DETERMINISTIC}" = "true" ]; then
    export CUBLAS_WORKSPACE_CONFIG=:4096:8
  fi

  cat > /tmp/train.yaml << EOF
  # ... konfiguracja ...
  seed: ${SEED:-42}
  data_seed: ${DATA_SEED:-42}
  EOF
```

---

## Wersjonowanie środowiska

### Docker Image - best practices

```dockerfile
# Dockerfile - PRZYKŁAD Z PINOWANYMI WERSJAMI

FROM python:3.10.14-slim-bullseye

# Pinuj wersje systemowe
RUN apt-get update && apt-get install -y \
    git=1:2.30.2-1+deb11u2 \
    && rm -rf /var/lib/apt/lists/*

# Pinuj wersje Python packages
COPY requirements.txt /tmp/
RUN pip install --no-cache-dir -r /tmp/requirements.txt

# METADATA dla reprodukowalności
LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.revision="${GIT_COMMIT}"
LABEL org.opencontainers.image.version="${VERSION}"
```

### requirements.txt z dokładnymi wersjami

```txt
# requirements.txt - PINOWANE WERSJE

# Core
torch==2.1.2+cu118
transformers==4.36.2
peft==0.7.1
accelerate==0.26.1
datasets==2.16.1

# LLaMA-Factory
llamafactory==0.9.3

# MLflow
mlflow==2.10.0

# Utils
numpy==1.24.3
scipy==1.11.4
```

### Generowanie requirements z działającego środowiska

```bash
# Zapisz dokładne wersje po udanym treningu
pip freeze > requirements-frozen.txt

# Lub z conda
conda list --export > environment.yml
```

### Wersjonowanie w MLflow

```python
# Automatyczne logowanie wersji (w custom callback lub skrypcie)
import mlflow
import torch
import transformers
import peft
import sys

def log_environment():
    """Zaloguj wersje bibliotek do MLflow."""
    mlflow.log_params({
        "python_version": sys.version,
        "torch_version": torch.__version__,
        "cuda_version": torch.version.cuda,
        "transformers_version": transformers.__version__,
        "peft_version": peft.__version__,
    })

    # Zaloguj pełny requirements jako artefakt
    import subprocess
    reqs = subprocess.check_output(['pip', 'freeze']).decode()
    with open('/tmp/requirements.txt', 'w') as f:
        f.write(reqs)
    mlflow.log_artifact('/tmp/requirements.txt')
```

---

## Dokumentacja eksperymentu

### Template dokumentacji eksperymentu

```markdown
# Experiment: [NAZWA]

## Metadata
- **Date**: 2025-01-25
- **Author**: [Imię]
- **MLflow Run ID**: abc123def456
- **Git Commit**: 7890abc

## Objective
[Co chcieliśmy osiągnąć?]

## Configuration

### Model
- Base model: `/storage/models/llama-3-8b`
- Finetuning type: LoRA
- LoRA rank: 16
- LoRA alpha: 32

### Training
- Learning rate: 2e-4
- Batch size: 1 (effective: 8)
- Epochs: 3
- Seed: 42

### Data
- Dataset: `company_qa_v2.json`
- Dataset hash: `a1b2c3d4`
- Train/Val/Test split: 80/10/10
- Total samples: 10,000

## Results

### Metrics
| Metric | Value |
|--------|-------|
| Final train loss | 0.35 |
| Final val loss | 0.38 |
| Test exact match | 0.82 |

### Observations
- [Obserwacje z treningu]
- [Problemy napotkane]

## Conclusions
[Wnioski i rekomendacje]

## Artifacts
- Model: `/storage/output/lora-exp-001`
- Logs: MLflow run abc123def456
- Config: `experiments/exp-001/train.yaml`
```

### Struktura katalogów eksperymentów

```
/storage/
├── experiments/
│   ├── exp-001/
│   │   ├── train.yaml           # Konfiguracja
│   │   ├── README.md            # Dokumentacja
│   │   ├── requirements.txt     # Wersje bibliotek
│   │   └── results/
│   │       ├── metrics.json
│   │       └── eval_results.json
│   │
│   ├── exp-002/
│   │   └── ...
│   │
│   └── baseline/                # Baseline do porównań
│       ├── train.yaml
│       └── results/
│
├── models/
│   ├── base-model/
│   └── merged-model/
│
├── output/
│   ├── lora-exp-001/
│   └── lora-exp-002/
│
└── data/
    ├── train_data.json
    ├── test_data.json           # Oddzielny test set!
    └── data_manifest.json       # Metadata datasetów
```

### Data manifest

```json
{
  "datasets": {
    "train_data_v2": {
      "file": "train_data.json",
      "created": "2025-01-20T10:00:00Z",
      "samples": 8000,
      "hash_sha256": "a1b2c3d4e5f6...",
      "description": "Company Q&A dataset, cleaned",
      "preprocessing": "scripts/preprocess_qa.py",
      "source": "internal_db_export_2025-01"
    },
    "test_data_v2": {
      "file": "test_data.json",
      "created": "2025-01-20T10:00:00Z",
      "samples": 1000,
      "hash_sha256": "f6e5d4c3b2a1...",
      "description": "Holdout test set - DO NOT USE FOR TRAINING",
      "split_seed": 42
    }
  }
}
```

---

## Audyt i compliance

### Audit trail w MLflow

**Co MLflow zapisuje automatycznie:**
- Timestamp rozpoczęcia/zakończenia
- User ID (jeśli skonfigurowany)
- Git commit (jeśli w repo)
- Wszystkie parametry
- Wszystkie metryki z timestampami
- Artefakty (model, config)

**Dodaj dla compliance:**
- Dataset hash/version
- Data governance tags
- Model approval status
- Human reviewer (jeśli wymagany)

### Tagi dla compliance

```python
# compliance_tags.py
import mlflow

def add_compliance_tags(run_id: str,
                        dataset_hash: str,
                        data_governance: str,
                        approved_by: str = None):
    """Dodaj tagi compliance do MLflow run."""

    with mlflow.start_run(run_id=run_id):
        mlflow.set_tags({
            # Data lineage
            "compliance.dataset_hash": dataset_hash,
            "compliance.data_governance": data_governance,  # "internal", "pii_removed", etc.

            # Model governance
            "compliance.model_stage": "development",
            "compliance.requires_review": "true",

            # Approval (po review)
            "compliance.approved_by": approved_by or "pending",
            "compliance.approval_date": "" if not approved_by else datetime.now().isoformat(),
        })
```

### Checklist compliance (GDPR / AI Act)

**DATA GOVERNANCE:**
- [ ] Dane treningowe zweryfikowane pod kątem PII
- [ ] Zgoda na użycie danych (jeśli wymagana)
- [ ] Data retention policy określona
- [ ] Prawo do bycia zapomnianym - procedura

**MODEL TRANSPARENCY:**
- [ ] Dokumentacja procesu treningu
- [ ] Znane ograniczenia modelu
- [ ] Intended use cases
- [ ] Known biases (jeśli zbadane)

**TRACEABILITY:**
- [ ] Pełny audit trail w MLflow
- [ ] Możliwość odtworzenia treningu
- [ ] Wersjonowanie modeli
- [ ] Rollback capability

**RISK ASSESSMENT (AI Act High-Risk):**
- [ ] Risk category określona
- [ ] Human oversight mechanisms
- [ ] Accuracy/robustness testing
- [ ] Bias testing

---

## Podsumowanie

### Quick reproducibility config

```yaml
# Minimalny config dla reprodukowalności
# train.yaml

seed: 42
data_seed: 42

report_to: mlflow
logging_steps: 10
save_steps: 500

val_size: 0.1
eval_strategy: steps
eval_steps: 100
```

### Komendy weryfikacji

```bash
# Sprawdź hash datasetu
sha256sum /storage/data/train_data.json

# Sprawdź wersje w kontenerze
kubectl -n llm-training exec -it job/llama-train -- pip freeze | head -20

# Sprawdź seed w logach
kubectl -n llm-training logs job/llama-train | grep -i seed

# Porównaj runs w MLflow
mlflow runs compare --run-ids <id1>,<id2>
```

---

## Źródła

- [PyTorch Reproducibility](https://pytorch.org/docs/stable/notes/randomness.html)
- [HuggingFace Reproducibility](https://huggingface.co/docs/transformers/v4.36.0/en/main_classes/trainer#reproducibility)
- [MLflow Tracking](https://mlflow.org/docs/latest/ml/tracking/)
- [Data Versioning Best Practices](https://labelyourdata.com/articles/machine-learning/data-versioning)
- [EU AI Act Overview](https://digital-strategy.ec.europa.eu/en/policies/regulatory-framework-ai)
