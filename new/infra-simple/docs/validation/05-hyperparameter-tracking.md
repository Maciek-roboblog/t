# Śledzenie Hiperparametrów

## Spis treści

1. [Hiperparametry w fine-tuningu LLM](#hiperparametry-w-fine-tuningu-llm)
2. [Co śledzić](#co-śledzić)
3. [Automatyczne śledzenie w MLflow](#automatyczne-śledzenie-w-mlflow)
4. [Porównywanie eksperymentów](#porównywanie-eksperymentów)
5. [Hyperparameter search](#hyperparameter-search)
6. [Best practices](#best-practices)

---

## Hiperparametry w fine-tuningu LLM

### Kategorie hiperparametrów

> **Diagram:** Zobacz [hyperparameter-categories.puml](diagrams/hyperparameter-categories.puml) - kategorie i wpływ hiperparametrów.

| Kategoria | Parametry | Typowe wartości |
|-----------|-----------|-----------------|
| **Model/Architektura** | model_name_or_path, finetuning_type, quantization_bit | lora/qlora/full, 4/8/none |
| **LoRA Specific** | lora_rank, lora_alpha, lora_dropout, lora_target | 8-64, 16-64, 0.0-0.1, q_proj/v_proj/all |
| **Training** | learning_rate, epochs, batch_size, gradient_accumulation | 1e-5 do 3e-4, 1-10, 1-4, 4-16 |
| **Data** | cutoff_len, val_size, template | 512-4096, 0.05-0.2, llama3/alpaca |
| **Optimization** | fp16/bf16, gradient_checkpointing, flash_attn | true/false, fa2/none |

### Wpływ hiperparametrów

| Parametr | Jakość | Szybkość | Pamięć | Stabilność |
|----------|--------|----------|--------|------------|
| ↑ lora_rank | ↑ | ↓ | ↑ | → |
| ↑ learning_rate | ? | → | → | ↓ |
| ↑ batch_size | ↑ | ↑ | ↑ | ↑ |
| ↑ cutoff_len | ↑ | ↓ | ↑↑ | → |
| ↑ epochs | ↑/↓* | ↓ | → | ↓* |
| ↑ lora_dropout | → | → | → | ↑ |

*\* = do pewnego punktu, potem overfitting*

**Najważniejsze parametry do tuningu:**
1. `learning_rate` - największy wpływ na konwergencję
2. `lora_rank` - kompromis jakość/wydajność
3. `epochs` - unikanie overfitting
4. `cutoff_len` - zależnie od długości danych

---

## Co śledzić

### Obowiązkowe do śledzenia

```yaml
# ZAWSZE śledź te parametry

# Model
model_name_or_path: "/storage/models/base-model"
finetuning_type: "lora"

# LoRA
lora_rank: 8
lora_alpha: 16
lora_dropout: 0.05
lora_target: "q_proj,k_proj,v_proj,o_proj"

# Training
learning_rate: 1.0e-4
num_train_epochs: 3
per_device_train_batch_size: 1
gradient_accumulation_steps: 8
warmup_ratio: 0.1
lr_scheduler_type: "cosine"

# Data
cutoff_len: 2048
val_size: 0.1
template: "llama3"

# Reproducibility
seed: 42
```

### Dodatkowe do śledzenia

```yaml
# OPCJONALNE, ale przydatne

# Quantization
quantization_bit: 4              # Jeśli używasz QLoRA
quantization_method: "bitsandbytes"

# Advanced LoRA
use_rslora: false
use_dora: false

# Optimization
fp16: true
bf16: false
gradient_checkpointing: true
flash_attn: "fa2"

# Regularization
weight_decay: 0.01
max_grad_norm: 1.0

# Early stopping
early_stopping_patience: 3
```

### Metadata (nie-hiperparametry)

```yaml
# Kontekst eksperymentu (loguj jako tagi)

# Environment
gpu_type: "NVIDIA A100"
num_gpus: 1
cuda_version: "11.8"
torch_version: "2.1.2"

# Data
dataset_version: "v2.1.0"
dataset_hash: "a1b2c3d4"
train_samples: 9000
test_samples: 1000

# Timing
start_time: "2025-01-25T10:30:00Z"
end_time: "2025-01-25T13:45:00Z"
total_duration_hours: 3.25
```

---

## Automatyczne śledzenie w MLflow

### Co LLaMA-Factory loguje automatycznie

Z `report_to: mlflow`, LLaMA-Factory automatycznie loguje:

```python
# Parametry (params)
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
    # ... i ~50 innych parametrów z TrainingArguments
}

# Metryki (metrics) - per step
{
    "loss": 1.23,
    "learning_rate": 9.5e-5,
    "epoch": 1.5,
    "grad_norm": 0.42,
    # podczas ewaluacji:
    "eval_loss": 1.15,
}

# Final metrics
{
    "train_runtime": 11700.5,
    "train_samples_per_second": 2.34,
    "total_steps": 3000,
}
```

### Dodawanie custom parametrów

```python
# custom_logging.py
import mlflow
import os

def log_custom_params():
    """Dodaj parametry, które nie są logowane automatycznie."""

    # Środowisko
    mlflow.log_params({
        "gpu_type": os.environ.get("GPU_TYPE", "unknown"),
        "cuda_version": os.environ.get("CUDA_VERSION", "unknown"),
    })

    # Dataset
    mlflow.log_params({
        "dataset_version": os.environ.get("DATASET_VERSION", "unknown"),
        "dataset_path": os.environ.get("DATASET_PATH", "unknown"),
    })

    # Custom tags
    mlflow.set_tags({
        "experiment.type": "lora_sweep",
        "experiment.phase": "exploration",
        "model.base": "llama-3-8b",
    })
```

### Integracja w Training Job

```yaml
# k8s/06-training-job.yaml (rozszerzony)
args:
- |
  # Pre-training: log environment
  python << 'PYEOF'
  import mlflow
  import os
  import torch

  mlflow.set_tracking_uri(os.environ["MLFLOW_TRACKING_URI"])
  mlflow.set_experiment(os.environ.get("MLFLOW_EXPERIMENT_NAME", "llama-finetuning"))

  with mlflow.start_run(run_name=os.environ.get("JOB_NAME", "train")):
      # Environment params
      mlflow.log_params({
          "env.cuda_version": torch.version.cuda,
          "env.torch_version": torch.__version__,
          "env.gpu_count": torch.cuda.device_count(),
          "env.gpu_name": torch.cuda.get_device_name(0) if torch.cuda.is_available() else "none",
      })

      # Dataset params
      mlflow.log_params({
          "data.version": os.environ.get("DATASET_VERSION", "unknown"),
          "data.path": os.environ.get("DATASET_PATH", "unknown"),
      })

      # Save run_id for later
      print(f"MLFLOW_RUN_ID={mlflow.active_run().info.run_id}")
  PYEOF

  # Run training (will create nested run or continue)
  llamafactory-cli train /tmp/train.yaml

  # Post-training: log additional info
  # ...
```

---

## Porównywanie eksperymentów

### MLflow UI - porównanie

> **Diagram:** Zobacz [hyperparameter-search.puml](diagrams/hyperparameter-search.puml) - strategia przeszukiwania hiperparametrów.

**Parameters Diff:**

| Parameter | run_001 | run_002 | run_003 |
|-----------|---------|---------|---------|
| lora_rank | 8 | 16 | 32 |
| lora_alpha | 16 | 32 | 64 |
| learning_rate | 1e-4 | 1e-4 | 1e-4 |

**Metrics:**

| Metric | run_001 | run_002 | run_003 |
|--------|---------|---------|---------|
| final_loss | 0.45 | 0.38 | 0.35 |
| eval_loss | 0.48 | 0.41 | 0.39 |
| train_time (h) | 2.1 | 2.8 | 3.5 |

### Programatyczne porównanie

```python
# compare_runs.py
import mlflow
import pandas as pd

def compare_experiments(experiment_name: str, metric: str = "eval_loss"):
    """Porównaj wszystkie runy w eksperymencie."""

    mlflow.set_tracking_uri("http://mlflow:5000")

    # Pobierz wszystkie runy
    runs = mlflow.search_runs(
        experiment_names=[experiment_name],
        filter_string="status = 'FINISHED'",
        order_by=[f"metrics.{metric} ASC"]
    )

    # Wybierz kluczowe kolumny
    key_params = [
        "params.lora_rank",
        "params.lora_alpha",
        "params.learning_rate",
        "params.num_train_epochs",
    ]

    key_metrics = [
        f"metrics.{metric}",
        "metrics.loss",
        "metrics.train_runtime",
    ]

    cols = ["run_id", "start_time"] + key_params + key_metrics
    comparison = runs[[c for c in cols if c in runs.columns]]

    return comparison


def find_best_config(experiment_name: str, metric: str = "eval_loss"):
    """Znajdź najlepszą konfigurację."""

    comparison = compare_experiments(experiment_name, metric)

    if comparison.empty:
        return None

    best_run = comparison.iloc[0]

    print(f"\n=== Best Run: {best_run['run_id'][:8]} ===")
    print(f"eval_loss: {best_run.get(f'metrics.{metric}', 'N/A')}")
    print("\nParameters:")
    for col in comparison.columns:
        if col.startswith("params."):
            param_name = col.replace("params.", "")
            print(f"  {param_name}: {best_run[col]}")

    return best_run


if __name__ == "__main__":
    best = find_best_config("llama-finetuning", "eval_loss")
```

### Analiza wrażliwości

```python
# sensitivity_analysis.py
import mlflow
import pandas as pd
import matplotlib.pyplot as plt

def analyze_parameter_sensitivity(experiment_name: str, param: str, metric: str = "eval_loss"):
    """Analizuj wpływ parametru na metrykę."""

    runs = mlflow.search_runs(experiment_names=[experiment_name])

    param_col = f"params.{param}"
    metric_col = f"metrics.{metric}"

    if param_col not in runs.columns:
        raise ValueError(f"Parameter {param} not found")

    # Konwertuj do numeric
    runs[param_col] = pd.to_numeric(runs[param_col], errors='coerce')
    runs[metric_col] = pd.to_numeric(runs[metric_col], errors='coerce')

    # Usuń NaN
    data = runs[[param_col, metric_col]].dropna()

    # Grupuj i agreguj
    grouped = data.groupby(param_col)[metric_col].agg(['mean', 'std', 'count'])

    print(f"\n=== Sensitivity Analysis: {param} ===")
    print(grouped.to_string())

    # Wykres
    plt.figure(figsize=(10, 6))
    plt.errorbar(grouped.index, grouped['mean'], yerr=grouped['std'], marker='o')
    plt.xlabel(param)
    plt.ylabel(metric)
    plt.title(f"Impact of {param} on {metric}")
    plt.savefig(f"/tmp/sensitivity_{param}.png")

    return grouped


if __name__ == "__main__":
    # Analizuj wpływ lora_rank
    analyze_parameter_sensitivity("llama-finetuning", "lora_rank")

    # Analizuj wpływ learning_rate
    analyze_parameter_sensitivity("llama-finetuning", "learning_rate")
```

---

## Hyperparameter search

### Grid search

```python
# grid_search.py
import itertools
import subprocess
import os

# Definicja przestrzeni parametrów
param_grid = {
    "lora_rank": [8, 16, 32],
    "lora_alpha": [16, 32, 64],
    "learning_rate": ["1e-4", "2e-4"],
}

# Generuj wszystkie kombinacje
keys = list(param_grid.keys())
values = list(param_grid.values())
combinations = list(itertools.product(*values))

print(f"Total experiments: {len(combinations)}")

# Uruchom eksperymenty
for i, combo in enumerate(combinations):
    config = dict(zip(keys, combo))

    run_name = f"grid_{i:03d}_r{config['lora_rank']}_a{config['lora_alpha']}"

    # Przygotuj config
    yaml_content = f"""
model_name_or_path: /storage/models/base-model
finetuning_type: lora
lora_rank: {config['lora_rank']}
lora_alpha: {config['lora_alpha']}
learning_rate: {config['learning_rate']}
num_train_epochs: 3
seed: 42
report_to: mlflow
output_dir: /storage/output/{run_name}
"""

    # Zapisz i uruchom
    with open(f"/tmp/{run_name}.yaml", "w") as f:
        f.write(yaml_content)

    print(f"Running {run_name}...")
    subprocess.run([
        "llamafactory-cli", "train", f"/tmp/{run_name}.yaml"
    ])
```

### Kubernetes Jobs dla grid search

```yaml
# k8s/grid-search-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: lora-sweep-r8
  namespace: llm-training
  labels:
    sweep: lora-rank
    lora_rank: "8"
spec:
  template:
    spec:
      containers:
      - name: trainer
        image: eu.gcr.io/PROJECT_ID/llama-factory-train:latest
        env:
        - name: LORA_RANK
          value: "8"
        - name: LORA_ALPHA
          value: "16"
        - name: MLFLOW_RUN_NAME
          value: "sweep-r8-a16"
        # ... reszta konfiguracji
---
apiVersion: batch/v1
kind: Job
metadata:
  name: lora-sweep-r16
  namespace: llm-training
  labels:
    sweep: lora-rank
    lora_rank: "16"
spec:
  # ... podobnie dla r16
---
apiVersion: batch/v1
kind: Job
metadata:
  name: lora-sweep-r32
  namespace: llm-training
  labels:
    sweep: lora-rank
    lora_rank: "32"
spec:
  # ... podobnie dla r32
```

### Skrypt do uruchomienia sweep

```bash
#!/bin/bash
# scripts/run_sweep.sh

# Parametry do przeszukania
RANKS=(8 16 32)
ALPHAS=(16 32 64)

for rank in "${RANKS[@]}"; do
  for alpha in "${ALPHAS[@]}"; do
    JOB_NAME="sweep-r${rank}-a${alpha}"

    echo "Launching $JOB_NAME..."

    # Generuj manifest
    cat > /tmp/sweep-job.yaml << EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  namespace: llm-training
spec:
  template:
    spec:
      containers:
      - name: trainer
        image: eu.gcr.io/\${PROJECT_ID}/llama-factory-train:latest
        env:
        - name: LORA_RANK
          value: "${rank}"
        - name: LORA_ALPHA
          value: "${alpha}"
        - name: MLFLOW_RUN_NAME
          value: "${JOB_NAME}"
        # ... (use envsubst or similar)
EOF

    kubectl apply -f /tmp/sweep-job.yaml
  done
done

echo "Monitoring sweep progress..."
kubectl -n llm-training get jobs -l sweep=lora-rank -w
```

---

## Best practices

### 1. Zacznij od baseline

```yaml
# Zawsze najpierw baseline z domyślnymi parametrami

# baseline_config.yaml
lora_rank: 8
lora_alpha: 16
learning_rate: 1.0e-4
num_train_epochs: 3

# Zapisz wyniki jako punkt odniesienia
# Wszystkie następne eksperymenty porównuj z baseline
```

### 2. Zmieniaj jeden parametr naraz

```
✗ NIE:
  Eksperyment 1: rank=8, lr=1e-4
  Eksperyment 2: rank=16, lr=2e-4   ← Zmieniono 2 rzeczy!

✓ TAK:
  Eksperyment 1: rank=8, lr=1e-4
  Eksperyment 2: rank=16, lr=1e-4  ← Tylko rank
  Eksperyment 3: rank=8, lr=2e-4   ← Tylko lr
```

### 3. Dokumentuj insights

```markdown
# Experiment Notes: LoRA Rank Sweep

## Obserwacje

1. **lora_rank=8** (baseline)
   - eval_loss: 0.45
   - Training time: 2.1h
   - Obserwacja: Stabilny trening, dobra generalizacja

2. **lora_rank=16**
   - eval_loss: 0.38 (-15%)
   - Training time: 2.8h (+33%)
   - Obserwacja: Znacząca poprawa, wart dodatkowego kosztu

3. **lora_rank=32**
   - eval_loss: 0.35 (-22%)
   - Training time: 3.5h (+67%)
   - Obserwacja: Marginalna poprawa vs r=16

## Wnioski
- Sweet spot: lora_rank=16 dla tego datasetu
- r=32 nie wart dodatkowego czasu treningu
- Następne: eksperymentuj z learning_rate przy r=16
```

### 4. Automatyczne tagowanie

```python
# auto_tagging.py
import mlflow

def tag_run(config: dict):
    """Automatycznie taguj run na podstawie konfiguracji."""

    tags = {}

    # Performance tier
    if config.get("quantization_bit") == 4:
        tags["tier"] = "memory_efficient"
    elif config.get("lora_rank", 8) >= 32:
        tags["tier"] = "high_quality"
    else:
        tags["tier"] = "balanced"

    # Experiment phase
    if "sweep" in config.get("run_name", ""):
        tags["phase"] = "hyperparameter_search"
    elif "baseline" in config.get("run_name", ""):
        tags["phase"] = "baseline"
    else:
        tags["phase"] = "iteration"

    mlflow.set_tags(tags)
```

### 5. Checklist przed eksperymentem

```
□ Baseline zdefiniowany i uruchomiony
□ Metryka sukcesu określona (np. eval_loss < 0.4)
□ Przestrzeń parametrów określona
□ Budget (czas/GPU) określony
□ MLflow experiment utworzony
□ Dataset version zablokowany
□ Seed ustawiony dla reprodukowalności
```

---

## Źródła

- [LoRA Hyperparameters Guide - Unsloth](https://docs.unsloth.ai/get-started/fine-tuning-llms-guide/lora-hyperparameters-guide)
- [Practical Tips for LoRA - Sebastian Raschka](https://magazine.sebastianraschka.com/p/practical-tips-for-finetuning-llms)
- [LoRA Fine-tuning Guide - Databricks](https://www.databricks.com/blog/efficient-fine-tuning-lora-guide-llms)
- [Insights from Hundreds of Experiments - Lightning AI](https://lightning.ai/pages/community/lora-insights/)
- [MLflow Tracking](https://mlflow.org/docs/latest/ml/tracking/)
