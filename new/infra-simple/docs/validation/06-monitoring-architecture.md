# Architektura Monitoringu Fine-Tuningu LLM

## Spis treści

1. [Przegląd monitoringu](#przegląd-monitoringu)
2. [Warstwy monitoringu](#warstwy-monitoringu)
3. [Kategorie metryk](#kategorie-metryk)
4. [Audit trail](#audit-trail)
5. [Quality gates](#quality-gates)
6. [Integracja z LLaMA-Factory](#integracja-z-llama-factory)
7. [Implementacja](#implementacja)

---

## Przegląd monitoringu

> **Diagram:** Zobacz [finetuning-monitoring-overview.puml](diagrams/finetuning-monitoring-overview.puml) - ogólny widok monitoringu fine-tuningu.

### Cel monitoringu fine-tuningu

Monitoring fine-tuningu LLM służy trzem głównym celom:

| Cel | Opis | Kluczowe elementy |
|-----|------|-------------------|
| **Obserwacja treningu** | Śledzenie postępu i wykrywanie problemów w czasie rzeczywistym | loss, learning_rate, GPU usage |
| **Walidacja jakości** | Ocena czy model spełnia wymagania jakościowe | eval metrics, benchmarks, quality gates |
| **Audytowalność** | Pełna dokumentacja procesu dla compliance i reprodukowalności | lineage, hashes, versioning |

### Główne komponenty

```
┌─────────────────────────────────────────────────────────────────┐
│                    Fine-Tuning Pipeline                          │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐  │
│  │  Input   │───►│ Training │───►│  Output  │───►│  Audit   │  │
│  │(versioned)│   │(monitored)│   │(validated)│   │(recorded)│  │
│  └──────────┘    └──────────┘    └──────────┘    └──────────┘  │
│       │               │               │               │         │
│       ▼               ▼               ▼               ▼         │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              Monitoring & Tracking Layer                  │  │
│  │  • Experiment Tracking (params, metrics, artifacts)       │  │
│  │  • Resource Monitoring (GPU, memory, throughput)          │  │
│  │  • Audit Trail (lineage, hashes, compliance)              │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Warstwy monitoringu

> **Diagram:** Zobacz [finetuning-monitoring-layers.puml](diagrams/finetuning-monitoring-layers.puml) - warstwy stacku.

### Architektura warstwowa

| Warstwa | Odpowiedzialność | Elementy |
|---------|------------------|----------|
| **L4: Audyt & Compliance** | Governance, reprodukowalność | Model Registry, Audit Log, Compliance Tags |
| **L3: Analiza & Decyzje** | Quality gates, alerting | Drift detection, Experiment comparison |
| **L2: Wizualizacja** | Dashboardy, UI | Training dashboard, Metrics API |
| **L1: Storage** | Przechowywanie danych | Experiment DB, Time-series, Artifacts |
| **L0: Kolekcja** | Zbieranie metryk | Callbacks, Exporters, Events |

### Warstwa 0: Kolekcja danych

**Źródła danych w LLaMA-Factory:**

```python
# Trainer callbacks - automatyczne logowanie
class LlamaFactoryCallback:
    def on_train_begin(self, args, state, control):
        # Log: parameters, config, dataset info
        pass

    def on_log(self, args, state, control, logs):
        # Log: loss, lr, epoch, grad_norm
        # Frequency: every logging_steps
        pass

    def on_evaluate(self, args, state, control, metrics):
        # Log: eval_loss, eval_accuracy
        # Frequency: every eval_steps
        pass

    def on_save(self, args, state, control):
        # Log: checkpoint saved, step, metrics
        pass

    def on_train_end(self, args, state, control):
        # Log: final metrics, training complete
        pass
```

### Warstwa 1: Storage

| Typ danych | Storage | Format | Retencja |
|------------|---------|--------|----------|
| Parametry eksperymentu | Relational DB | JSON | Permanentna |
| Metryki (per-step) | Time-series DB | Float + timestamp | 30-90 dni |
| Checkpointy | Object Store | safetensors/bin | 3-5 ostatnich |
| Artefakty (configs) | Object Store | YAML/JSON | Permanentna |
| Logi | Log Store | Text | 30 dni |

### Warstwa 2: Wizualizacja

**Kluczowe widoki:**

1. **Training Dashboard** - real-time loss, LR schedule, progress
2. **Experiment Comparison** - porównanie runów, diff parametrów
3. **Resource Dashboard** - GPU utilization, memory, throughput
4. **Audit View** - lineage, hashes, compliance status

### Warstwa 3: Analiza & Decyzje

**Quality gates (bramki jakości):**

```yaml
quality_gates:
  training_stability:
    - loss != NaN
    - loss != Inf
    - loss_decreased: true

  generalization:
    - eval_loss < train_loss * 1.2

  baseline_comparison:
    - current_metric >= baseline * 0.95

  audit_completeness:
    - all_artifacts_logged: true
    - all_hashes_computed: true
    - config_versioned: true
```

### Warstwa 4: Audyt & Compliance

**Model Registry stages:**

| Stage | Opis | Wymagania |
|-------|------|-----------|
| `None` | Nowy run | - |
| `Candidate` | Przeszedł quality gates | All gates passed |
| `Staging` | W trakcie review | Human approval pending |
| `Production` | Zatwierdzony | Full compliance check |
| `Archived` | Wycofany | Documented reason |

---

## Kategorie metryk

> **Diagram:** Zobacz [finetuning-metrics-categories.puml](diagrams/finetuning-metrics-categories.puml) - kategorie metryk.

### 1. Training Metrics (Metryki treningu)

| Metryka | Opis | Częstotliwość | Alert |
|---------|------|---------------|-------|
| `train_loss` | Cross-entropy loss | logging_steps | NaN, spike >50% |
| `learning_rate` | Aktualny LR | logging_steps | - |
| `epoch` | Numer epoki | logging_steps | - |
| `grad_norm` | Norma gradientów | logging_steps | >10 (instability) |
| `tokens_processed` | Throughput | logging_steps | <100/s (slow) |

**Interpretacja train_loss:**

```
Prawidłowy:   ████████▄▄▄▃▃▂▂▁▁▁  (malejący, stabilizacja)
Underfitting: ████████████████████  (brak spadku)
Unstable:     █▄█▃█▄█▂█▃█▄█▂█▃█▄  (oscylacje)
Error:        ████████NaN          (przerwij trening)
```

### 2. Validation Metrics (Metryki walidacji)

| Metryka | Opis | Częstotliwość | Alert |
|---------|------|---------------|-------|
| `eval_loss` | Loss na validation set | eval_steps | > train_loss * 1.5 |
| `eval_accuracy` | Token accuracy | eval_steps | < baseline |
| `perplexity` | exp(eval_loss) | eval_steps | > 100 |

**Wykrywanie overfittingu:**

```
train_loss:  ████▄▄▃▃▂▂▁▁▁▁▁▁▁▁▁▁  (ciągle spada)
eval_loss:   ████▄▄▃▃▂▂▂▂▃▃▄▄▅▅▆▆  (zaczyna rosnąć)
                          ↑
                    Stop tutaj!
```

### 3. Resource Metrics (Metryki zasobów)

| Metryka | Opis | Threshold |
|---------|------|-----------|
| `gpu_memory_used` | VRAM usage | <95% |
| `gpu_utilization` | Compute usage | >70% (healthy) |
| `gpu_temperature` | Temp in °C | <85°C |
| `batch_time` | Czas na batch | stable |
| `throughput` | Samples/sec | >expected |

### 4. Quality Metrics (Metryki jakości)

| Task | Metryki | Threshold |
|------|---------|-----------|
| Q&A | exact_match, F1 | >0.8 |
| Summarization | ROUGE-1, ROUGE-L | >0.3 |
| Translation | BLEU | >0.3 |
| General | MMLU accuracy | >baseline |
| Chat | Human eval score | >3.5/5 |

### 5. Audit Metrics (Metryki audytu)

| Metryka | Cel | Wymagane |
|---------|-----|----------|
| `dataset_hash` | Integrity check | SHA256 |
| `config_version` | Reproducibility | Git commit |
| `model_hash` | Artifact tracking | SHA256 |
| `experiment_id` | Lineage | UUID |
| `timestamp` | Timeline | ISO 8601 |

---

## Audit trail

> **Diagram:** Zobacz [finetuning-audit-trail.puml](diagrams/finetuning-audit-trail.puml) - śledzenie liniażu.

### Co musi być zapisane dla audytowalności

#### Input Artifacts (Wejście)

```yaml
input_artifacts:
  base_model:
    path: "/storage/models/llama-3-8b"
    source: "meta-llama/Meta-Llama-3-8B"
    revision: "main"  # lub konkretny commit
    hash: "sha256:abc123..."  # opcjonalnie

  dataset:
    path: "/storage/data/train_v2.1.0"
    version: "v2.1.0"
    hash: "sha256:def456..."
    samples: 9000
    schema: "alpaca"

  config:
    file: "train.yaml"
    git_commit: "7890abc"
    content_hash: "sha256:ghi789..."
```

#### Training Record (Przebieg)

```yaml
training_record:
  experiment_id: "exp-20250126-001"
  run_id: "run-abc123"

  timeline:
    start_time: "2025-01-26T10:30:00Z"
    end_time: "2025-01-26T13:45:00Z"
    duration_seconds: 11700

  progress:
    total_steps: 3000
    completed_steps: 3000
    epochs_completed: 3.0

  checkpoints:
    - step: 1000
      path: "/storage/output/checkpoint-1000"
      eval_loss: 0.45
    - step: 2000
      path: "/storage/output/checkpoint-2000"
      eval_loss: 0.38
    - step: 3000
      path: "/storage/output/checkpoint-3000"
      eval_loss: 0.35

  metrics_summary:
    initial_loss: 2.1
    final_loss: 0.35
    best_eval_loss: 0.35
    best_checkpoint: "checkpoint-3000"
```

#### Output Artifacts (Wyjście)

```yaml
output_artifacts:
  adapter:
    path: "/storage/output/lora-adapter"
    type: "lora"
    files:
      - name: "adapter_model.safetensors"
        hash: "sha256:xyz789..."
      - name: "adapter_config.json"
        hash: "sha256:uvw456..."

  training_args:
    path: "/storage/output/lora-adapter/training_args.json"
    hash: "sha256:rst123..."

  metrics:
    final_train_loss: 0.35
    final_eval_loss: 0.38
    quality_gate_status: "passed"
```

#### Reproducibility Record (Reprodukowalność)

```yaml
reproducibility:
  seeds:
    seed: 42
    data_seed: 42
    numpy_seed: 42

  environment:
    python_version: "3.10.14"
    torch_version: "2.1.2+cu118"
    transformers_version: "4.36.2"
    peft_version: "0.7.1"
    llama_factory_version: "0.9.3"

  hardware:
    gpu_type: "NVIDIA A100"
    gpu_count: 1
    cuda_version: "11.8"

  determinism:
    cudnn_deterministic: true
    cudnn_benchmark: false
```

### Implementacja audit log

```python
# audit_logger.py
import hashlib
import json
from datetime import datetime
from pathlib import Path

class AuditLogger:
    def __init__(self, experiment_id: str, output_dir: str):
        self.experiment_id = experiment_id
        self.output_dir = Path(output_dir)
        self.audit_record = {
            "experiment_id": experiment_id,
            "created_at": datetime.now().isoformat(),
            "input_artifacts": {},
            "training_record": {},
            "output_artifacts": {},
            "reproducibility": {}
        }

    def log_input(self, name: str, path: str, metadata: dict):
        """Log input artifact with hash."""
        file_hash = self._compute_hash(path)
        self.audit_record["input_artifacts"][name] = {
            "path": path,
            "hash": file_hash,
            **metadata
        }

    def log_output(self, name: str, path: str, metadata: dict):
        """Log output artifact with hash."""
        file_hash = self._compute_hash(path)
        self.audit_record["output_artifacts"][name] = {
            "path": path,
            "hash": file_hash,
            **metadata
        }

    def log_environment(self):
        """Log reproducibility information."""
        import torch
        import transformers
        import sys

        self.audit_record["reproducibility"] = {
            "python_version": sys.version,
            "torch_version": torch.__version__,
            "cuda_version": torch.version.cuda,
            "transformers_version": transformers.__version__,
        }

    def save(self):
        """Save audit record to file."""
        audit_path = self.output_dir / "audit_record.json"
        with open(audit_path, "w") as f:
            json.dump(self.audit_record, f, indent=2)
        return audit_path

    def _compute_hash(self, path: str) -> str:
        """Compute SHA256 hash of file."""
        sha256 = hashlib.sha256()
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(4096), b""):
                sha256.update(chunk)
        return f"sha256:{sha256.hexdigest()}"
```

---

## Quality gates

> **Diagram:** Zobacz [finetuning-quality-gates.puml](diagrams/finetuning-quality-gates.puml) - bramki jakości.

### Definicja bramek

| Gate | Metryka | Warunek | Na fail |
|------|---------|---------|---------|
| **G1: Stability** | train_loss | != NaN, != Inf | Block |
| **G2: Convergence** | loss trend | decreased | Warn |
| **G3: Generalization** | eval/train ratio | < 1.2 | Warn |
| **G4: Baseline** | vs baseline | >= 95% | Block |
| **G5: Task Quality** | task_metric | > threshold | Warn |
| **G6: Audit** | completeness | 100% | Block |

### Implementacja quality gates

```python
# quality_gates.py
from dataclasses import dataclass
from typing import Optional, List
import math

@dataclass
class GateResult:
    name: str
    passed: bool
    severity: str  # "block", "warn", "info"
    message: str
    metrics: dict

class QualityGates:
    def __init__(self, baseline_metrics: Optional[dict] = None):
        self.baseline = baseline_metrics or {}
        self.results: List[GateResult] = []

    def check_stability(self, train_loss: float) -> GateResult:
        """G1: Check if training was stable."""
        passed = not (math.isnan(train_loss) or math.isinf(train_loss))
        return GateResult(
            name="stability",
            passed=passed,
            severity="block",
            message="Training loss is valid" if passed else "Invalid loss (NaN/Inf)",
            metrics={"train_loss": train_loss}
        )

    def check_convergence(self, initial_loss: float, final_loss: float) -> GateResult:
        """G2: Check if model converged."""
        passed = final_loss < initial_loss
        improvement = (initial_loss - final_loss) / initial_loss * 100
        return GateResult(
            name="convergence",
            passed=passed,
            severity="warn",
            message=f"Loss improved by {improvement:.1f}%" if passed else "No convergence",
            metrics={"initial": initial_loss, "final": final_loss, "improvement_pct": improvement}
        )

    def check_generalization(self, train_loss: float, eval_loss: float) -> GateResult:
        """G3: Check for overfitting."""
        ratio = eval_loss / train_loss if train_loss > 0 else float('inf')
        passed = ratio < 1.2
        return GateResult(
            name="generalization",
            passed=passed,
            severity="warn",
            message=f"Eval/train ratio: {ratio:.2f}" if passed else "Possible overfitting",
            metrics={"train_loss": train_loss, "eval_loss": eval_loss, "ratio": ratio}
        )

    def check_baseline(self, current_metric: float, metric_name: str) -> GateResult:
        """G4: Compare with baseline."""
        if metric_name not in self.baseline:
            return GateResult(
                name="baseline",
                passed=True,
                severity="info",
                message="No baseline - setting current as baseline",
                metrics={"current": current_metric}
            )

        baseline_value = self.baseline[metric_name]
        ratio = current_metric / baseline_value if baseline_value > 0 else 0
        passed = ratio >= 0.95
        return GateResult(
            name="baseline",
            passed=passed,
            severity="block",
            message=f"vs baseline: {ratio:.1%}" if passed else "Regression detected",
            metrics={"current": current_metric, "baseline": baseline_value, "ratio": ratio}
        )

    def check_audit_completeness(self, audit_record: dict) -> GateResult:
        """G6: Check audit trail completeness."""
        required = ["input_artifacts", "output_artifacts", "reproducibility"]
        missing = [r for r in required if not audit_record.get(r)]
        passed = len(missing) == 0
        return GateResult(
            name="audit_completeness",
            passed=passed,
            severity="block",
            message="Audit complete" if passed else f"Missing: {missing}",
            metrics={"missing_sections": missing}
        )

    def run_all(self, metrics: dict, audit_record: dict) -> dict:
        """Run all quality gates."""
        self.results = [
            self.check_stability(metrics.get("final_train_loss", float('nan'))),
            self.check_convergence(
                metrics.get("initial_train_loss", 0),
                metrics.get("final_train_loss", 0)
            ),
            self.check_generalization(
                metrics.get("final_train_loss", 0),
                metrics.get("final_eval_loss", 0)
            ),
            self.check_baseline(
                metrics.get("final_eval_loss", 0),
                "eval_loss"
            ),
            self.check_audit_completeness(audit_record)
        ]

        blocked = any(r.severity == "block" and not r.passed for r in self.results)
        warnings = any(r.severity == "warn" and not r.passed for r in self.results)

        return {
            "overall_status": "blocked" if blocked else ("warnings" if warnings else "passed"),
            "gates": [vars(r) for r in self.results]
        }
```

---

## Integracja z LLaMA-Factory

### Konfiguracja monitoringu

```yaml
# train.yaml - konfiguracja z pełnym monitoringiem

### Model
model_name_or_path: ${BASE_MODEL_PATH}
finetuning_type: lora

### LoRA
lora_rank: ${LORA_RANK:-16}
lora_alpha: ${LORA_ALPHA:-32}

### Training
learning_rate: ${LEARNING_RATE:-2e-4}
num_train_epochs: ${NUM_EPOCHS:-3}
per_device_train_batch_size: 1
gradient_accumulation_steps: 8

### Monitoring - Logging
report_to: mlflow
logging_steps: 10
logging_first_step: true

### Monitoring - Validation
val_size: 0.1
eval_strategy: steps
eval_steps: 100
per_device_eval_batch_size: 1

### Monitoring - Checkpoints
save_strategy: steps
save_steps: 500
save_total_limit: 3
load_best_model_at_end: true
metric_for_best_model: eval_loss
greater_is_better: false

### Reproducibility
seed: 42
data_seed: 42
```

### Custom callback dla audytu

```python
# audit_callback.py
from transformers import TrainerCallback
import mlflow
import hashlib

class AuditCallback(TrainerCallback):
    """Callback for comprehensive audit logging."""

    def on_train_begin(self, args, state, control, **kwargs):
        """Log all input artifacts at training start."""
        # Log dataset hash
        dataset_hash = self._compute_dataset_hash(args.dataset_dir)
        mlflow.log_param("audit.dataset_hash", dataset_hash)

        # Log config hash
        config_hash = self._compute_config_hash(args)
        mlflow.log_param("audit.config_hash", config_hash)

        # Log environment
        self._log_environment()

    def on_save(self, args, state, control, **kwargs):
        """Log checkpoint metadata."""
        mlflow.log_metrics({
            "checkpoint.step": state.global_step,
            "checkpoint.loss": state.log_history[-1].get("loss", 0)
        }, step=state.global_step)

    def on_train_end(self, args, state, control, **kwargs):
        """Log final audit information."""
        # Compute and log model hash
        model_hash = self._compute_model_hash(args.output_dir)
        mlflow.log_param("audit.model_hash", model_hash)

        # Log final metrics summary
        mlflow.log_param("audit.final_step", state.global_step)
        mlflow.log_param("audit.training_complete", True)

    def _compute_dataset_hash(self, dataset_dir: str) -> str:
        """Compute hash of dataset files."""
        # Implementation
        pass

    def _compute_config_hash(self, args) -> str:
        """Compute hash of training config."""
        # Implementation
        pass

    def _compute_model_hash(self, output_dir: str) -> str:
        """Compute hash of output model."""
        # Implementation
        pass

    def _log_environment(self):
        """Log environment for reproducibility."""
        import torch
        import transformers

        mlflow.log_params({
            "env.torch_version": torch.__version__,
            "env.cuda_version": torch.version.cuda or "N/A",
            "env.transformers_version": transformers.__version__,
        })
```

---

## Implementacja

### Struktura plików

```
docs/validation/
├── README.md
├── 01-metrics-monitoring.md
├── 02-evaluation-pipeline.md
├── 03-reproducibility-checklist.md
├── 04-dataset-versioning.md
├── 05-hyperparameter-tracking.md
├── 06-monitoring-architecture.md      # Ten dokument
└── diagrams/
    ├── finetuning-monitoring-overview.puml
    ├── finetuning-monitoring-layers.puml
    ├── finetuning-metrics-categories.puml
    ├── finetuning-audit-trail.puml
    ├── finetuning-quality-gates.puml
    └── ... (inne diagramy)
```

### Quick checklist

**Przed treningiem:**
- [ ] Dataset wersjonowany i hash obliczony
- [ ] Config w git
- [ ] MLflow experiment utworzony
- [ ] Seed ustawiony

**Podczas treningu:**
- [ ] `report_to: mlflow` włączone
- [ ] `logging_steps` skonfigurowane
- [ ] `eval_steps` skonfigurowane
- [ ] `save_steps` skonfigurowane

**Po treningu:**
- [ ] Quality gates przeszły
- [ ] Model hash obliczony
- [ ] Audit record kompletny
- [ ] Artifacts w registry

---

## Źródła

- [LLaMA-Factory GitHub](https://github.com/hiyouga/LLaMA-Factory)
- [MLflow Tracking](https://mlflow.org/docs/latest/ml/tracking/)
- [LLMOps - Databricks](https://www.databricks.com/glossary/llmops)
- [LLM Observability Tools 2025](https://lakefs.io/blog/llm-observability-tools/)
- [Fine-Tuning LLMs in 2025 - SuperAnnotate](https://www.superannotate.com/blog/llm-fine-tuning)
