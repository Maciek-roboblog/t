# Konfiguracja vLLM - Kompletny przewodnik

## Spis tresci

1. [Wprowadzenie do vLLM](#wprowadzenie-do-vllm)
2. [Parametry serwera](#parametry-serwera)
3. [Optymalizacja pamieci](#optymalizacja-pamieci)
4. [Skalowanie](#skalowanie)
5. [API OpenAI](#api-openai)
6. [Monitoring i metryki](#monitoring-i-metryki)
7. [Konfiguracja produkcyjna](#konfiguracja-produkcyjna)

---

## Wprowadzenie do vLLM

### Czym jest vLLM?

**vLLM** (Very Large Language Model) to wysokowydajny silnik do inference LLM:

- **PagedAttention** - efektywne zarzadzanie pamiecia KV-cache
- **Continuous batching** - dynamiczne grupowanie requestow
- **OpenAI-compatible API** - drop-in replacement dla OpenAI
- **High throughput** - do 24x szybszy niz HuggingFace

### Architektura

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        ARCHITEKTURA vLLM                                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   ┌─────────────┐     ┌─────────────┐     ┌─────────────┐              │
│   │   Client    │────▶│   vLLM API  │────▶│   Engine    │              │
│   │  (HTTP/gRPC)│     │   Server    │     │             │              │
│   └─────────────┘     └─────────────┘     └──────┬──────┘              │
│                                                   │                      │
│                              ┌────────────────────┴───────────────┐     │
│                              │                                    │     │
│                              ▼                                    ▼     │
│                     ┌─────────────────┐              ┌───────────────┐ │
│                     │   Scheduler     │              │ Model Weights │ │
│                     │ (Cont. Batching)│              │   (GPU RAM)   │ │
│                     └────────┬────────┘              └───────────────┘ │
│                              │                                          │
│                              ▼                                          │
│                     ┌─────────────────┐                                │
│                     │  KV Cache       │                                │
│                     │ (PagedAttention)│                                │
│                     └─────────────────┘                                │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### PagedAttention

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        PAGED ATTENTION                                   │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   Tradycyjne podejscie:                                                 │
│   ┌──────────────────────────────────────┐                             │
│   │  Seq 1: [KV Cache ██████████         ]  <- zarezerwowane 100%     │
│   │  Seq 2: [KV Cache ████               ]  <- zarezerwowane 100%     │
│   │  Seq 3: [KV Cache ████████           ]  <- zarezerwowane 100%     │
│   └──────────────────────────────────────┘                             │
│   Marnowanie pamieci: ~60%                                             │
│                                                                          │
│   PagedAttention (vLLM):                                                │
│   ┌──────────────────────────────────────┐                             │
│   │  Page Pool: [█][█][█][█][█][█][ ][ ] <- dynamiczna alokacja       │
│   │  Seq 1: pages 0,1,2                                                │
│   │  Seq 2: pages 3                                                    │
│   │  Seq 3: pages 4,5                                                  │
│   └──────────────────────────────────────┘                             │
│   Marnowanie pamieci: <5%                                              │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Parametry serwera

### Podstawowe uruchomienie

```bash
python -m vllm.entrypoints.openai.api_server \
    --host 0.0.0.0 \
    --port 8000 \
    --model /models/merged-model
```

### Wszystkie parametry

#### Model i tokenizer

| Parametr | Domyslna | Opis |
|----------|----------|------|
| `--model` | (wymagany) | Sciezka do modelu lub nazwa HF |
| `--tokenizer` | = model | Sciezka do tokenizera |
| `--served-model-name` | = model | Nazwa w API |
| `--revision` | main | Wersja/commit modelu |
| `--trust-remote-code` | false | Zaufaj kodowi z HF |

```bash
# Przyklad
--model /models/merged-model \
--served-model-name llama-finetuned \
--tokenizer /models/merged-model
```

#### Pamiec i GPU

| Parametr | Domyslna | Opis |
|----------|----------|------|
| `--gpu-memory-utilization` | 0.9 | % pamieci GPU dla KV cache |
| `--max-model-len` | auto | Max dlugosc kontekstu |
| `--dtype` | auto | Typ danych (float16, bfloat16, float32) |
| `--quantization` | none | Metoda kwantyzacji (awq, gptq, squeezellm) |
| `--enforce-eager` | false | Wylacz CUDA graphs |

```bash
# Przyklad - oszczedna konfiguracja
--gpu-memory-utilization 0.85 \
--max-model-len 4096 \
--dtype float16
```

#### Batching i throughput

| Parametr | Domyslna | Opis |
|----------|----------|------|
| `--max-num-batched-tokens` | auto | Max tokenow w batchu |
| `--max-num-seqs` | 256 | Max sekwencji rownoczesnie |
| `--max-paddings` | 256 | Max padding tokenow |

```bash
# Przyklad - wysoki throughput
--max-num-batched-tokens 32768 \
--max-num-seqs 512
```

#### Skalowanie (multi-GPU)

| Parametr | Domyslna | Opis |
|----------|----------|------|
| `--tensor-parallel-size` | 1 | Liczba GPU (tensor parallelism) |
| `--pipeline-parallel-size` | 1 | Pipeline parallelism |
| `--distributed-executor-backend` | ray | Backend (ray, mp) |

```bash
# Przyklad - 4 GPU
--tensor-parallel-size 4 \
--distributed-executor-backend ray
```

#### Serwer HTTP

| Parametr | Domyslna | Opis |
|----------|----------|------|
| `--host` | localhost | Adres nasluchu |
| `--port` | 8000 | Port |
| `--api-key` | none | Klucz API |
| `--ssl-keyfile` | none | Klucz SSL |
| `--ssl-certfile` | none | Certyfikat SSL |

```bash
# Przyklad - z API key
--host 0.0.0.0 \
--port 8000 \
--api-key "sk-your-secret-key"
```

### Pelna konfiguracja (K8s manifest)

```yaml
# Fragment 07-vllm-inference.yaml
containers:
- name: vllm
  image: eu.gcr.io/PROJECT_ID/llama-factory-api:latest
  command: ["python", "-m", "vllm.entrypoints.openai.api_server"]
  args:
  # Model
  - "--model=/models/merged-model"
  - "--served-model-name=llama-finetuned"
  - "--tokenizer=/models/merged-model"

  # Serwer
  - "--host=0.0.0.0"
  - "--port=8000"

  # Pamiec
  - "--gpu-memory-utilization=0.9"
  - "--max-model-len=4096"
  - "--dtype=float16"

  # Batching
  - "--max-num-seqs=256"
  - "--max-num-batched-tokens=8192"

  # Logging
  - "--disable-log-requests"
```

---

## Optymalizacja pamieci

### Zuzycie pamieci GPU

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    ZUZYCIE PAMIECI GPU (vLLM)                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   ┌───────────────────────────────────────────────────────────────┐    │
│   │                    GPU Memory (np. 40GB)                       │    │
│   ├───────────────────────────────────────────────────────────────┤    │
│   │  Model Weights     │      KV Cache      │  Other  │ Reserved │    │
│   │    (stale)         │    (dynamiczny)    │         │          │    │
│   │  ████████████████  │  ████████████████  │  ████   │   ███    │    │
│   │      ~50%          │    ~40% (0.9 util) │  ~5%    │   ~5%    │    │
│   └───────────────────────────────────────────────────────────────┘    │
│                                                                          │
│   Model weights: zalezy od rozmiaru modelu                             │
│   - 7B FP16: ~14GB                                                     │
│   - 13B FP16: ~26GB                                                    │
│   - 70B FP16: ~140GB (wymaga multi-GPU)                               │
│                                                                          │
│   KV Cache: zalezy od gpu_memory_utilization i max_model_len           │
│   - Wiecej KV cache = wiecej rownoczesnych requestow                  │
│   - Mniejszy max_model_len = wiecej miejsca na batching               │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Parametr gpu-memory-utilization

```yaml
# Bezpieczne (dla wspoldzielonych GPU)
--gpu-memory-utilization 0.8

# Standardowe (dedykowane GPU)
--gpu-memory-utilization 0.9

# Agresywne (maksymalna wydajnosc)
--gpu-memory-utilization 0.95
```

**Zaleznosc od wartosci:**

| Wartosc | Efekt | Kiedy uzywac |
|---------|-------|--------------|
| 0.7-0.8 | Mniej KV cache, mniej rownoczesnych seq | Wspoldzielone GPU |
| 0.9 | **Domyslna** - dobry balans | Wiekszość przypadkow |
| 0.95 | Max wydajnosc, ryzyko OOM | Dedykowane, testowane |

### Parametr max-model-len

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    WPLYW max-model-len                                   │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   max_model_len = 8192 (dlugi kontekst)                                │
│   ┌────────────────────────────────────────┐                           │
│   │  KV Cache per seq: duzy (8K tokenow)   │                           │
│   │  Max concurrent seqs: malo (~32)       │                           │
│   │  Latency: wysza dla dlugich promptow  │                           │
│   └────────────────────────────────────────┘                           │
│                                                                          │
│   max_model_len = 2048 (krotki kontekst)                               │
│   ┌────────────────────────────────────────┐                           │
│   │  KV Cache per seq: maly (2K tokenow)   │                           │
│   │  Max concurrent seqs: duzo (~128)      │                           │
│   │  Latency: nisza                       │                           │
│   └────────────────────────────────────────┘                           │
│                                                                          │
│   REKOMENDACJA:                                                        │
│   Ustaw na minimum wymagane przez twoje use case                       │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

**Rekomendowane wartosci:**

| Use case | max_model_len | Uzasadnienie |
|----------|---------------|--------------|
| Chatbot (krotkie) | 2048 | Typowe konwersacje |
| Q&A | 4096 | Srednie pytania/odpowiedzi |
| Analiza dokumentow | 8192 | Dluzsze teksty |
| Dluge dokumenty | 16384+ | RAG, summarization |

### Kwantyzacja (dla mniejszych GPU)

```bash
# AWQ (Activation-aware Weight Quantization)
--quantization awq \
--model TheBloke/Llama-2-7B-AWQ

# GPTQ
--quantization gptq \
--model TheBloke/Llama-2-7B-GPTQ

# SqueezeLLM
--quantization squeezellm
```

**Porownanie:**

| Metoda | Redukcja | Jakosc | Predkosc |
|--------|----------|--------|----------|
| FP16 | 1x (bazowa) | 100% | 1x |
| AWQ 4-bit | 4x | ~99% | 1.2x |
| GPTQ 4-bit | 4x | ~98% | 1.1x |
| SqueezeLLM | 3x | ~99% | 1x |

---

## Skalowanie

### Single GPU

```yaml
# Dla modeli do ~13B na A100 40GB
args:
- "--model=/models/merged-model"
- "--tensor-parallel-size=1"
- "--max-model-len=4096"
```

### Multi-GPU (Tensor Parallelism)

```yaml
# Dla modeli >40B lub nizszej latencji
args:
- "--model=/models/merged-model"
- "--tensor-parallel-size=4"  # 4x GPU
- "--max-model-len=8192"
```

**Wymagania:**
- GPU musza byc w tym samym nodzie
- NVLink zalecany dla najlepszej wydajnosci
- `nvidia.com/gpu: 4` w resources

### Skalowanie poziome (multiple replicas)

```yaml
# K8s Deployment z wieloma replikami
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vllm-inference
spec:
  replicas: 3  # 3 niezalezne instancje
  selector:
    matchLabels:
      app: vllm-inference
  template:
    spec:
      containers:
      - name: vllm
        resources:
          limits:
            nvidia.com/gpu: "1"  # Kazda replika = 1 GPU
---
# Load Balancer
apiVersion: v1
kind: Service
metadata:
  name: vllm-inference
spec:
  type: LoadBalancer
  selector:
    app: vllm-inference
  ports:
  - port: 8000
```

### Wybor strategii skalowania

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    STRATEGIE SKALOWANIA                                  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   SCENARIUSZ 1: Model 7B, wysoki throughput                            │
│   └─> 3x repliki, po 1 GPU kazda                                       │
│       Throughput: ~150 req/s                                            │
│                                                                          │
│   SCENARIUSZ 2: Model 70B                                               │
│   └─> 1x replika, 4 GPU (tensor parallel)                              │
│       Throughput: ~10 req/s, nizsza latencja                           │
│                                                                          │
│   SCENARIUSZ 3: Model 13B, balans                                       │
│   └─> 2x repliki, po 1 A100 80GB kazda                                 │
│       Throughput: ~60 req/s                                             │
│                                                                          │
│   SCENARIUSZ 4: Model 70B, wysoki throughput                           │
│   └─> 2x repliki, po 4 GPU kazda (8 GPU total)                         │
│       Throughput: ~20 req/s                                             │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## API OpenAI

### Kompatybilnosc

vLLM implementuje OpenAI Chat Completions API:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    OPENAI COMPATIBILITY                                  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   Wspierane endpointy:                                                  │
│   ✓ POST /v1/chat/completions                                          │
│   ✓ POST /v1/completions                                               │
│   ✓ GET  /v1/models                                                    │
│   ✓ GET  /health                                                        │
│                                                                          │
│   Wspierane parametry:                                                  │
│   ✓ model, messages, temperature, top_p, max_tokens                    │
│   ✓ stream, stop, presence_penalty, frequency_penalty                  │
│   ✓ n (multiple completions), logprobs                                 │
│                                                                          │
│   NIE wspierane:                                                        │
│   ✗ function_calling (w podstawowej wersji)                            │
│   ✗ vision (wymaga multimodal models)                                  │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Przyklady uzycia

#### Chat Completions

```bash
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama-finetuned",
    "messages": [
      {"role": "system", "content": "Jestes pomocnym asystentem."},
      {"role": "user", "content": "Czesc, jak sie masz?"}
    ],
    "temperature": 0.7,
    "max_tokens": 100
  }'
```

**Odpowiedz:**

```json
{
  "id": "cmpl-xxx",
  "object": "chat.completion",
  "created": 1234567890,
  "model": "llama-finetuned",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Czesc! Dziekuje za pytanie. Jako asystent AI jestem zawsze gotowy do pomocy. Jak moge Ci dzis pomoc?"
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 25,
    "completion_tokens": 32,
    "total_tokens": 57
  }
}
```

#### Streaming

```bash
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama-finetuned",
    "messages": [{"role": "user", "content": "Opowiedz historie"}],
    "stream": true
  }'
```

#### Completions (legacy)

```bash
curl http://localhost:8000/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama-finetuned",
    "prompt": "Zycie to ",
    "max_tokens": 50,
    "temperature": 0.8
  }'
```

#### Lista modeli

```bash
curl http://localhost:8000/v1/models
```

```json
{
  "object": "list",
  "data": [
    {
      "id": "llama-finetuned",
      "object": "model",
      "created": 1234567890,
      "owned_by": "vllm"
    }
  ]
}
```

### Python client

```python
from openai import OpenAI

# Uzyj vLLM jako backend
client = OpenAI(
    base_url="http://localhost:8000/v1",
    api_key="not-needed"  # lub twoj klucz jesli skonfigurowales
)

# Chat completion
response = client.chat.completions.create(
    model="llama-finetuned",
    messages=[
        {"role": "system", "content": "Jestes ekspertem od programowania."},
        {"role": "user", "content": "Jak sortowac liste w Pythonie?"}
    ],
    temperature=0.7,
    max_tokens=500
)

print(response.choices[0].message.content)
```

### Parametry generowania

| Parametr | Zakres | Domyslna | Opis |
|----------|--------|----------|------|
| `temperature` | 0.0-2.0 | 1.0 | Losowość generowania |
| `top_p` | 0.0-1.0 | 1.0 | Nucleus sampling |
| `max_tokens` | 1-inf | 16 | Max tokenow odpowiedzi |
| `stop` | string/list | null | Sekwencje stopu |
| `presence_penalty` | -2.0-2.0 | 0 | Kara za powtorzenia (obecnosc) |
| `frequency_penalty` | -2.0-2.0 | 0 | Kara za powtorzenia (czestotliwosc) |
| `n` | 1-inf | 1 | Liczba odpowiedzi |

**Rekomendacje:**

| Use case | temperature | top_p | Efekt |
|----------|-------------|-------|-------|
| Fakty, kod | 0.0-0.3 | 0.9 | Deterministyczne |
| Konwersacja | 0.5-0.8 | 0.95 | Zbalansowane |
| Kreatywne | 0.9-1.2 | 1.0 | Losowe, kreatywne |

---

## Monitoring i metryki

### Health check

```bash
# Prosty health check
curl http://localhost:8000/health

# Odpowiedz (gdy OK)
{"status": "healthy"}
```

### Metryki Prometheus

vLLM eksponuje metryki Prometheus:

```bash
curl http://localhost:8000/metrics
```

**Kluczowe metryki:**

| Metryka | Opis |
|---------|------|
| `vllm:num_requests_running` | Aktywne requesty |
| `vllm:num_requests_waiting` | Requesty w kolejce |
| `vllm:num_preemptions` | Liczba preemptions |
| `vllm:gpu_cache_usage_perc` | % uzycia KV cache |
| `vllm:cpu_cache_usage_perc` | % uzycia CPU cache |
| `vllm:avg_prompt_throughput_toks_per_s` | Throughput promptow |
| `vllm:avg_generation_throughput_toks_per_s` | Throughput generowania |

### Konfiguracja Prometheus

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'vllm'
    static_configs:
      - targets: ['vllm-inference:8000']
    metrics_path: /metrics
    scrape_interval: 15s
```

### Alerty (Alertmanager)

```yaml
# alerts.yml
groups:
- name: vllm
  rules:
  - alert: VLLMHighLatency
    expr: histogram_quantile(0.99, vllm_request_latency_seconds_bucket) > 10
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "vLLM high latency (p99 > 10s)"

  - alert: VLLMQueueBacklog
    expr: vllm:num_requests_waiting > 100
    for: 2m
    labels:
      severity: critical
    annotations:
      summary: "vLLM queue backlog (>100 waiting)"

  - alert: VLLMGPUCacheHigh
    expr: vllm:gpu_cache_usage_perc > 95
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "vLLM GPU cache usage >95%"
```

### Logi

```bash
# Logi z requestami (domyslnie wlaczone)
--disable-log-requests  # Wylacz dla produkcji (duzo logow)

# Logi statystyk
--disable-log-stats     # Wylacz statystyki

# Przykladowe logi:
# INFO: Received request cmpl-xxx: prompt: "...", ...
# INFO: Request cmpl-xxx finished. Time: 1.23s, Tokens: 150
```

---

## Konfiguracja produkcyjna

### Kompletny manifest K8s

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vllm-inference
  namespace: llm-training
  labels:
    app: vllm-inference
spec:
  replicas: 2
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
      maxSurge: 1
  selector:
    matchLabels:
      app: vllm-inference
  template:
    metadata:
      labels:
        app: vllm-inference
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8000"
        prometheus.io/path: "/metrics"
    spec:
      # Anti-affinity - rozrzuc po nodach
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchLabels:
                  app: vllm-inference
              topologyKey: kubernetes.io/hostname

      containers:
      - name: vllm
        image: eu.gcr.io/PROJECT_ID/llama-factory-api:latest
        command: ["python", "-m", "vllm.entrypoints.openai.api_server"]
        args:
        # Model
        - "--model=/models/merged-model"
        - "--served-model-name=llama-finetuned"
        - "--trust-remote-code"

        # Server
        - "--host=0.0.0.0"
        - "--port=8000"
        # - "--api-key=$(VLLM_API_KEY)"  # Uncomment dla auth

        # Performance
        - "--gpu-memory-utilization=0.9"
        - "--max-model-len=4096"
        - "--dtype=float16"
        - "--max-num-seqs=256"

        # Logging (produkcja)
        - "--disable-log-requests"

        ports:
        - containerPort: 8000
          name: http
          protocol: TCP

        env:
        - name: CUDA_VISIBLE_DEVICES
          value: "0"
        # - name: VLLM_API_KEY
        #   valueFrom:
        #     secretKeyRef:
        #       name: vllm-secrets
        #       key: api-key

        volumeMounts:
        - name: storage
          mountPath: /models
          subPath: models
          readOnly: true
        - name: shm
          mountPath: /dev/shm

        resources:
          requests:
            cpu: "4"
            memory: "16Gi"
            nvidia.com/gpu: "1"
          limits:
            cpu: "8"
            memory: "32Gi"
            nvidia.com/gpu: "1"

        # Health checks
        livenessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 120
          periodSeconds: 30
          timeoutSeconds: 10
          failureThreshold: 3

        readinessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 60
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3

        startupProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 30  # 5 minut na start

      # GPU tolerations
      tolerations:
      - key: "nvidia.com/gpu"
        operator: "Exists"
        effect: "NoSchedule"

      volumes:
      - name: storage
        persistentVolumeClaim:
          claimName: llama-storage
      - name: shm
        emptyDir:
          medium: Memory
          sizeLimit: 8Gi

      # Graceful shutdown
      terminationGracePeriodSeconds: 60
---
apiVersion: v1
kind: Service
metadata:
  name: vllm-inference
  namespace: llm-training
  labels:
    app: vllm-inference
spec:
  type: ClusterIP
  selector:
    app: vllm-inference
  ports:
  - port: 8000
    targetPort: 8000
    name: http
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: vllm-inference-hpa
  namespace: llm-training
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: vllm-inference
  minReplicas: 1
  maxReplicas: 4
  metrics:
  - type: Pods
    pods:
      metric:
        name: vllm_num_requests_running
      target:
        type: AverageValue
        averageValue: "50"
```

### Checklist produkcyjny

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    CHECKLIST PRODUKCYJNY                                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   BEZPIECZENSTWO                                                        │
│   [ ] API key skonfigurowany                                           │
│   [ ] Network Policy ogranicza dostep                                  │
│   [ ] TLS/HTTPS dla ruchu zewnetrznego                                 │
│   [ ] Secrets nie w manifeście (External Secrets/Vault)                │
│                                                                          │
│   WYDAJNOSC                                                             │
│   [ ] gpu-memory-utilization przetestowane                             │
│   [ ] max-model-len dopasowany do use case                             │
│   [ ] Metryki eksportowane do Prometheus                               │
│   [ ] Load testing wykonany                                             │
│                                                                          │
│   NIEZAWODNOSC                                                          │
│   [ ] Health checks skonfigurowane                                     │
│   [ ] Multiple replicas (min. 2)                                       │
│   [ ] Anti-affinity (rozrzucenie po nodach)                            │
│   [ ] PDB (PodDisruptionBudget) skonfigurowany                         │
│   [ ] Graceful shutdown (terminationGracePeriodSeconds)                │
│                                                                          │
│   OBSERVABILITY                                                         │
│   [ ] Logi zbierane (ELK/Loki)                                         │
│   [ ] Metryki w Grafana                                                │
│   [ ] Alerty skonfigurowane                                            │
│   [ ] Tracing (opcjonalnie)                                            │
│                                                                          │
│   SKALOWALNOSC                                                          │
│   [ ] HPA skonfigurowany                                               │
│   [ ] Resource limits ustawione                                        │
│   [ ] Node affinity dla GPU nodes                                      │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Przydatne linki

- [vLLM Documentation](https://docs.vllm.ai/)
- [vLLM GitHub](https://github.com/vllm-project/vllm)
- [PagedAttention Paper](https://arxiv.org/abs/2309.06180)
- [OpenAI API Reference](https://platform.openai.com/docs/api-reference)

---

*Dokumentacja konfiguracji vLLM dla LLaMA-Factory*
