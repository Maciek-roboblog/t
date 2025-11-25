# Metryki i Monitoring Fine-Tuningu

## Spis treści

1. [Metryki treningu](#metryki-treningu)
2. [Integracja MLflow](#integracja-mlflow)
3. [Konfiguracja logowania](#konfiguracja-logowania)
4. [Dashboard i wizualizacja](#dashboard-i-wizualizacja)
5. [Alerting i progi](#alerting-i-progi)

---

## Metryki treningu

### Kluczowe metryki

#### 1. Training Loss

**Co mierzy:** Jak dobrze model uczy się na danych treningowych.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        TRAINING LOSS                                         │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Loss                                                                       │
│   │                                                                          │
│   │  ██                                                                     │
│   │  ████                                                                   │
│   │    ████                                                                 │
│   │      ████                                                               │
│   │        ██████                                                           │
│   │            ██████████                                                   │
│   │                    ████████████████████████                             │
│   └───────────────────────────────────────────────────────────────► Steps   │
│                                                                              │
│   ✓ PRAWIDŁOWY: Malejący trend, stabilizacja na końcu                       │
│   ✗ PROBLEM: Brak spadku = underfitting, skoki = niestabilność              │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Interpretacja:**
| Wzorzec | Diagnoza | Akcja |
|---------|----------|-------|
| Ciągły spadek | Prawidłowy trening | Kontynuuj |
| Brak spadku | Underfitting | Zwiększ LR lub rank |
| Oscylacje | Niestabilność | Zmniejsz LR |
| NaN/Inf | Błąd numeryczny | Użyj bf16, zmniejsz LR |
| Szybki spadek + plateau | Możliwy overfitting | Sprawdź val_loss |

#### 2. Validation Loss

**Co mierzy:** Jak dobrze model generalizuje na niewidzianych danych.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    TRAINING vs VALIDATION LOSS                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Loss                                                                       │
│   │                                                                          │
│   │  ──── Training Loss                                                     │
│   │  ════ Validation Loss                                                   │
│   │                                                                          │
│   │  ██══                                                                   │
│   │    ██══                                                                 │
│   │      ██════                                                             │
│   │        ████════                                                         │
│   │            ██████══════════                                             │
│   │                  ████████        ═══════════════  ◄── Overfitting!      │
│   │                          ████████████████████████                       │
│   └───────────────────────────────────────────────────────────────► Steps   │
│              │                                                               │
│              └── Optimal stopping point                                      │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Interpretacja:**
| Wzorzec | Diagnoza | Akcja |
|---------|----------|-------|
| train↓ val↓ | Prawidłowy trening | Kontynuuj |
| train↓ val→ | Początek overfittingu | Rozważ early stopping |
| train↓ val↑ | Overfitting | STOP, użyj wcześniejszego checkpointu |
| train→ val→ | Plateau | Zmień LR scheduler lub zakończ |

#### 3. Token Accuracy (opcjonalnie)

**Co mierzy:** Procent poprawnie przewidzianych tokenów.

```yaml
# Włącz w konfiguracji:
compute_accuracy: true
```

**Typowe wartości:**
- Początek: 30-50%
- Po fine-tuningu: 70-90%+ (zależnie od zadania)

#### 4. Perplexity

**Co mierzy:** "Zaskoczenie" modelu - im niższe, tym lepsze.

```
Perplexity = exp(Loss)

Przykład:
- Loss = 2.0 → Perplexity = 7.39
- Loss = 1.0 → Perplexity = 2.72
- Loss = 0.5 → Perplexity = 1.65
```

**Benchmarki:**
| Model/Zadanie | Dobra perplexity |
|---------------|------------------|
| Language modeling | < 20 |
| Domain-specific | < 10 |
| Task-specific fine-tuning | < 5 |

---

## Integracja MLflow

### Architektura integracji

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     MLFLOW INTEGRATION                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌──────────────────────────────────────────────────────────────────┐     │
│   │                      Training Job (K8s)                           │     │
│   │                                                                   │     │
│   │   llamafactory-cli train config.yaml                             │     │
│   │           │                                                       │     │
│   │           │ report_to: mlflow                                    │     │
│   │           ▼                                                       │     │
│   │   ┌───────────────────────────────────────────────────┐          │     │
│   │   │           Transformers Trainer                     │          │     │
│   │   │                                                    │          │     │
│   │   │   on_log() ──────────────────────────────────────┐│          │     │
│   │   │   - loss                                          ││          │     │
│   │   │   - learning_rate                                 ││          │     │
│   │   │   - epoch                                         ││          │     │
│   │   │   - grad_norm                                     ││          │     │
│   │   │                                                    ││          │     │
│   │   │   on_evaluate() ─────────────────────────────────┤│          │     │
│   │   │   - eval_loss                                     ││          │     │
│   │   │   - eval_accuracy (if enabled)                   ││          │     │
│   │   └───────────────────────────────────────────────────┘│          │     │
│   │                                                        │          │     │
│   └────────────────────────────────────────────────────────┼──────────┘     │
│                                                            │                 │
│                                                            │ HTTP API        │
│                                                            ▼                 │
│   ┌────────────────────────────────────────────────────────────────────┐   │
│   │                        MLflow Server                                │   │
│   ├────────────────────────────────────────────────────────────────────┤   │
│   │                                                                     │   │
│   │   Experiment: "llama-finetuning"                                   │   │
│   │   │                                                                 │   │
│   │   ├── Run: "train-20250125-1430"                                   │   │
│   │   │   ├── Parameters:                                              │   │
│   │   │   │   - lora_rank: 8                                           │   │
│   │   │   │   - learning_rate: 1e-4                                    │   │
│   │   │   │   - batch_size: 1                                          │   │
│   │   │   │   - epochs: 3                                              │   │
│   │   │   │                                                             │   │
│   │   │   ├── Metrics (per step):                                      │   │
│   │   │   │   - loss: [2.1, 1.8, 1.5, ...]                             │   │
│   │   │   │   - eval_loss: [1.9, 1.6, ...]                             │   │
│   │   │   │   - learning_rate: [1e-4, 9.5e-5, ...]                     │   │
│   │   │   │                                                             │   │
│   │   │   └── Artifacts:                                               │   │
│   │   │       - model/                                                  │   │
│   │   │       - training_args.json                                     │   │
│   │   │                                                                 │   │
│   │   └── Run: "train-20250126-0900"                                   │   │
│   │       └── ...                                                       │   │
│   │                                                                     │   │
│   └────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Automatycznie logowane metryki

LLaMA-Factory z `report_to: mlflow` automatycznie loguje:

| Metryka | Częstotliwość | Opis |
|---------|---------------|------|
| `loss` | `logging_steps` | Training loss |
| `learning_rate` | `logging_steps` | Aktualny LR |
| `epoch` | `logging_steps` | Numer epoki |
| `grad_norm` | `logging_steps` | Norma gradientów |
| `eval_loss` | `eval_steps` | Validation loss |
| `train_runtime` | Na końcu | Całkowity czas |
| `train_samples_per_second` | Na końcu | Throughput |

### Automatycznie logowane parametry

```python
# Parametry logowane automatycznie:
{
    "model_name_or_path": "/storage/models/base-model",
    "finetuning_type": "lora",
    "lora_rank": 8,
    "lora_alpha": 16,
    "learning_rate": 1e-4,
    "per_device_train_batch_size": 1,
    "gradient_accumulation_steps": 8,
    "num_train_epochs": 3,
    "seed": 42,
    # ... i wiele więcej
}
```

---

## Konfiguracja logowania

### Podstawowa konfiguracja (train.yaml)

```yaml
### MODEL
model_name_or_path: ${BASE_MODEL_PATH}
finetuning_type: lora

### TRAINING
learning_rate: 1.0e-4
num_train_epochs: 3
per_device_train_batch_size: 1
gradient_accumulation_steps: 8

### LOGGING & MONITORING
report_to: mlflow              # Włącz MLflow
logging_steps: 10              # Log co 10 kroków
logging_first_step: true       # Loguj też pierwszy krok

### VALIDATION
val_size: 0.1                  # 10% na walidację
eval_strategy: steps           # Ewaluuj co N kroków
eval_steps: 100                # Co 100 kroków
per_device_eval_batch_size: 1

### CHECKPOINTING
save_strategy: steps           # Zapisuj co N kroków
save_steps: 500                # Co 500 kroków
save_total_limit: 3            # Trzymaj max 3 checkpointy

### REPRODUCIBILITY
seed: 42
data_seed: 42
```

### Zaawansowana konfiguracja z custom metrics

```yaml
### EVALUATION METRICS
compute_accuracy: true          # Token accuracy
predict_with_generate: true     # Dla BLEU/ROUGE (wolniejsze)

### BEST MODEL TRACKING
load_best_model_at_end: true
metric_for_best_model: eval_loss
greater_is_better: false
```

### Konfiguracja w Kubernetes ConfigMap

Rozszerz `k8s/04-configmap.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: llm-config
  namespace: llm-training
data:
  # ... istniejące zmienne ...

  # VALIDATION & MONITORING (dodaj):
  VAL_SIZE: "0.1"
  EVAL_STRATEGY: "steps"
  EVAL_STEPS: "100"
  LOGGING_STEPS: "10"
  SAVE_STEPS: "500"
  SAVE_TOTAL_LIMIT: "3"
  SEED: "42"

  # MLFLOW
  MLFLOW_EXPERIMENT_NAME: "llama-finetuning"
```

### Użycie w Training Job

Zaktualizuj `k8s/06-training-job.yaml`:

```yaml
args:
- |
  # Ustaw nazwę eksperymentu MLflow
  export MLFLOW_EXPERIMENT_NAME="${MLFLOW_EXPERIMENT_NAME:-llama-finetuning}"

  cat > /tmp/train.yaml << EOF
  model_name_or_path: ${BASE_MODEL_PATH}
  stage: sft
  finetuning_type: ${FINETUNING_TYPE}
  lora_rank: ${LORA_RANK}
  lora_alpha: ${LORA_ALPHA}
  template: ${TEMPLATE}
  cutoff_len: ${CUTOFF_LEN}
  dataset_dir: ${DATASET_PATH}
  dataset: train_data
  output_dir: ${LORA_OUTPUT_PATH}
  per_device_train_batch_size: ${BATCH_SIZE}
  gradient_accumulation_steps: ${GRADIENT_ACCUMULATION}
  learning_rate: ${LEARNING_RATE}
  num_train_epochs: ${NUM_EPOCHS}
  fp16: true

  # VALIDATION & MONITORING
  val_size: ${VAL_SIZE:-0.1}
  eval_strategy: ${EVAL_STRATEGY:-steps}
  eval_steps: ${EVAL_STEPS:-100}
  per_device_eval_batch_size: 1
  logging_steps: ${LOGGING_STEPS:-10}
  save_steps: ${SAVE_STEPS:-500}
  save_total_limit: ${SAVE_TOTAL_LIMIT:-3}
  seed: ${SEED:-42}
  report_to: mlflow
  EOF

  llamafactory-cli train /tmp/train.yaml
```

---

## Dashboard i wizualizacja

### Dostęp do MLflow UI

```bash
# Port-forward do MLflow
./scripts/ui.sh mlflow

# Otwórz w przeglądarce
open http://localhost:5000
```

### Kluczowe widoki w MLflow

#### 1. Experiment View

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  MLflow > Experiments > llama-finetuning                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Runs                                                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ Run Name              │ loss  │ eval_loss │ lora_rank │ Duration   │   │
│  ├───────────────────────┼───────┼───────────┼───────────┼────────────┤   │
│  │ train-20250125-v1     │ 0.42  │ 0.45      │ 8         │ 2h 15m     │   │
│  │ train-20250125-v2     │ 0.38  │ 0.41      │ 16        │ 2h 45m     │   │
│  │ train-20250126-v1 ⭐  │ 0.35  │ 0.38      │ 32        │ 3h 20m     │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  [Compare] [Delete] [Download CSV]                                          │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### 2. Run Comparison

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Compare Runs: train-20250125-v1 vs train-20250126-v1                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Parameters Diff:                                                            │
│  ┌─────────────────┬─────────────────┬─────────────────┐                   │
│  │ Parameter       │ v1              │ v2              │                   │
│  ├─────────────────┼─────────────────┼─────────────────┤                   │
│  │ lora_rank       │ 8               │ 32 (changed)    │                   │
│  │ lora_alpha      │ 16              │ 64 (changed)    │                   │
│  │ learning_rate   │ 1e-4            │ 1e-4            │                   │
│  └─────────────────┴─────────────────┴─────────────────┘                   │
│                                                                              │
│  Metrics Comparison:                                                         │
│  Loss ─────────────────────────────────────────────────                     │
│       │                                                                      │
│       │  v1 ────                                                            │
│       │  v2 ════ (lower = better)                                           │
│       │                                                                      │
│       └──────────────────────────────────────────────► Steps                │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Przydatne queries MLflow

```python
# Znajdź najlepszy run
import mlflow

mlflow.set_tracking_uri("http://mlflow.mlflow.svc.cluster.local:5000")
experiment = mlflow.get_experiment_by_name("llama-finetuning")

runs = mlflow.search_runs(
    experiment_ids=[experiment.experiment_id],
    order_by=["metrics.eval_loss ASC"],
    max_results=5
)

print(runs[["run_id", "metrics.eval_loss", "params.lora_rank"]])
```

---

## Alerting i progi

### Definicja progów

```yaml
# Progi dla alertów (do zaimplementowania w monitoringu)
thresholds:
  # Training
  max_loss_increase_pct: 20      # Alert jeśli loss wzrośnie o >20%
  min_loss_decrease_per_epoch: 5 # Alert jeśli loss spada <5% na epokę

  # Validation
  max_val_loss_diff: 0.1         # Alert jeśli val_loss > train_loss + 0.1
  max_val_loss_increase: 3       # Alert po 3 wzrostach val_loss z rzędu

  # Resources
  max_gpu_memory_pct: 95         # Alert przy >95% GPU memory
  max_training_time_hours: 24    # Alert przy treningu >24h
```

### Implementacja Early Stopping

```yaml
# W train.yaml:
early_stopping_patience: 3      # Stop po 3 eval bez poprawy
early_stopping_threshold: 0.01  # Minimalna poprawa
load_best_model_at_end: true    # Załaduj najlepszy checkpoint
```

### Monitoring GPU (Prometheus/Grafana)

```yaml
# Przykładowe metryki do monitorowania:
- nvidia_gpu_memory_used_bytes
- nvidia_gpu_utilization_pct
- nvidia_gpu_temperature_celsius
```

---

## Podsumowanie

### Checklist konfiguracji

- [ ] `report_to: mlflow` w konfiguracji
- [ ] `val_size` > 0 (np. 0.1)
- [ ] `eval_strategy: steps` + `eval_steps`
- [ ] `logging_steps` (np. 10)
- [ ] `save_steps` + `save_total_limit`
- [ ] `seed` dla reprodukowalności
- [ ] MLflow Secret skonfigurowany w K8s

### Komendy diagnostyczne

```bash
# Sprawdź logi treningu
kubectl -n llm-training logs -f job/llama-train

# Sprawdź metryki w MLflow
./scripts/ui.sh mlflow

# Status GPU
kubectl -n llm-training exec -it job/llama-train -- nvidia-smi
```

---

## Źródła

- [MLflow Tracking Documentation](https://mlflow.org/docs/latest/ml/tracking/)
- [MLflow LLM Tracking](https://mlflow.org/docs/latest/llms/llm-tracking/index.html)
- [LLaMA-Factory GitHub](https://github.com/hiyouga/LLaMA-Factory)
- [Transformers Trainer Callbacks](https://huggingface.co/docs/transformers/main_classes/callback)
