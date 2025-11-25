# LLaMA-Factory - Przewodnik Użycia

Kompletny przewodnik fine-tuningu modeli LLM z wykorzystaniem LLaMA-Factory na Kubernetes.

## Spis treści

1. [Przegląd](#przegląd)
2. [Skąd brać modele](#skąd-brać-modele)
3. [Przygotowanie danych](#przygotowanie-danych)
4. [Konfiguracja treningu](#konfiguracja-treningu)
5. [Trening przez WebUI](#trening-przez-webui)
6. [Trening przez CLI/YAML](#trening-przez-cliyaml)
7. [Merge LoRA z modelem](#merge-lora-z-modelem)
8. [Deployment do vLLM](#deployment-do-vllm)
9. [Best practices](#best-practices)

---

## Przegląd

### Workflow

![Workflow Fine-tuningu](diagrams/finetune-workflow.puml)

### Komponenty systemu

| Komponent | Rola | Lokalizacja |
|-----------|------|-------------|
| **LLaMA-Factory** | Trening, merge, WebUI | Kubernetes (ten repo) |
| **NFS Storage** | Modele, dane, output | Zewnętrzny |
| **MLflow** | Metryki, tracking | Zewnętrzny |
| **vLLM** | Inference (API) | Zewnętrzny |

---

## Skąd brać modele

### Opcja 1: Pobranie z HuggingFace (zalecane)

```bash
# Na maszynie z dostępem do NFS
pip install huggingface-cli

# Logowanie (dla modeli wymagających akceptacji licencji)
huggingface-cli login

# Pobranie modelu
huggingface-cli download meta-llama/Llama-3.1-8B-Instruct \
  --local-dir /storage/models/llama-3.1-8b-instruct
```

### Opcja 2: Własne modele

Skopiuj model w formacie HuggingFace na NFS:

```bash
# Struktura modelu
/storage/models/my-model/
├── config.json           # Konfiguracja modelu
├── tokenizer.json        # Tokenizer
├── tokenizer_config.json
├── special_tokens_map.json
├── model-00001-of-00004.safetensors  # Wagi modelu
├── model-00002-of-00004.safetensors
├── model-00003-of-00004.safetensors
├── model-00004-of-00004.safetensors
└── model.safetensors.index.json
```

### Opcja 3: ModelScope (alternatywa dla HuggingFace)

```bash
# Jeśli HuggingFace niedostępny
export USE_MODELSCOPE_HUB=1
```

### Popularne modele do fine-tuningu

| Model | Rozmiar | VRAM (LoRA) | VRAM (QLoRA) | Użycie |
|-------|---------|-------------|--------------|--------|
| Llama-3.1-8B | 16GB | 24GB | 12GB | Ogólne |
| Llama-3.2-3B | 6GB | 12GB | 8GB | Małe GPU |
| Qwen2.5-7B | 14GB | 20GB | 10GB | Wielojęzyczne |
| Mistral-7B | 14GB | 20GB | 10GB | Szybkie |
| Phi-3-mini | 7GB | 12GB | 6GB | Edge/mobile |

### Konfiguracja ścieżki modelu

W `k8s/04-configmap.yaml`:

```yaml
data:
  BASE_MODEL_PATH: "/storage/models/llama-3.1-8b-instruct"
```

---

## Przygotowanie danych

### Format Alpaca (zalecany dla prostych zadań)

Idealny dla instruction-following:

```json
[
  {
    "instruction": "Przetłumacz na angielski",
    "input": "Dzień dobry, jak się masz?",
    "output": "Good morning, how are you?"
  },
  {
    "instruction": "Napisz krótkie podsumowanie",
    "input": "LLaMA-Factory to framework do fine-tuningu modeli LLM...",
    "output": "LLaMA-Factory umożliwia fine-tuning ponad 100 modeli."
  }
]
```

**Pola:**
- `instruction` (wymagane) - polecenie/pytanie
- `input` (opcjonalne) - dodatkowy kontekst
- `output` (wymagane) - oczekiwana odpowiedź
- `system` (opcjonalne) - system prompt

### Format ShareGPT (dla konwersacji)

Idealny dla chatbotów i multi-turn:

```json
[
  {
    "conversations": [
      {"from": "human", "value": "Cześć, kim jesteś?"},
      {"from": "gpt", "value": "Jestem asystentem AI. W czym mogę pomóc?"},
      {"from": "human", "value": "Jak działa fine-tuning?"},
      {"from": "gpt", "value": "Fine-tuning to proces dostosowania..."}
    ],
    "system": "Jesteś pomocnym asystentem."
  }
]
```

**Role:**
- `human` - wiadomość użytkownika
- `gpt` - odpowiedź modelu
- `system` - system prompt (opcjonalnie)
- `function`, `observation` - dla function calling

### Kiedy użyć którego formatu?

| Scenariusz | Format | Dlaczego |
|------------|--------|----------|
| Q&A | Alpaca | Proste pary pytanie-odpowiedź |
| Klasyfikacja | Alpaca | Jeden input → jeden output |
| Chatbot | ShareGPT | Multi-turn konwersacje |
| Function calling | ShareGPT | Obsługuje role function/observation |
| Tłumaczenia | Alpaca | Prosty mapping |
| RAG fine-tuning | Alpaca | Kontekst w polu input |

### Rejestracja datasetu

Utwórz lub edytuj `/storage/data/dataset_info.json`:

```json
{
  "my_dataset": {
    "file_name": "my_data.json",
    "formatting": "alpaca",
    "columns": {
      "prompt": "instruction",
      "query": "input",
      "response": "output"
    }
  },
  "my_chat_dataset": {
    "file_name": "conversations.json",
    "formatting": "sharegpt",
    "columns": {
      "messages": "conversations",
      "system": "system"
    }
  }
}
```

### Walidacja datasetu

```bash
# W podzie LLaMA-Factory
kubectl -n llm-training exec -it deploy/llama-webui -- bash

# Waliduj JSON
python -c "
import json
with open('/storage/data/my_data.json') as f:
    data = json.load(f)
    print(f'Liczba przykładów: {len(data)}')
    print(f'Pierwszy przykład: {data[0]}')
"
```

---

## Konfiguracja treningu

### Parametry LoRA/QLoRA

| Parametr | Wartość domyślna | Opis | Wpływ na VRAM |
|----------|------------------|------|---------------|
| `lora_rank` | 8 | Rank macierzy LoRA | ↑ rank = ↑ VRAM |
| `lora_alpha` | 16 | Współczynnik skalowania | Minimalny |
| `lora_dropout` | 0.1 | Dropout | Brak |
| `lora_target` | all | Które warstwy | ↑ warstw = ↑ VRAM |

### Rekomendacje dla GPU

![Rekomendacje GPU](diagrams/gpu-recommendations.puml)

### LoRA vs QLoRA vs Full

| Metoda | VRAM | Jakość | Szybkość | Kiedy używać |
|--------|------|--------|----------|--------------|
| **LoRA** | Średni | Bardzo dobra | Szybki | Domyślny wybór |
| **QLoRA** | Niski | Dobra | Średni | Ograniczone GPU |
| **Full** | Wysoki | Najlepsza | Wolny | Duże zmiany w modelu |

---

## Trening przez WebUI

### 1. Uruchomienie WebUI

```bash
# Wdróż WebUI
./scripts/deploy.sh webui

# Port-forward
./scripts/ui.sh webui

# Otwórz przeglądarkę
# http://localhost:7860
```

### 2. Konfiguracja w WebUI (LlamaBoard)

**Zakładka: Train**

| Sekcja | Parametr | Wartość |
|--------|----------|---------|
| **MODEL** | Model path | `/storage/models/llama-3.1-8b-instruct` |
| | Template | `llama3` (musi pasować do modelu!) |
| **DATASET** | Dataset dir | `/storage/data` |
| | Dataset | `my_dataset` (z dataset_info.json) |
| **METHOD** | Finetuning type | `lora` |
| | LoRA rank | `8` (zwiększ dla lepszej jakości) |
| | LoRA alpha | `16` |
| | LoRA target | `all` |
| **TRAINING** | Learning rate | `5e-5` |
| | Epochs | `3` |
| | Batch size | `2` |
| | Gradient accumulation | `8` (efektywny batch = 16) |
| | Cutoff length | `2048` |
| | Quantization bit | `None` (lub `4` dla QLoRA) |
| **OUTPUT** | Output dir | `/storage/output/lora-adapter` |
| | Logging dir | `/storage/output/logs` |

Kliknij **[Start]** aby rozpocząć trening.

### 3. Monitorowanie w WebUI

- **Loss chart** - wykres straty treningowej
- **Learning rate** - aktualna wartość LR
- **Progress** - postęp treningu
- **Logs** - szczegółowe logi

### 4. Po zakończeniu treningu

W WebUI przejdź do zakładki **Export**:
1. Wybierz adapter z `/storage/output/lora-adapter`
2. Export dir: `/storage/models/merged-model`
3. Kliknij **Export**

---

## Trening przez CLI/YAML

### Przykładowa konfiguracja YAML

Utwórz `/storage/configs/train_lora.yaml`:

```yaml
### Model
model_name_or_path: /storage/models/llama-3.1-8b-instruct
template: llama3
trust_remote_code: true

### Dataset
dataset_dir: /storage/data
dataset: my_dataset
cutoff_len: 2048
preprocessing_num_workers: 4

### Method (LoRA)
finetuning_type: lora
lora_rank: 16
lora_alpha: 32
lora_dropout: 0.1
lora_target: all

### Training
per_device_train_batch_size: 2
gradient_accumulation_steps: 8
learning_rate: 5.0e-5
num_train_epochs: 3
lr_scheduler_type: cosine
warmup_ratio: 0.1
max_grad_norm: 1.0

### Optimization
bf16: true
gradient_checkpointing: true
flash_attn: fa2

### Output
output_dir: /storage/output/lora-adapter
logging_dir: /storage/output/logs
logging_steps: 10
save_strategy: epoch
save_total_limit: 3

### MLflow (opcjonalne)
report_to: mlflow
mlflow_tracking_uri: ${MLFLOW_TRACKING_URI}
run_name: llama3-lora-training
```

### QLoRA (dla mniejszych GPU)

```yaml
### Model
model_name_or_path: /storage/models/llama-3.1-8b-instruct
template: llama3

### Quantization (QLoRA)
quantization_bit: 4
quantization_method: bitsandbytes

### Method
finetuning_type: lora
lora_rank: 8
lora_target: all

### Training (mniejsze wartości dla QLoRA)
per_device_train_batch_size: 1
gradient_accumulation_steps: 16
cutoff_len: 1024
```

### Uruchomienie treningu

**Opcja A - Kubernetes Job:**

```bash
# Edytuj k8s/06-training-job.yaml z odpowiednimi parametrami
kubectl apply -f k8s/06-training-job.yaml

# Monitoruj
kubectl -n llm-training logs -f job/training-job
```

**Opcja B - Bezpośrednio w podzie:**

```bash
# Wejdź do poda WebUI
kubectl -n llm-training exec -it deploy/llama-webui -- bash

# Uruchom trening
llamafactory-cli train /storage/configs/train_lora.yaml
```

### Dostępne komendy CLI

| Komenda | Opis |
|---------|------|
| `llamafactory-cli train config.yaml` | Trening |
| `llamafactory-cli export config.yaml` | Merge LoRA |
| `llamafactory-cli chat config.yaml` | Test w CLI |
| `llamafactory-cli webchat` | Test przez przeglądarkę |
| `llamafactory-cli webui` | Uruchom WebUI |
| `llamafactory-cli eval config.yaml` | Ewaluacja |

---

## Merge LoRA z modelem

### Dlaczego merge?

- **LoRA adapter** - małe pliki (~100MB), wymaga modelu bazowego
- **Merged model** - pełny model, gotowy do inference
- **vLLM** - wymaga zmergowanego modelu (nie obsługuje LoRA bezpośrednio w podstawowej konfiguracji)

### Konfiguracja merge (YAML)

Utwórz `/storage/configs/merge_lora.yaml`:

```yaml
### Model
model_name_or_path: /storage/models/llama-3.1-8b-instruct
adapter_name_or_path: /storage/output/lora-adapter
template: llama3
trust_remote_code: true
finetuning_type: lora

### Export
export_dir: /storage/models/merged-model
export_size: 4
export_device: auto
export_legacy_format: false
```

### Uruchomienie merge

**Opcja A - Kubernetes Job:**

```bash
kubectl apply -f k8s/09-merge-model-job.yaml
kubectl -n llm-training logs -f job/merge-lora
```

**Opcja B - W podzie:**

```bash
kubectl -n llm-training exec -it deploy/llama-webui -- bash
llamafactory-cli export /storage/configs/merge_lora.yaml
```

### Weryfikacja merge

```bash
# Sprawdź strukturę
ls -la /storage/models/merged-model/

# Powinno zawierać:
# - config.json
# - tokenizer.json
# - tokenizer_config.json
# - special_tokens_map.json
# - model-*.safetensors (lub model.safetensors)
# - generation_config.json

# Sprawdź rozmiar (powinien być podobny do modelu bazowego)
du -sh /storage/models/merged-model/
```

---

## Deployment do vLLM

> **UWAGA:** vLLM jest zewnętrzną usługą. Poniższe instrukcje dotyczą konfiguracji zewnętrznego serwera vLLM.

### Wymagania dla vLLM

1. Dostęp do tego samego NFS co LLaMA-Factory
2. GPU z wystarczającą pamięcią
3. vLLM zainstalowany (`pip install vllm`)

### Uruchomienie vLLM

```bash
# Na serwerze vLLM
vllm serve /storage/models/merged-model \
  --host 0.0.0.0 \
  --port 8000 \
  --tensor-parallel-size 1 \
  --gpu-memory-utilization 0.9 \
  --max-model-len 4096 \
  --trust-remote-code
```

### Test API

```bash
curl http://vllm-server:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "/storage/models/merged-model",
    "messages": [
      {"role": "system", "content": "Jesteś pomocnym asystentem."},
      {"role": "user", "content": "Cześć, jak się masz?"}
    ],
    "max_tokens": 100,
    "temperature": 0.7
  }'
```

### Diagram przepływu

![LLaMA-Factory → vLLM Flow](diagrams/llama-vllm-flow.puml)

---

## Best practices

### Jakość danych > Ilość

![Priorytety Fine-tuningu](diagrams/training-priorities.puml)

### Checklisty

**Przed treningiem:**
- [ ] Model bazowy jest na NFS i działa
- [ ] Dataset jest w poprawnym formacie (Alpaca/ShareGPT)
- [ ] dataset_info.json zawiera definicję datasetu
- [ ] Template odpowiada modelowi
- [ ] GPU ma wystarczająco VRAM

**Podczas treningu:**
- [ ] Loss maleje (nie jest NaN)
- [ ] Wykorzystanie GPU jest wysokie (>80%)
- [ ] Brak błędów OOM
- [ ] Checkpointy zapisują się

**Po treningu:**
- [ ] Model zmergowany poprawnie
- [ ] Wszystkie pliki są w katalogu merged-model
- [ ] Test inference działa
- [ ] vLLM może załadować model

### Typowe błędy

| Błąd | Przyczyna | Rozwiązanie |
|------|-----------|-------------|
| `Loss = NaN` | Za wysoki LR | Zmniejsz do 1e-5 |
| `CUDA OOM` | Za mało VRAM | Użyj QLoRA, zmniejsz batch |
| `Template mismatch` | Zły template | Sprawdź dokumentację modelu |
| `Dataset not found` | Brak w dataset_info.json | Dodaj definicję |
| `Model size doubled` | Normalne dla merge | embed_tokens w FP32 |

### Monitorowanie

```bash
# Logi treningu
kubectl -n llm-training logs -f job/training-job

# GPU utilization
kubectl -n llm-training exec -it deploy/llama-webui -- nvidia-smi -l 1

# MLflow dashboard
./scripts/ui.sh mlflow
# http://localhost:5000
```

---

## Przykładowy end-to-end workflow

```bash
# 1. Przygotuj dane (na maszynie z NFS)
cat > /storage/data/qa_dataset.json << 'EOF'
[
  {"instruction": "Co to jest LLaMA?", "input": "", "output": "LLaMA to rodzina modeli LLM od Meta."},
  {"instruction": "Jak działa fine-tuning?", "input": "", "output": "Fine-tuning dostosowuje wagi modelu do konkretnego zadania."}
]
EOF

# 2. Zarejestruj dataset
cat > /storage/data/dataset_info.json << 'EOF'
{
  "qa_dataset": {
    "file_name": "qa_dataset.json",
    "formatting": "alpaca"
  }
}
EOF

# 3. Wdróż LLaMA-Factory
./scripts/deploy.sh all

# 4. Uruchom WebUI
./scripts/ui.sh webui
# Skonfiguruj w przeglądarce i uruchom trening

# 5. Po treningu - merge
kubectl apply -f k8s/09-merge-model-job.yaml
kubectl -n llm-training logs -f job/merge-lora

# 6. Sprawdź wynik
kubectl -n llm-training exec -it deploy/llama-webui -- \
  ls -la /storage/models/merged-model/

# 7. vLLM (na zewnętrznym serwerze)
vllm serve /storage/models/merged-model --port 8000
```

---

## Źródła

- [LLaMA-Factory GitHub](https://github.com/hiyouga/LLaMA-Factory)
- [LLaMA-Factory Dataset Format](https://github.com/hiyouga/LLaMA-Factory/blob/main/data/README.md)
- [DataCamp: LlamaBoard WebUI Guide](https://www.datacamp.com/tutorial/llama-factory-web-ui-guide-fine-tuning-llms)
- [LoRA & QLoRA Best Practices](https://medium.com/@QuarkAndCode/lora-qlora-llm-fine-tuning-best-practices-setup-pitfalls-c8147d34a6fd)
- [Google Cloud: LoRA/QLoRA Recommendations](https://docs.cloud.google.com/vertex-ai/generative-ai/docs/model-garden/lora-qlora)
- [vLLM Documentation](https://docs.vllm.ai/)

---

*Przewodnik użycia LLaMA-Factory dla Kubernetes*
