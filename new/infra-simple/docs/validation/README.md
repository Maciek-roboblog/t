# Walidacja Fine-Tuningu LLM - Kompletny Przewodnik

## Spis treści

1. [Wprowadzenie](#wprowadzenie)
2. [Architektura walidacji](#architektura-walidacji)
3. [Dokumenty szczegółowe](#dokumenty-szczegółowe)
4. [Quick Start](#quick-start)
5. [Integracja z obecną infrastrukturą](#integracja-z-obecną-infrastrukturą)

---

## Wprowadzenie

### Cel dokumentacji

Ten folder zawiera kompletny przewodnik dotyczący **walidowalności** (validation & reproducibility) procesu fine-tuningu modeli LLM przy użyciu LLaMA-Factory. Dokumentacja opisuje:

- **Metryki** - jakie metryki monitorować i jak je interpretować
- **Śledzenie eksperymentów** - integracja z MLflow
- **Reprodukowalność** - jak zapewnić powtarzalność wyników
- **Wersjonowanie** - zarządzanie datasetami i modelami
- **Ewaluacja** - pipeline do oceny jakości modeli

### Dlaczego walidacja jest kluczowa?

> **Diagram:** Zobacz [problem-solution.puml](diagrams/problem-solution.puml) - porównanie podejścia bez i z walidacją.

**Problem bez walidacji:**
- Nie wiadomo który model jest lepszy
- Nie można odtworzyć najlepszego wyniku
- Brak możliwości debugowania
- Brak audytu dla compliance

**Rozwiązanie z walidacją:**
- Porównanie wyników między eksperymentami
- Pełna reprodukowalność
- Śledzenie liniażu modeli
- Compliance i audyt

---

## Architektura walidacji

### Komponenty systemu walidacji

> **Diagram:** Zobacz [mlflow-integration.puml](diagrams/mlflow-integration.puml) - architektura integracji z MLflow.

**Komponenty:**

| Warstwa | Komponenty |
|---------|------------|
| **MLflow Server** | Tracking Server (metryki, parametry, tagi), Model Registry (wersje, stage), Artifact Store (checkpointy, datasety) |
| **Kubernetes** | Training Job (report_to: mlflow), WebUI (LlamaBoard), Eval Job (benchmarki) |
| **Storage** | NFS: /storage/models/, /storage/output/, /storage/data/ |

### Przepływ danych walidacji

> **Diagram:** Zobacz [validation-flow.puml](diagrams/validation-flow.puml) - pełny przepływ walidacji end-to-end.

**Etapy walidacji:**

| Etap | Czynności |
|------|-----------|
| **1. Przed treningiem** | Przygotuj dataset (train/val/test split), wersjonuj dataset, zdefiniuj baseline, ustaw seed |
| **2. Podczas treningu** | Training Loss → MLflow, Validation Loss → MLflow, Learning Rate, checkpointy → NFS |
| **3. Po treningu** | Ewaluacja na test set, benchmark MMLU, porównanie z baseline, tag najlepszego modelu |
| **4. Przed deploymentem** | A/B testing, human evaluation, safety checks, promocja do Production |

---

## Dokumenty szczegółowe

| Dokument | Opis |
|----------|------|
| [01-metrics-monitoring.md](01-metrics-monitoring.md) | Metryki treningu, MLflow, dashboardy |
| [02-evaluation-pipeline.md](02-evaluation-pipeline.md) | Pipeline ewaluacji, benchmarki, test set |
| [03-reproducibility-checklist.md](03-reproducibility-checklist.md) | Checklist reprodukowalności |
| [04-dataset-versioning.md](04-dataset-versioning.md) | Wersjonowanie datasetów |
| [05-hyperparameter-tracking.md](05-hyperparameter-tracking.md) | Śledzenie hiperparametrów |

### Diagramy PlantUML

| Diagram | Opis |
|---------|------|
| [validation-flow.puml](diagrams/validation-flow.puml) | Główny przepływ walidacji end-to-end |
| [mlflow-integration.puml](diagrams/mlflow-integration.puml) | Architektura integracji z MLflow |
| [dataset-versioning.puml](diagrams/dataset-versioning.puml) | Strategia wersjonowania datasetów |
| [evaluation-pipeline.puml](diagrams/evaluation-pipeline.puml) | Pipeline ewaluacji modeli |
| [reproducibility-components.puml](diagrams/reproducibility-components.puml) | Komponenty reprodukowalności |
| [hyperparameter-search.puml](diagrams/hyperparameter-search.puml) | Strategia przeszukiwania hiperparametrów |

**Renderowanie diagramów:**
```bash
# Zainstaluj PlantUML
brew install plantuml  # macOS
apt install plantuml   # Ubuntu

# Renderuj wszystkie diagramy
plantuml docs/validation/diagrams/*.puml

# Lub użyj online: https://www.plantuml.com/plantuml/
```

---

## Quick Start

### Minimalna konfiguracja walidacji

Dodaj do swojego `train.yaml`:

```yaml
### Walidacja podstawowa
val_size: 0.1                    # 10% danych na walidację
eval_strategy: steps             # Ewaluacja co N kroków
eval_steps: 100                  # Co 100 kroków
per_device_eval_batch_size: 1    # Batch size dla ewaluacji

### Logowanie do MLflow
report_to: mlflow                # Automatyczne raportowanie
logging_steps: 10                # Loguj co 10 kroków
save_steps: 500                  # Zapisuj checkpoint co 500 kroków

### Reprodukowalność
seed: 42                         # Stały seed
```

### Uruchomienie z walidacją

```bash
# 1. Ustaw MLflow URI (już skonfigurowane w Secret)
export MLFLOW_TRACKING_URI="http://mlflow.mlflow.svc.cluster.local:5000"

# 2. Uruchom trening
./scripts/train.sh my-experiment-v1

# 3. Sprawdź metryki w MLflow
./scripts/ui.sh mlflow
# Otwórz http://localhost:5000
```

---

## Integracja z obecną infrastrukturą

### Obecna konfiguracja (k8s/04-configmap.yaml)

Nasza infrastruktura już wspiera podstawową walidację:

```yaml
# Już skonfigurowane:
FINETUNING_TYPE: "lora"
LORA_RANK: "8"
LORA_ALPHA: "16"
LEARNING_RATE: "1.0e-4"
NUM_EPOCHS: "3"
```

### Rozszerzenie o walidację

Aby włączyć pełną walidację, dodaj do ConfigMap lub train.yaml:

```yaml
# Dodaj do 04-configmap.yaml:
VAL_SIZE: "0.1"
EVAL_STEPS: "100"
LOGGING_STEPS: "10"
SAVE_STEPS: "500"
SEED: "42"
```

### Aktualizacja Job (k8s/06-training-job.yaml)

Obecny job już używa `report_to: mlflow`. Rozszerz konfigurację:

```yaml
# W sekcji args training job:
cat > /tmp/train.yaml << EOF
# ... istniejąca konfiguracja ...

# WALIDACJA (dodaj):
val_size: ${VAL_SIZE:-0.1}
eval_strategy: steps
eval_steps: ${EVAL_STEPS:-100}
per_device_eval_batch_size: 1
logging_steps: ${LOGGING_STEPS:-10}
save_steps: ${SAVE_STEPS:-500}
seed: ${SEED:-42}
report_to: mlflow
EOF
```

---

## Źródła i referencje

### LLaMA-Factory
- [GitHub - hiyouga/LLaMA-Factory](https://github.com/hiyouga/LLaMA-Factory)
- [LLaMA-Factory Evaluation Docs](https://www.aidoczh.com/llamafactory/en/getting_started/eval.html)
- [ACL 2024 Paper](https://aclanthology.org/2024.acl-demos.38/)

### MLflow
- [MLflow Tracking](https://mlflow.org/docs/latest/ml/tracking/)
- [MLflow LLM Tracking](https://mlflow.org/docs/latest/llms/llm-tracking/index.html)

### Best Practices
- [Fine-tuning LLMs Guide 2025 - SuperAnnotate](https://www.superannotate.com/blog/llm-fine-tuning)
- [LoRA Hyperparameters Guide - Unsloth](https://docs.unsloth.ai/get-started/fine-tuning-llms-guide/lora-hyperparameters-guide)
- [LLM Evaluation Metrics - DagsHub](https://dagshub.com/blog/llm-evaluation-metrics/)
- [Data Versioning Best Practices](https://labelyourdata.com/articles/machine-learning/data-versioning)
- [Practical Tips for LoRA - Sebastian Raschka](https://magazine.sebastianraschka.com/p/practical-tips-for-finetuning-llms)

---

*Dokumentacja walidacji fine-tuningu LLM - LLaMA-Factory Infrastructure*
