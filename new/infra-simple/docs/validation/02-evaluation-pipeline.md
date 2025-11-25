# Pipeline Ewaluacji Modeli

## Spis treści

1. [Typy ewaluacji](#typy-ewaluacji)
2. [Metryki ewaluacyjne](#metryki-ewaluacyjne)
3. [Konfiguracja w LLaMA-Factory](#konfiguracja-w-llama-factory)
4. [Benchmarki standardowe](#benchmarki-standardowe)
5. [Ewaluacja custom](#ewaluacja-custom)
6. [Pipeline CI/CD](#pipeline-cicd)

---

## Typy ewaluacji

### Przegląd

> **Diagram:** Zobacz [evaluation-pipeline.puml](diagrams/evaluation-pipeline.puml) - pipeline ewaluacji modeli.

| Typ ewaluacji | Kiedy | Metryki |
|---------------|-------|---------|
| **Online (podczas treningu)** | Co eval_steps | Validation Loss, Token Accuracy |
| **Offline (po treningu)** | Po zakończeniu | BLEU, ROUGE, Exact Match, MMLU |
| **Production Readiness** | Przed deploymentem | A/B testing, safety checks, latency |

### Podział datasetu

> **Diagram:** Zobacz [dataset-versioning.puml](diagrams/dataset-versioning.puml) - strategia wersjonowania i podziału danych.

| Set | Procent | Cel | Kiedy używany |
|-----|---------|-----|---------------|
| **Training** | 80% | Uczenie modelu | Każdy krok treningu |
| **Validation** | 10% | Monitoring, early stop, hyperparameter tuning | Co eval_steps |
| **Test** | 10% | Final eval, benchmarki, porównania | **NIGDY** podczas treningu! |

**WAŻNE:** Test set musi być oddzielony **PRZED** treningiem!

---

## Metryki ewaluacyjne

### 1. Loss-based metrics

#### Cross-Entropy Loss

```python
# Najczęściej używana metryka
# Im niższy loss, tym lepiej

Loss = -1/N * Σ log(P(correct_token))
```

#### Perplexity

```python
# Perplexity = exp(Loss)
# Interpretacja: "ile tokenów model rozważa"

PPL = exp(CE_Loss)

# Przykłady:
# PPL = 1.0 → model jest pewny (idealnie)
# PPL = 10.0 → model rozważa ~10 opcji
# PPL = 100.0 → model bardzo niepewny
```

### 2. Generation-based metrics

#### BLEU Score

**Zastosowanie:** Tłumaczenia, podsumowania, generacja tekstu.

**Mierzy:** Podobieństwo n-gramów między generacją a referencją.

**Przykład:**
- Reference: "The cat sat on the mat"
- Generated: "The cat is on the mat"
- BLEU-4 = BP × (p1 × p2 × p3 × p4)^(1/4)

**Interpretacja:**

| Score | Jakość |
|-------|--------|
| 0.0 - 0.1 | Słaba jakość |
| 0.1 - 0.3 | Podstawowa jakość |
| 0.3 - 0.5 | Dobra jakość |
| 0.5 - 0.7 | Bardzo dobra jakość |
| > 0.7 | Doskonała (bliska human-level) |

#### ROUGE Score

**Zastosowanie:** Podsumowania, ekstrakcja informacji.

| Typ | Mierzy |
|-----|--------|
| ROUGE-1 | Overlap 1-gramów (słów) |
| ROUGE-2 | Overlap 2-gramów |
| ROUGE-L | Longest Common Subsequence |

**Warianty:** Precision, Recall, F1

**Przykład:**
- Reference: "The quick brown fox jumps"
- Generated: "A quick brown dog jumps high"
- ROUGE-1 F1 = 0.73

#### Exact Match (EM)

**Zastosowanie:** Q&A, klasyfikacja, zadania z jednoznaczną odpowiedzią.

```python
# Prosty binary match
EM = 1 if generated.strip().lower() == reference.strip().lower() else 0

# Agregacja
EM_score = sum(matches) / total_samples
```

### 3. Task-specific metrics

| Zadanie | Metryki |
|---------|---------|
| Q&A | Exact Match, F1, BLEU |
| Summarization | ROUGE-1, ROUGE-2, ROUGE-L |
| Translation | BLEU, chrF, COMET |
| Classification | Accuracy, F1, Precision, Recall |
| Code generation | pass@k, functional correctness |
| Chat/Dialog | Human eval, coherence, helpfulness |

---

## Konfiguracja w LLaMA-Factory

### Ewaluacja podczas treningu

```yaml
# train.yaml

### VALIDATION SET
val_size: 0.1                    # 10% na walidację
# LUB osobny dataset:
# eval_dataset: my_eval_data

### EVALUATION STRATEGY
eval_strategy: steps             # "steps" lub "epoch"
eval_steps: 100                  # Co 100 kroków (jeśli strategy=steps)
per_device_eval_batch_size: 1

### METRICS
compute_accuracy: true           # Token accuracy

### BEST MODEL
load_best_model_at_end: true
metric_for_best_model: eval_loss
greater_is_better: false         # Dla loss: mniejszy = lepszy
```

### Ewaluacja po treningu (CLI)

```bash
# Utworz eval_config.yaml
cat > /tmp/eval_config.yaml << EOF
### Model
model_name_or_path: /storage/models/base-model
adapter_name_or_path: /storage/output/lora-adapter
finetuning_type: lora

### Task
task: mmlu_test                  # lub custom task
template: llama3
lang: en
n_shot: 5                        # Few-shot examples

### Output
output_dir: /storage/eval_results
EOF

# Uruchom ewaluację
llamafactory-cli eval /tmp/eval_config.yaml
```

### Dostępne benchmarki w LLaMA-Factory

| Benchmark | Task name | Opis |
|-----------|-----------|------|
| MMLU | `mmlu_test` | 57 zadań wiedzy ogólnej |
| C-Eval | `ceval_validation` | Chiński benchmark |
| CMMLU | `cmmlu_test` | Chiński multitask |
| Custom | Własna nazwa | Własny dataset |

### Ewaluacja z generacją (BLEU/ROUGE)

```yaml
# eval_with_generation.yaml

model_name_or_path: /storage/models/base-model
adapter_name_or_path: /storage/output/lora-adapter
finetuning_type: lora

### Dataset do ewaluacji
dataset_dir: /storage/data
dataset: test_data               # Osobny test set!
template: llama3

### Generation settings
predict_with_generate: true
max_new_tokens: 256

### Output
output_dir: /storage/eval_results
```

---

## Benchmarki standardowe

### MMLU (Massive Multitask Language Understanding)

**57 zadań w 4 kategoriach:**

| STEM | Humanities | Social Science | Other |
|------|------------|----------------|-------|
| Mathematics, Physics, Chemistry, Biology, CS | History, Philosophy, Law, Literature, Ethics | Economics, Psychology, Sociology, Politics | Business, Health, Misc |

**Format:** Multiple choice (A, B, C, D)
**Metryka:** Accuracy (% poprawnych)

**Typowe wyniki:**

| Model | MMLU Score |
|-------|------------|
| Random baseline | 25% |
| LLaMA-2 7B | ~46% |
| LLaMA-2 70B | ~68% |
| GPT-4 | ~86% |
| Human expert | ~90% |

**Konfiguracja dla LLaMA-Factory:**

```yaml
# mmlu_eval.yaml
model_name_or_path: /storage/models/base-model
adapter_name_or_path: /storage/output/lora-adapter
finetuning_type: lora
task: mmlu_test
template: llama3
lang: en
n_shot: 5
batch_size: 4
output_dir: /storage/eval_results/mmlu
```

### Custom Benchmark

```yaml
# custom_benchmark.yaml

### Własny benchmark
# 1. Utwórz dataset w formacie:
# [{"instruction": "...", "input": "...", "output": "expected_answer"}]

# 2. Zarejestruj w dataset_info.json:
# "my_test": {
#   "file_name": "test_data.json",
#   "formatting": "alpaca"
# }

# 3. Użyj w ewaluacji:
model_name_or_path: /storage/models/base-model
adapter_name_or_path: /storage/output/lora-adapter
finetuning_type: lora

dataset_dir: /storage/data
dataset: my_test
template: llama3

predict_with_generate: true
max_new_tokens: 256

output_dir: /storage/eval_results/custom
```

---

## Ewaluacja custom

### Tworzenie własnego test set

```python
# create_test_set.py
import json
import hashlib
from datetime import datetime

def create_test_set(data_path, output_path, test_ratio=0.1):
    """Wydziel test set z datasetu."""
    with open(data_path, 'r') as f:
        data = json.load(f)

    # Deterministyczny shuffle (dla reprodukowalności)
    import random
    random.seed(42)
    random.shuffle(data)

    split_idx = int(len(data) * (1 - test_ratio))
    train_data = data[:split_idx]
    test_data = data[split_idx:]

    # Zapisz z metadanymi
    test_output = {
        "metadata": {
            "created_at": datetime.now().isoformat(),
            "source_file": data_path,
            "num_samples": len(test_data),
            "hash": hashlib.sha256(json.dumps(test_data).encode()).hexdigest()[:16]
        },
        "data": test_data
    }

    with open(output_path, 'w') as f:
        json.dump(test_output, f, indent=2, ensure_ascii=False)

    print(f"Created test set: {len(test_data)} samples")
    print(f"Hash: {test_output['metadata']['hash']}")

    return test_data

# Użycie:
# python create_test_set.py
```

### Skrypt ewaluacji custom metrics

```python
# evaluate_custom.py
import json
from typing import List, Dict
from collections import defaultdict

def calculate_metrics(predictions: List[str], references: List[str]) -> Dict:
    """Oblicz metryki dla predykcji."""

    metrics = defaultdict(float)
    n = len(predictions)

    # Exact Match
    exact_matches = sum(1 for p, r in zip(predictions, references)
                       if p.strip().lower() == r.strip().lower())
    metrics['exact_match'] = exact_matches / n

    # Token-level F1 (uproszczona wersja)
    f1_scores = []
    for pred, ref in zip(predictions, references):
        pred_tokens = set(pred.lower().split())
        ref_tokens = set(ref.lower().split())

        if not pred_tokens or not ref_tokens:
            f1_scores.append(0.0)
            continue

        common = pred_tokens & ref_tokens
        precision = len(common) / len(pred_tokens)
        recall = len(common) / len(ref_tokens)

        if precision + recall == 0:
            f1_scores.append(0.0)
        else:
            f1_scores.append(2 * precision * recall / (precision + recall))

    metrics['token_f1'] = sum(f1_scores) / n

    # Długość odpowiedzi
    metrics['avg_pred_length'] = sum(len(p.split()) for p in predictions) / n
    metrics['avg_ref_length'] = sum(len(r.split()) for r in references) / n

    return dict(metrics)


def evaluate_model_outputs(results_path: str, test_data_path: str):
    """Ewaluuj wyniki modelu."""

    with open(results_path, 'r') as f:
        results = json.load(f)

    with open(test_data_path, 'r') as f:
        test_data = json.load(f)

    predictions = [r['generated'] for r in results]
    references = [t['output'] for t in test_data]

    metrics = calculate_metrics(predictions, references)

    print("\n=== Evaluation Results ===")
    for metric, value in metrics.items():
        print(f"{metric}: {value:.4f}")

    return metrics


if __name__ == "__main__":
    import sys
    evaluate_model_outputs(sys.argv[1], sys.argv[2])
```

### Kubernetes Job dla ewaluacji

```yaml
# k8s/10-eval-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: llama-eval
  namespace: llm-training
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 86400
  template:
    spec:
      restartPolicy: Never
      nodeSelector:
        nvidia.com/gpu: "true"

      containers:
      - name: evaluator
        image: eu.gcr.io/PROJECT_ID/llama-factory-train:latest
        command: ["/bin/bash", "-c"]
        args:
        - |
          echo "=== LLaMA-Factory Evaluation ==="

          # Konfiguracja ewaluacji
          cat > /tmp/eval.yaml << EOF
          model_name_or_path: ${BASE_MODEL_PATH}
          adapter_name_or_path: ${LORA_OUTPUT_PATH}
          finetuning_type: ${FINETUNING_TYPE}
          template: ${TEMPLATE}

          # Benchmark
          task: ${EVAL_TASK:-mmlu_test}
          lang: en
          n_shot: 5
          batch_size: 4

          output_dir: /storage/eval_results/${JOB_NAME:-eval}
          EOF

          # Uruchom ewaluację
          llamafactory-cli eval /tmp/eval.yaml

          echo "=== Evaluation Complete ==="
          cat /storage/eval_results/${JOB_NAME:-eval}/results.json

        envFrom:
        - configMapRef:
            name: llm-config

        volumeMounts:
        - name: storage
          mountPath: /storage

        resources:
          requests:
            nvidia.com/gpu: "1"
          limits:
            nvidia.com/gpu: "1"

      volumes:
      - name: storage
        persistentVolumeClaim:
          claimName: llama-storage
```

---

## Pipeline CI/CD

### Automatyczny pipeline ewaluacji

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      CI/CD EVALUATION PIPELINE                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐ │
│   │ Training│───►│Checkpoint│───►│  Eval   │───►│ Compare │───►│ Deploy? │ │
│   │   Job   │    │  Saved  │    │   Job   │    │Baseline │    │         │ │
│   └─────────┘    └─────────┘    └─────────┘    └─────────┘    └─────────┘ │
│                                      │              │              │        │
│                                      ▼              ▼              ▼        │
│                                 ┌─────────┐   ┌─────────┐   ┌─────────┐   │
│                                 │ Metrics │   │  Pass/  │   │ Promote │   │
│                                 │ to      │   │  Fail   │   │ or      │   │
│                                 │ MLflow  │   │         │   │ Reject  │   │
│                                 └─────────┘   └─────────┘   └─────────┘   │
│                                                                              │
│   Gate conditions:                                                           │
│   ✓ eval_loss < baseline_loss * 1.05                                        │
│   ✓ exact_match > 0.8 (dla Q&A tasks)                                       │
│   ✓ MMLU score > baseline_score                                             │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Skrypt porównania z baseline

```bash
#!/bin/bash
# compare_with_baseline.sh

CURRENT_EVAL=$1
BASELINE_EVAL=${2:-"/storage/eval_results/baseline/results.json"}
THRESHOLD=${3:-0.05}  # 5% degradation allowed

# Pobierz metryki
CURRENT_LOSS=$(jq '.eval_loss' $CURRENT_EVAL)
BASELINE_LOSS=$(jq '.eval_loss' $BASELINE_EVAL)

# Porównaj
DEGRADATION=$(echo "scale=4; ($CURRENT_LOSS - $BASELINE_LOSS) / $BASELINE_LOSS" | bc)

echo "Current loss: $CURRENT_LOSS"
echo "Baseline loss: $BASELINE_LOSS"
echo "Degradation: ${DEGRADATION}%"

if (( $(echo "$DEGRADATION > $THRESHOLD" | bc -l) )); then
    echo "FAIL: Model degradation exceeds threshold"
    exit 1
else
    echo "PASS: Model meets quality gate"
    exit 0
fi
```

---

## Podsumowanie

### Checklist ewaluacji

- [ ] Wydzielony test set (10%) PRZED treningiem
- [ ] Validation set (10%) dla monitoringu
- [ ] `eval_strategy: steps` skonfigurowane
- [ ] Baseline metrics zapisane w MLflow
- [ ] Post-training evaluation job gotowy
- [ ] Custom metrics zdefiniowane (jeśli potrzebne)
- [ ] Quality gates dla CI/CD

### Komendy

```bash
# Uruchom ewaluację MMLU
kubectl apply -f k8s/10-eval-job.yaml

# Sprawdź wyniki
kubectl -n llm-training logs job/llama-eval

# Porównaj z baseline
./scripts/compare_with_baseline.sh \
    /storage/eval_results/current/results.json \
    /storage/eval_results/baseline/results.json
```

---

## Źródła

- [LLaMA-Factory Evaluation](https://www.aidoczh.com/llamafactory/en/getting_started/eval.html)
- [MMLU Benchmark](https://arxiv.org/abs/2009.03300)
- [LLM Evaluation Metrics - DagsHub](https://dagshub.com/blog/llm-evaluation-metrics/)
- [BLEU Score Explained](https://towardsdatascience.com/bleu-score-in-machine-translation-b2b6f3f0f9fd)
- [ROUGE Score Overview](https://www.aclweb.org/anthology/W04-1013/)
