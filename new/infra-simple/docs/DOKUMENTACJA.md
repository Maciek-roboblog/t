# LLaMA-Factory - Dokumentacja Architektoniczna

## Spis treści

1. [Kontekst](#kontekst) - Co i dlaczego?
2. [Architektura](#architektura) - Jak to działa?
3. [Decyzje architektoniczne](#decyzje-architektoniczne) - Dlaczego tak?
4. [Komponenty](#komponenty) - Z czego się składa?
5. [Przepływ pracy](#przepływ-pracy) - Jak używać?
6. [Walidacja i reprodukowalność](#walidacja-i-reprodukowalność) - Jak zapewnić jakość?

---

## Kontekst

### Co to jest?

Infrastruktura Kubernetes do **fine-tuningu modeli LLM** przy użyciu [LLaMA-Factory](https://github.com/hiyouga/LLaMA-Factory).

### Jaki problem rozwiązuje?

| Problem | Rozwiązanie |
|---------|-------------|
| Fine-tuning wymaga GPU i specyficznej konfiguracji | Gotowe manifesty K8s z GPU affinity |
| Trudne zarządzanie modelami i danymi | Współdzielony NFS storage |
| Brak śledzenia eksperymentów | Integracja z MLflow |
| Skomplikowane wdrożenie inference | Zewnętrzny vLLM czyta z tego samego storage |

### Dla kogo?

- **ML Engineers** - trenowanie i fine-tuning modeli
- **MLOps Engineers** - infrastruktura, deployment, monitoring
- **Platform Teams** - utrzymanie środowiska K8s

---

## Architektura

### Diagram kontekstowy (C4 Level 1)

![Architecture](diagrams/architecture.puml)

### Zasady projektowe

| Zasada | Opis | Dlaczego? |
|--------|------|-----------|
| **Idempotentność** | Repozytorium nie zarządza zewnętrznymi usługami | Oddzielenie odpowiedzialności, łatwiejsze utrzymanie |
| **Single Image** | Jeden obraz Docker dla wszystkich zadań | Prostota, spójność środowiska |
| **GPU-first** | Wszystkie workloady na nodach GPU | Optymalne wykorzystanie zasobów |
| **Shared Storage** | NFS (ReadWriteMany) | Współdzielenie modeli między komponentami |
| **External Inference** | vLLM jako zewnętrzna usługa | Niezależne skalowanie, SLA |

### Granice systemu

**W zakresie tego repozytorium:**
- Trening modeli (LoRA, QLoRA, Full)
- WebUI do eksperymentów
- Merge LoRA adapterów
- Integracja z MLflow

**Poza zakresem (zewnętrzne usługi):**
- MLflow Server
- NFS Storage
- vLLM Inference Server
- Model bazowy (już na NFS)

---

## Decyzje architektoniczne

### ADR-001: Model Registry

**Problem:** Jak udostępniać wytrenowane modele dla vLLM?

**Opcje:**
1. NFS/PVC (obecna) - proste, brak wersjonowania
2. Object Storage (GCS/S3) - skalowalne, multi-cluster
3. MLflow Registry - pełne wersjonowanie, audyt

**Decyzja:** → [ADR-001](adr/001-model-registry.md)

### ADR-002: vLLM Deployment

**Problem:** Czy vLLM powinien być wewnętrznym czy zewnętrznym komponentem?

**Opcje:**
1. Zewnętrzny (obecna) - lepsza izolacja, niezależne SLA
2. Wewnętrzny - prostsze zarządzanie, współdzielone zasoby

**Decyzja:** → [ADR-002](adr/002-vllm-deployment.md)

---

## Komponenty

### Warstwa logiczna

```
┌─────────────────────────────────────────────────────────┐
│                    ZEWNĘTRZNE USŁUGI                     │
│  ┌─────────┐   ┌─────────┐   ┌─────────┐               │
│  │ MLflow  │   │   NFS   │   │  vLLM   │               │
│  │(metrics)│   │(storage)│   │(serving)│               │
│  └────┬────┘   └────┬────┘   └────┬────┘               │
└───────┼─────────────┼─────────────┼─────────────────────┘
        │             │             │
        ▼             ▼             ▼
┌─────────────────────────────────────────────────────────┐
│                  KUBERNETES CLUSTER                      │
│                                                          │
│  ┌──────────────────────────────────────────────────┐   │
│  │              llama-factory-train                  │   │
│  │                                                   │   │
│  │   WebUI ──► Training Job ──► Merge Job           │   │
│  │   (7860)      (GPU)          (GPU)               │   │
│  └──────────────────────────────────────────────────┘   │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

### Komponenty K8s

| Komponent | Typ | Cel | GPU |
|-----------|-----|-----|-----|
| Namespace | `llm-training` | Izolacja zasobów | - |
| Secret | `mlflow-config` | Dane dostępowe MLflow | - |
| PVC | `llama-storage` | Persystentny storage NFS | - |
| ConfigMap | `llm-config` | Konfiguracja środowiska | - |
| Deployment | `llama-webui` | WebUI do eksperymentów | ✓ |
| Job | `training-*` | Trening modelu | ✓ |
| Job | `merge-lora` | Merge LoRA z modelem | ✓ |

### Storage layout

```
/storage/                    # NFS mount (ReadWriteMany)
├── models/
│   ├── base-model/          # Model bazowy (input)
│   └── merged-model/        # Wynik merge (output → vLLM)
├── output/
│   └── lora-adapter/        # Wynik treningu
└── data/
    └── *.json               # Datasety treningowe
```

---

## Przepływ pracy

### High-level workflow

```
  ┌─────────────────────────────────────────────────────────────┐
  │                                                             │
  │   1. PRZYGOTOWANIE        2. TRENING        3. DEPLOYMENT   │
  │                                                             │
  │   Model bazowy ───────►  LLaMA-Factory ───────►  vLLM       │
  │   Dataset                 (LoRA/QLoRA)          (serving)   │
  │                              │                              │
  │                              ▼                              │
  │                          MLflow                             │
  │                         (metryki)                           │
  │                                                             │
  └─────────────────────────────────────────────────────────────┘
```

### Etapy

| Etap | Co się dzieje? | Wynik |
|------|----------------|-------|
| **1. Przygotowanie** | Model i dane są na NFS | `/storage/models/base-model`, `/storage/data/` |
| **2. Trening** | LLaMA-Factory trenuje LoRA adapter | `/storage/output/lora-adapter/` |
| **3. Merge** | LoRA + model bazowy → pełny model | `/storage/models/merged-model/` |
| **4. Serving** | vLLM serwuje model | OpenAI-compatible API |

### Tryby użycia

| Tryb | Przypadek użycia | Jak uruchomić? |
|------|------------------|----------------|
| **WebUI** | Eksperymenty, prototypowanie | `./scripts/ui.sh webui` |
| **Job** | Produkcyjny trening | `./scripts/train.sh <name>` |
| **CLI** | Zaawansowane scenariusze | `kubectl exec ... llamafactory-cli` |

---

## Walidacja i reprodukowalność

### Dlaczego to ważne?

> "Nie wiesz, czy model jest lepszy, jeśli nie możesz go porównać z poprzednim."

| Bez walidacji | Z walidacją |
|---------------|-------------|
| "Ten model chyba działa lepiej" | Metryki: loss 0.28 vs 0.35 |
| "Nie pamiętam parametrów" | MLflow: pełna historia |
| "Nie mogę odtworzyć wyniku" | Seed + wersjonowany dataset |
| "Klient pyta o audyt" | Pełny liniage w MLflow |

### Architektura walidacji

```
┌────────────────────────────────────────────────────────────┐
│                     CYKL WALIDACJI                          │
│                                                             │
│   Trening ──► MLflow ──► Ewaluacja ──► Porównanie          │
│      │          │            │             │                │
│      │          ▼            ▼             ▼                │
│      │      Metryki      Benchmark     Baseline            │
│      │      Parametry    (MMLU, etc)   (poprzedni)         │
│      │      Artefakty                                       │
│      │                                                      │
│      └──────────────────────────────────────────────────►  │
│                     REPRODUKOWALNOŚĆ                        │
│                     (seed, dataset version, config)         │
└────────────────────────────────────────────────────────────┘
```

### Kluczowe praktyki

| Praktyka | Cel | Jak? |
|----------|-----|------|
| **Seed** | Powtarzalność | `seed: 42` w konfiguracji |
| **Wersjonowanie datasetu** | Audyt, rollback | Git LFS lub MLflow Artifacts |
| **Metryki do MLflow** | Porównania | `report_to: mlflow` |
| **Ewaluacja na test set** | Obiektywna ocena | Osobny split danych |
| **Checkpointy** | Recovery, analiza | `save_steps: 500` |

### Szczegółowa dokumentacja

→ [validation/README.md](validation/README.md) - Kompletny przewodnik walidacji

---

## Dodatkowa dokumentacja

| Dokument | Cel | Dla kogo? |
|----------|-----|-----------|
| [**platform-concept/**](platform-concept/README.md) | Koncepcja architektoniczna platformy (fazy wdrożenia, multi-tenancy, CI/CD) | Architekci, PM |
| [PRZEWODNIK-UZYCIA.md](PRZEWODNIK-UZYCIA.md) | Krok po kroku: modele, dane, trening | ML Engineers |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | Rozwiązywanie problemów | Wszyscy |
| [ADR-001](adr/001-model-registry.md) | Decyzja: Model Registry | Architekci |
| [ADR-002](adr/002-vllm-deployment.md) | Decyzja: vLLM deployment | Architekci |
| [validation/](validation/) | Walidacja i reprodukowalność | MLOps |

---

## Źródła

- [LLaMA-Factory](https://github.com/hiyouga/LLaMA-Factory) - Framework do fine-tuningu
- [vLLM](https://docs.vllm.ai/) - High-performance inference
- [MLflow](https://mlflow.org/docs/latest/) - ML lifecycle management
- [C4 Model](https://c4model.com/) - Software architecture diagrams

---

*Dokumentacja architektoniczna - LLaMA-Factory Infrastructure*
