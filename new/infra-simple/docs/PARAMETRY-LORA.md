# Parametry LoRA i QLoRA - Kompletny przewodnik

## Spis tresci

1. [Wprowadzenie do LoRA](#wprowadzenie-do-lora)
2. [Parametry LoRA](#parametry-lora)
3. [QLoRA - kwantyzacja](#qlora---kwantyzacja)
4. [Parametry treningowe](#parametry-treningowe)
5. [Optymalizacja pamieci](#optymalizacja-pamieci)
6. [Rekomendowane konfiguracje](#rekomendowane-konfiguracje)
7. [Eksperymenty i tuning](#eksperymenty-i-tuning)

---

## Wprowadzenie do LoRA

### Czym jest LoRA?

**LoRA (Low-Rank Adaptation)** to technika efektywnego fine-tuningu, ktora:
- Zamraza oryginalne wagi modelu
- Dodaje male, trenovalne macierze (adaptery)
- Drastycznie redukuje liczbe parametrow do treningu
- Pozwala na szybki trening z mala iloscia GPU RAM

### Jak dziala LoRA?

![Architektura LoRA](diagrams/lora-architecture.puml)

| Metoda | Macierz | Parametry |
|--------|---------|-----------|
| **Standardowy fine-tuning** | W (d x k) = 4096 x 4096 | 16.7M na warstwe |
| **LoRA** | W (zamrozone) + A (d x r) × B (r x k) | 2 × 4096 × 8 = 65K |

**Redukcja parametrow: 99.6%!**

### Wzor matematyczny

```
h = W₀x + ΔWx = W₀x + BAx

gdzie:
- W₀: oryginalne (zamrozone) wagi [d × k]
- B: macierz adaptera [d × r]
- A: macierz adaptera [r × k]
- r: rank LoRA (hiperparametr)
- Δ W = BA: nauczona aktualizacja wag
```

---

## Parametry LoRA

### Glowne parametry

#### `lora_rank` (r)

**Definicja:** Wymiar wewnetrzny macierzy LoRA (rank).

| Wartosc | Parametry (7B) | Jakosc | Uzycie |
|---------|----------------|--------|--------|
| 4 | ~2M | Podstawowa | Bardzo proste zadania |
| 8 | ~4M | Dobra | **Domyslna** - wiekszość zadan |
| 16 | ~8M | Bardzo dobra | Zlozoone zadania |
| 32 | ~16M | Doskonala | Fine-tuning specjalistyczny |
| 64 | ~32M | Maksymalna | Bliski full fine-tuning |
| 128+ | ~64M+ | N/A | Rzadko uzywane |

**Rekomendacje:**
- **Zacznij od 8** - dobry balans jakosc/wydajnosc
- **Zwieksz do 16-32** jesli jakosc niezadowalajaca
- **Nie przekraczaj 64** bez wyraźnej potrzeby

```yaml
# Konfiguracja w train.yaml
lora_rank: 8  # Domyslne
```

#### `lora_alpha`

**Definicja:** Wspolczynnik skalowania LoRA. Kontroluje sile adaptacji.

**Wzor:**
```
ΔW = (alpha / rank) × BA
```

| Wartosc | Efekt |
|---------|-------|
| alpha = rank | Skalowanie = 1 (neutralne) |
| alpha = 2×rank | Skalowanie = 2 (silniejsza adaptacja) |
| alpha < rank | Skalowanie < 1 (lagodniejsza adaptacja) |

**Typowe ustawienia:**
- `lora_alpha = 16` przy `lora_rank = 8` (skalowanie = 2)
- `lora_alpha = 32` przy `lora_rank = 16` (skalowanie = 2)
- **Regula:** `lora_alpha = 2 × lora_rank`

```yaml
lora_alpha: 16  # Przy rank=8
```

#### `lora_dropout`

**Definicja:** Dropout stosowany do warstw LoRA dla regularyzacji.

| Wartosc | Efekt | Kiedy uzywac |
|---------|-------|--------------|
| 0.0 | Brak dropout | Male datasety, underfitting |
| 0.05 | Lekka regularyzacja | **Domyslne** |
| 0.1 | Umiarkowana | Wiekssze datasety |
| 0.2+ | Silna | Overfitting, bardzo duze dane |

```yaml
lora_dropout: 0.1
```

#### `lora_target`

**Definicja:** Warstwy modelu, do ktorych stosowany jest LoRA.

**Dostepne warstwy (dla LLaMA):**
- `q_proj` - Query projection (attention)
- `k_proj` - Key projection (attention)
- `v_proj` - Value projection (attention)
- `o_proj` - Output projection (attention)
- `gate_proj` - Gate projection (MLP)
- `up_proj` - Up projection (MLP)
- `down_proj` - Down projection (MLP)

**Typowe konfiguracje:**

```yaml
# Minimalna (najszybsza, najmniej parametrow)
lora_target: q_proj,v_proj

# Standardowa (dobry balans) - DOMYSLNA
lora_target: q_proj,k_proj,v_proj,o_proj

# Rozszerzona (lepsza jakosc, wiecej parametrow)
lora_target: q_proj,k_proj,v_proj,o_proj,gate_proj,up_proj,down_proj

# Wszystkie warstwy
lora_target: all
```

**Porownanie:**

| Target | Parametry (7B, r=8) | Jakosc | Czas |
|--------|---------------------|--------|------|
| q,v | ~2M | Podstawowa | Szybki |
| q,k,v,o | ~4M | Dobra | Sredni |
| all | ~8M | Bardzo dobra | Wolniejszy |

### Zaawansowane parametry

#### `lora_fa` (Flash Attention dla LoRA)

Wlacza efektywne obliczenia attention:

```yaml
lora_fa: true  # Wymaga flash-attn
```

#### `use_rslora` (Rank-Stabilized LoRA)

Ulepszona wersja LoRA z lepszą stabilnoscia:

```yaml
use_rslora: true  # Zalecane dla rank > 16
```

#### `use_dora` (Weight-Decomposed LoRA)

DoRA - zaawansowana technika dekompozycji:

```yaml
use_dora: true  # Lepsza jakosc, wolniejszy trening
```

---

## QLoRA - kwantyzacja

### Czym jest QLoRA?

**QLoRA** laczy LoRA z 4-bitowa kwantyzacja modelu bazowego:

![QLoRA vs LoRA](diagrams/qlora-comparison.puml)

| Metoda | Model bazowy | Adapter | GPU RAM (7B) |
|--------|--------------|---------|--------------|
| **LoRA** | FP16 (14GB) | FP16 | ~16GB |
| **QLoRA** | 4-bit (4GB) | FP16 | ~6GB |

**Redukcja pamieci: ~60%!**

### Parametry kwantyzacji

#### `quantization_bit`

```yaml
# 4-bitowa kwantyzacja (QLoRA)
quantization_bit: 4

# 8-bitowa kwantyzacja (kompromis)
quantization_bit: 8

# Brak kwantyzacji (standardowe LoRA)
# quantization_bit: null
```

#### `quantization_method`

```yaml
# bitsandbytes - najpopularniejsza metoda
quantization_method: bitsandbytes
```

### Konfiguracja bitsandbytes (4-bit)

W LLaMA-Factory mozesz dokladnie skonfigurowac kwantyzacje:

```yaml
### QLoRA Configuration
quantization_bit: 4
quantization_method: bitsandbytes

# Typ kwantyzacji (w kodzie Python)
# bnb_4bit_quant_type: "nf4"  # lub "fp4"
# bnb_4bit_compute_dtype: "float16"  # lub "bfloat16"
# bnb_4bit_use_double_quant: true  # Double quantization
```

**Wyjaśnienie parametrow bitsandbytes:**

| Parametr | Wartosci | Opis |
|----------|----------|------|
| `bnb_4bit_quant_type` | `nf4`, `fp4` | **nf4** (Normal Float 4) - lepsze dla LLM |
| `bnb_4bit_compute_dtype` | `float16`, `bfloat16` | Typ danych dla obliczen |
| `bnb_4bit_use_double_quant` | `true/false` | Dodatkowa kompresja (~0.4 bit/param) |

### Porownanie zuzycia pamieci

| Model | FP16 | 8-bit | 4-bit (QLoRA) |
|-------|------|-------|---------------|
| 7B | 14 GB | 8 GB | **4-5 GB** |
| 13B | 26 GB | 14 GB | **8-10 GB** |
| 70B | 140 GB | 70 GB | **35-40 GB** |

---

## Parametry treningowe

### Learning Rate

```yaml
learning_rate: 1.0e-4  # Domyslna dla LoRA
```

**Rekomendacje:**

| Metoda | Learning Rate | Uwagi |
|--------|---------------|-------|
| LoRA | 1e-4 do 3e-4 | **1e-4 domyslne** |
| QLoRA | 1e-4 do 2e-4 | Nieco nizsze |
| Full | 1e-5 do 5e-5 | Znacznie nizsze |

**Dynamiczny LR:**

```yaml
lr_scheduler_type: cosine  # Zalecane
warmup_ratio: 0.1          # 10% kroków na warmup
```

Dostepne schedulery:
- `linear` - liniowy spadek
- `cosine` - **zalecany** - lagodny spadek
- `polynomial` - wielomianowy
- `constant` - staly LR

### Batch size i gradient accumulation

```yaml
per_device_train_batch_size: 1    # Na GPU
gradient_accumulation_steps: 8    # Efektywny batch = 1 × 8 = 8
```

**Efektywny batch size:**
```
effective_batch = per_device_batch × gradient_accumulation × num_gpus
```

**Rekomendacje:**

| GPU RAM | per_device_batch | gradient_accum | Effective |
|---------|------------------|----------------|-----------|
| 16 GB | 1 | 8 | 8 |
| 24 GB | 2 | 4 | 8 |
| 40 GB | 4 | 2 | 8 |
| 80 GB | 8 | 1 | 8 |

### Liczba epok

```yaml
num_train_epochs: 3  # Domyslna
```

**Zaleznosc od rozmiaru datasetu:**

| Dataset | Epoki | Uwagi |
|---------|-------|-------|
| < 1K sampli | 5-10 | Wiecej epok, uwaga na overfitting |
| 1K - 10K | 3-5 | **Standardowe** |
| 10K - 100K | 2-3 | Mniejsza liczba wystarczy |
| > 100K | 1-2 | Jedna epoka moze wystarczyc |

### Cutoff length

```yaml
cutoff_len: 2048  # Maksymalna dlugosc sekwencji
```

**Wplyw na pamiec:**

| cutoff_len | Pamiec (wzgledna) | Kiedy uzywac |
|------------|-------------------|--------------|
| 512 | 1x | Krotkie teksty |
| 1024 | 2x | Standardowe |
| 2048 | 4x | **Domyslna** |
| 4096 | 8x | Dlugie konteksty |
| 8192 | 16x | Bardzo dlugie dokumenty |

### Precision (FP16/BF16)

```yaml
# FP16 - szersza kompatybilnosc
fp16: true
bf16: false

# BF16 - lepsza stabilnosc (Ampere+)
fp16: false
bf16: true
```

**Rekomendacje:**
- **NVIDIA A100/H100:** Uzyj `bf16: true`
- **NVIDIA V100/T4:** Uzyj `fp16: true`
- **Niestabilny trening:** Sprobuj `bf16` lub zmniejsz LR

---

## Optymalizacja pamieci

### Gradient checkpointing

```yaml
gradient_checkpointing: true  # Zalecane
```

**Efekt:**
- Redukcja pamieci GPU o ~30-50%
- Wolniejszy trening o ~20%
- Umozliwia trening wiekszych modeli

### Flash Attention

```yaml
flash_attn: fa2  # Flash Attention 2
```

**Wymagania:**
- GPU: Ampere (A100) lub nowsze
- Instalacja: `pip install flash-attn`

**Efekt:**
- Szybsze obliczenia attention
- Mniejsze zuzycie pamieci
- Niezbedne dla dlugich sekwencji

### DeepSpeed (multi-GPU)

```yaml
deepspeed: ds_z2_config.json  # ZeRO Stage 2
```

**Konfiguracje:**
- `ZeRO-1`: Partycjonowanie optimizer state
- `ZeRO-2`: + Partycjonowanie gradientow
- `ZeRO-3`: + Partycjonowanie parametrow (rozproszone)

### Podsumowanie technik

```
┌─────────────────────────────────────────────────────────────────────────┐
│               TECHNIKI OPTYMALIZACJI PAMIECI                             │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   Bazowe zuzycie: 100%                                                  │
│   │                                                                      │
│   ├─ + QLoRA (4-bit)              → -60%  = 40%                         │
│   ├─ + Gradient checkpointing     → -15%  = 25%                         │
│   ├─ + Flash Attention            → -10%  = 15%                         │
│   └─ + Mniejszy batch             → -5%   = 10%                         │
│                                                                          │
│   Przyklad 7B model:                                                    │
│   FP16 LoRA: ~16 GB  →  QLoRA + optymalizacje: ~4 GB                   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Rekomendowane konfiguracje

### Konfiguracja bazowa (GPU 16GB)

```yaml
### Model
model_name_or_path: /models/base-model

### Method - QLoRA dla oszczednosci pamieci
stage: sft
finetuning_type: lora
quantization_bit: 4

### LoRA
lora_rank: 8
lora_alpha: 16
lora_dropout: 0.1
lora_target: q_proj,k_proj,v_proj,o_proj

### Dataset
dataset: my_dataset
template: llama3
cutoff_len: 1024  # Mniejszy dla oszczednosci

### Training
per_device_train_batch_size: 1
gradient_accumulation_steps: 8
learning_rate: 1.0e-4
num_train_epochs: 3
lr_scheduler_type: cosine
warmup_ratio: 0.1
fp16: true
gradient_checkpointing: true

### Output
output_dir: /output/lora-model
logging_steps: 10
save_steps: 500
```

### Konfiguracja srednia (GPU 24-40GB)

```yaml
### Model
model_name_or_path: /models/base-model

### Method - standardowe LoRA
stage: sft
finetuning_type: lora

### LoRA - wiekszy rank
lora_rank: 16
lora_alpha: 32
lora_dropout: 0.05
lora_target: q_proj,k_proj,v_proj,o_proj,gate_proj,up_proj,down_proj

### Dataset
dataset: my_dataset
template: llama3
cutoff_len: 2048

### Training
per_device_train_batch_size: 2
gradient_accumulation_steps: 4
learning_rate: 2.0e-4
num_train_epochs: 3
lr_scheduler_type: cosine
warmup_ratio: 0.1
bf16: true
flash_attn: fa2
gradient_checkpointing: true

### Output
output_dir: /output/lora-model
logging_steps: 10
save_steps: 500
```

### Konfiguracja zaawansowana (GPU 80GB+)

```yaml
### Model
model_name_or_path: /models/base-model

### Method - LoRA z DoRA
stage: sft
finetuning_type: lora

### LoRA - maksymalna jakosc
lora_rank: 64
lora_alpha: 128
lora_dropout: 0.05
lora_target: all
use_rslora: true
use_dora: true

### Dataset
dataset: my_dataset
template: llama3
cutoff_len: 4096

### Training
per_device_train_batch_size: 4
gradient_accumulation_steps: 2
learning_rate: 1.0e-4
num_train_epochs: 3
lr_scheduler_type: cosine
warmup_ratio: 0.1
bf16: true
flash_attn: fa2

### Output
output_dir: /output/lora-model
logging_steps: 10
save_steps: 200
```

---

## Eksperymenty i tuning

### Strategia eksperymentowania

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    STRATEGIA TUNING HIPERPARAMETROW                      │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   Krok 1: Baseline                                                      │
│   ├── lora_rank: 8                                                      │
│   ├── lora_alpha: 16                                                    │
│   ├── learning_rate: 1e-4                                               │
│   └── epochs: 3                                                         │
│                                                                          │
│   Krok 2: Jesli underfitting (loss nie spada)                          │
│   ├── Zwieksz lora_rank: 16, 32                                        │
│   ├── Zwieksz learning_rate: 2e-4, 3e-4                                │
│   └── Zwieksz epochs: 5, 10                                             │
│                                                                          │
│   Krok 3: Jesli overfitting (val_loss rosnie)                          │
│   ├── Zmniejsz lora_rank: 4                                            │
│   ├── Zwieksz lora_dropout: 0.1, 0.15                                  │
│   ├── Zmniejsz epochs                                                   │
│   └── Dodaj early stopping                                              │
│                                                                          │
│   Krok 4: Jesli OOM (brak pamieci)                                     │
│   ├── Uzyj QLoRA (quantization_bit: 4)                                 │
│   ├── Zmniejsz cutoff_len                                              │
│   ├── Zmniejsz batch_size, zwieksz grad_accum                          │
│   └── Wlacz gradient_checkpointing                                      │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Grid search przykladowy

```python
# Przykladowe eksperymenty do uruchomienia
experiments = [
    # Baseline
    {"lora_rank": 8, "lora_alpha": 16, "lr": 1e-4},

    # Wyzszy rank
    {"lora_rank": 16, "lora_alpha": 32, "lr": 1e-4},
    {"lora_rank": 32, "lora_alpha": 64, "lr": 1e-4},

    # Rozne LR
    {"lora_rank": 8, "lora_alpha": 16, "lr": 5e-5},
    {"lora_rank": 8, "lora_alpha": 16, "lr": 2e-4},

    # Rozne targets
    {"lora_rank": 8, "lora_target": "q_proj,v_proj"},
    {"lora_rank": 8, "lora_target": "all"},
]
```

### Metryki do monitorowania

1. **Training loss** - powinien spadac
2. **Validation loss** - nie powinien rosnac (overfitting)
3. **GPU memory** - czy miesci sie w limitach
4. **Training time** - czas na epoke
5. **Metryki domenowe** - BLEU, ROUGE, accuracy (zaleznie od zadania)

### Typowe problemy i rozwiazania

| Problem | Objaw | Rozwiazanie |
|---------|-------|-------------|
| Underfitting | Loss nie spada | Zwieksz rank, LR, epochs |
| Overfitting | Val loss rosnie | Zwieksz dropout, zmniejsz rank |
| OOM | CUDA out of memory | QLoRA, mniejszy batch, checkpointing |
| NaN loss | Loss = nan | Zmniejsz LR, uzyj bf16 |
| Slow training | Dlugi czas na step | Flash attention, wiekszy batch |

---

## Przydatne linki

- [LoRA Paper](https://arxiv.org/abs/2106.09685)
- [QLoRA Paper](https://arxiv.org/abs/2305.14314)
- [LLaMA-Factory Documentation](https://github.com/hiyouga/LLaMA-Factory)
- [PEFT Library](https://github.com/huggingface/peft)
- [bitsandbytes](https://github.com/TimDettmers/bitsandbytes)

---

*Dokumentacja parametrow LoRA/QLoRA dla LLaMA-Factory*
