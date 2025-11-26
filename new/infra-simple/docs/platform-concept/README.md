# Platforma Fine-Tuningu LLM - Koncepcja Architektoniczna

## Spis treści
1. [Podsumowanie wykonawcze](#podsumowanie-wykonawcze)
2. [Architektura wysokopoziomowa](#architektura-wysokopoziomowa)
3. [Komponenty systemu](#komponenty-systemu)
4. [Workflow użytkownika](#workflow-użytkownika)
5. [Dwa podejścia do triggerowania treningu](#dwa-podejścia-do-triggerowania-treningu)
6. [Integracja z istniejącą infrastrukturą](#integracja-z-istniejącą-infrastrukturą)
7. [Decyzje architektoniczne (ADR)](#decyzje-architektoniczne-adr)
8. [Fazy wdrożenia](#fazy-wdrożenia)
9. [Otwarte kwestie i ryzyka](#otwarte-kwestie-i-ryzyka)

---

## Podsumowanie wykonawcze

Platforma umożliwia Data Scientistom fine-tuning modeli LLM (Large Language Models) w środowisku bankowym na Kubernetes z wykorzystaniem GPU. Głównym narzędziem jest **LLaMA Factory** - open-source'owa platforma do fine-tuningu, zintegrowana z **MLflow** do śledzenia eksperymentów i **vLLM** jako zewnętrzną usługą inference.

### Kluczowe założenia
- **Idempotentność** - każde wdrożenie jest powtarzalne
- **Zewnętrzne usługi** - vLLM, MLflow, NFS Storage są zewnętrzne
- **GPU-native** - wszystkie workloady treningu na węzłach GPU
- **Multi-tenancy** - izolacja przez namespace'y Kubernetes
- **Audytowalność** - pełne śledzenie kto, co i kiedy uruchomił

---

## Architektura wysokopoziomowa

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              UŻYTKOWNICY                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌──────────────────┐              ┌──────────────────┐                    │
│   │  Data Scientist  │              │  Data Scientist  │                    │
│   │    (WebUI)       │              │   (YAML/Git)     │                    │
│   └────────┬─────────┘              └────────┬─────────┘                    │
│            │                                  │                              │
│            │ Konfiguracja                     │ Commit YAML                  │
│            │ parametrów                       │ do GitLab                    │
│            ▼                                  ▼                              │
│   ┌──────────────────┐              ┌──────────────────┐                    │
│   │  LLaMA Factory   │              │  Jenkins/GitLab  │                    │
│   │     WebUI        │              │      CI/CD       │                    │
│   │   (Gradio)       │              │                  │                    │
│   └────────┬─────────┘              └────────┬─────────┘                    │
│            │                                  │                              │
│            └──────────────┬──────────────────┘                              │
│                           │                                                  │
│                           ▼                                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                         KUBERNETES CLUSTER                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                    Namespace: llm-training                           │   │
│   │                                                                      │   │
│   │  ┌───────────────┐    ┌───────────────┐    ┌───────────────┐        │   │
│   │  │  Training     │    │    Merge      │    │    WebUI      │        │   │
│   │  │    Job        │    │     Job       │    │  Deployment   │        │   │
│   │  │   (GPU)       │    │    (GPU)      │    │    (GPU)      │        │   │
│   │  └───────┬───────┘    └───────┬───────┘    └───────────────┘        │   │
│   │          │                    │                                      │   │
│   │          └────────────────────┴────────────────┐                    │   │
│   │                                                │                    │   │
│   │                                                ▼                    │   │
│   │  ┌─────────────────────────────────────────────────────────────┐   │   │
│   │  │                    PVC (NFS Storage)                         │   │   │
│   │  │  /storage/models/    /storage/output/    /storage/data/      │   │   │
│   │  └─────────────────────────────────────────────────────────────┘   │   │
│   │                                                                      │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                          USŁUGI ZEWNĘTRZNE                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌───────────────┐    ┌───────────────┐    ┌───────────────┐              │
│   │    MLflow     │    │  NFS Storage  │    │     vLLM      │              │
│   │   (Tracking   │    │ (ReadWriteMany│    │  (Inference   │              │
│   │  & Registry)  │    │    200Gi)     │    │   Service)    │              │
│   └───────────────┘    └───────────────┘    └───────────────┘              │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Komponenty systemu

### 1. LLaMA Factory
**Rola**: Główne narzędzie do fine-tuningu modeli LLM

**Funkcjonalności**:
- Wsparcie dla technik: LoRA, QLoRA, Full Fine-Tuning
- WebUI (Gradio) do konfiguracji parametrów
- Eksport konfiguracji do YAML
- Integracja z transformers, peft, datasets

**Ograniczenia**:
- Brak natywnego multi-tenancy (jedna instancja per namespace)
- Nie jest przystosowany do Enterprise - zaprojektowany dla pojedynczych użytkowników
- Równoległe sesje utrzymują osobne zadania

**Wersja**: LLaMA-Factory 0.9.3

### 2. MLflow
**Rola**: Platforma MLOps do śledzenia eksperymentów i zarządzania modelami

**Wykorzystanie**:
- **Experiment Tracking**: Logowanie metryk (loss, learning rate, epochs)
- **Model Registry**: Rejestracja wytrenowanych modeli
- **Artifact Storage**: Przechowywanie artefaktów treningu

**Integracja z LLaMA Factory**:
```bash
export MLFLOW_TRACKING_URI=http://mlflow-server:5000
# LLaMA Factory automatycznie loguje do MLflow
```

**Metryki automatycznie logowane**:
- Training loss
- Learning rate
- Epoch progress
- Custom metrics (wymagają dodatkowej konfiguracji)

### 3. vLLM (Zewnętrzna usługa)
**Rola**: Skalowalne serwowanie modeli LLM do inference

**Kluczowe decyzje**:
- vLLM jest **ZEWNĘTRZNĄ** usługą - nie deployujemy jej z tego repozytorium
- Czyta modele z tego samego NFS Storage (`/storage/models/merged-model`)
- Zapewnia izolację i niezależne skalowanie

**Dlaczego zewnętrzny**:
- Lepsza izolacja GPU między treningiem a inference
- Niezależne skalowanie
- Prostsze zarządzanie zasobami
- Unikanie contention na GPU

### 4. NFS Storage
**Rola**: Współdzielony system plików dla wszystkich komponentów

**Struktura katalogów**:
```
/storage/
├── models/
│   ├── base-model/           # Preładowane modele bazowe
│   └── merged-model/         # Output z merge job → vLLM czyta stąd
├── output/
│   ├── lora-adapter/         # Adaptery LoRA z treningu
│   └── checkpoints/          # Checkpointy do wznowienia
└── data/
    └── training-datasets/    # Datasety w formacie Alpaca/ShareGPT
```

**Specyfikacja**:
- Typ: ReadWriteMany (RWX)
- Rozmiar: 200Gi
- Dostęp: Wszystkie joby i deployments w namespace

### 5. Kubernetes Jobs
**Typy jobów**:

| Job | Cel | GPU | Opis |
|-----|-----|-----|------|
| Training Job | Fine-tuning modelu | Tak | Wykonuje trening z LLaMA Factory |
| Merge Job | Łączenie LoRA z base model | Tak | Tworzy finalny model do inference |

**Node Selector**:
```yaml
nodeSelector:
  nvidia.com/gpu: "true"
```

---

## Workflow użytkownika

### Pełny przepływ fine-tuningu

```
┌────────────────────────────────────────────────────────────────────────────┐
│                          FAZA 1: PRZYGOTOWANIE                              │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  1. Data Scientist przygotowuje dataset                                     │
│     └─→ Format: JSON array [{instruction, input, output}]                   │
│     └─→ Upload do: /storage/data/                                           │
│                                                                             │
│  2. Wybór modelu bazowego                                                   │
│     └─→ Z predefiniowanej listy (ConfigMap)                                 │
│     └─→ Lub z MLflow Model Registry                                         │
│                                                                             │
├────────────────────────────────────────────────────────────────────────────┤
│                          FAZA 2: KONFIGURACJA                               │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  OPCJA A: WebUI                          OPCJA B: YAML/Git                  │
│  ┌─────────────────────┐                 ┌─────────────────────┐            │
│  │ • Wybór modelu      │                 │ • Commit YAML       │            │
│  │ • Parametry LoRA    │                 │ • MR/PR approval    │            │
│  │ • Learning rate     │                 │ • CI walidacja      │            │
│  │ • Epochs            │                 │                     │            │
│  │ • Batch size        │                 │                     │            │
│  │ → Submit            │                 │ → Pipeline start    │            │
│  └─────────────────────┘                 └─────────────────────┘            │
│                                                                             │
├────────────────────────────────────────────────────────────────────────────┤
│                          FAZA 3: TRENING                                    │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    KUBERNETES TRAINING JOB                           │   │
│  │                                                                      │   │
│  │  PRE-TRAINING:                                                       │   │
│  │  • Walidacja konfiguracji                                            │   │
│  │  • Rejestracja parametrów w MLflow                                   │   │
│  │  • Hash datasetu do MLflow                                           │   │
│  │                                                                      │   │
│  │  TRAINING:                                                           │   │
│  │  • LLaMA Factory wykonuje fine-tuning                                │   │
│  │  • Logowanie metryk do MLflow (real-time)                            │   │
│  │  • Checkpointy zapisywane do NFS                                     │   │
│  │                                                                      │   │
│  │  POST-TRAINING:                                                      │   │
│  │  • Zapis adaptera LoRA do /storage/output/                           │   │
│  │  • Rejestracja modelu w MLflow                                       │   │
│  │                                                                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
├────────────────────────────────────────────────────────────────────────────┤
│                          FAZA 4: MERGE & DEPLOY                             │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  1. Merge Job łączy LoRA adapter z base model                              │
│     └─→ Output: /storage/models/merged-model/                              │
│                                                                             │
│  2. Pipeline CI/CD wdraża model na vLLM                                    │
│     └─→ ArgoCD synchronizuje konfigurację                                  │
│     └─→ vLLM ładuje nowy model                                             │
│                                                                             │
│  3. Rejestracja w API Gateway (Stream)                                     │
│     └─→ Model dostępny przez endpoint                                      │
│                                                                             │
└────────────────────────────────────────────────────────────────────────────┘
```

---

## Dwa podejścia do triggerowania treningu

### Podejście A: LLaMA Factory WebUI

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│    Data     │───▶│   WebUI     │───▶│ Kubernetes  │───▶│   MLflow    │
│  Scientist  │    │  (Gradio)   │    │    Job      │    │  Tracking   │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
```

**Zalety**:
- Intuicyjny interfejs graficzny
- Wizualizacja postępu (loss curve)
- Możliwość testowania modelu w wbudowanym chacie
- Eksport konfiguracji do YAML

**Wady**:
- Brak natywnej autoryzacji użytkowników
- Trudniejsza audytowalność (kto co uruchomił)
- Wymaga dodatkowego komponentu do utrzymania
- Problem z sesjami przy wielu użytkownikach

**Kiedy używać**:
- Eksperymentowanie i prototypowanie
- Szybkie testy parametrów
- Użytkownicy mniej techniczni

### Podejście B: YAML + Git + CI/CD

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│    Data     │───▶│   GitLab    │───▶│  Jenkins/   │───▶│ Kubernetes  │
│  Scientist  │    │   Commit    │    │   GitLab CI │    │    Job      │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
       │                  │                  │                  │
       │                  ▼                  │                  │
       │           ┌─────────────┐           │                  │
       │           │     MR      │◀──────────┘                  │
       │           │   Review    │                              │
       │           └─────────────┘                              │
       │                                                        │
       └────────────────────────────────────────────────────────┘
                         Audyt trail w Git
```

**Zalety**:
- Pełna audytowalność (Git history)
- Kontrola przez MR/PR i code review
- Łatwiejsza integracja z istniejącymi procesami CI/CD
- Możliwość walidacji przed uruchomieniem
- Nie wymaga dodatkowych komponentów UI

**Wady**:
- Wymaga znajomości formatu YAML
- Brak wizualizacji postępu w czasie rzeczywistym
- Mniej intuicyjne dla nie-programistów

**Kiedy używać**:
- Produkcyjne workloady
- Procesy wymagające audytu
- Powtarzalne eksperymenty

### Rekomendacja

**Faza 1 (MVP)**: Rozpocząć od podejścia B (YAML + Git)
- Prostsze do wdrożenia
- Lepsza audytowalność
- Wykorzystanie istniejącej infrastruktury CI/CD

**Faza 2**: Dodać WebUI jako opcję
- Po walidacji podstawowego flow
- Dla użytkowników eksperymentujących

---

## Integracja z istniejącą infrastrukturą

### Repozytoria i ArgoCD

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        STRUKTURA REPOZYTORIÓW                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Grupa: llm-finetuning/                                                  │
│  │                                                                       │
│  ├── llama-factory-image/        # Dockerfile + build pipeline          │
│  │   ├── Dockerfile                                                      │
│  │   ├── requirements.txt                                                │
│  │   └── .gitlab-ci.yml                                                  │
│  │                                                                       │
│  ├── training-jobs/               # Definicje jobów treningowych        │
│  │   ├── templates/                                                      │
│  │   │   └── training-job.yaml                                           │
│  │   └── configs/                 # Konfiguracje per eksperyment        │
│  │       └── experiment-001.yaml                                         │
│  │                                                                       │
│  └── argo-deployment/             # Helm charts + ArgoCD values         │
│      ├── charts/                                                         │
│      │   └── llm-training/                                               │
│      └── values/                                                         │
│          ├── dev.yaml                                                    │
│          └── prod.yaml                                                   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Pipeline CI/CD (Jenkins/GitLab CI)

```yaml
# Przykładowy pipeline dla treningu
stages:
  - validate
  - build
  - train
  - register

validate:
  stage: validate
  script:
    - python validate_config.py configs/experiment-001.yaml

build:
  stage: build
  script:
    - docker build -t llama-factory-train:$CI_COMMIT_SHA .
    - docker push $REGISTRY/llama-factory-train:$CI_COMMIT_SHA

train:
  stage: train
  script:
    - kubectl apply -f training-job.yaml
    - kubectl wait --for=condition=complete job/training-$CI_COMMIT_SHA

register:
  stage: register
  script:
    - python register_model.py --run-id $MLFLOW_RUN_ID
```

### Integracja z MLflow

**Zmienne środowiskowe w ConfigMap**:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: llm-training-config
data:
  MLFLOW_TRACKING_URI: "http://mlflow.mlplatform.svc:5000"
  MLFLOW_EXPERIMENT_NAME: "llm-finetuning"
```

**Automatyczne logowanie**:
- LLaMA Factory wspiera MLflow out-of-the-box
- Wystarczy ustawić `MLFLOW_TRACKING_URI`
- Custom metrics wymagają rozszerzenia skryptów

---

## Decyzje architektoniczne (ADR)

### ADR-001: Model Registry - NFS vs Object Storage vs MLflow

| Opcja | Zalety | Wady | Decyzja |
|-------|--------|------|---------|
| **NFS/PVC** | Prostota, szybki dostęp | Ograniczona skalowalność | **Faza 1** |
| Object Storage (GCS) | Skalowalność, multi-cluster | Większa złożoność | Faza 2+ |
| MLflow Registry | Wersjonowanie, audit | Wymaga integracji | Faza 2+ |

**Decyzja**: NFS na start, migracja do MLflow Registry w kolejnych fazach.

### ADR-002: vLLM - Zewnętrzny vs Wewnętrzny

| Aspekt | Zewnętrzny | Wewnętrzny |
|--------|------------|------------|
| Izolacja GPU | ✅ Pełna | ❌ Współdzielone |
| Skalowalność | ✅ Niezależna | ⚠️ Ograniczona |
| Prostota ops | ❌ Więcej komponentów | ✅ Jeden deployment |
| Zarządzanie | ✅ Dedykowany zespół | ❌ Nasze utrzymanie |

**Decyzja**: vLLM jako zewnętrzna usługa.

### ADR-003: Multi-tenancy

**Podejście**: Izolacja przez namespace'y Kubernetes

```
Namespace: tenant-a-training    → Zespół A
Namespace: tenant-b-training    → Zespół B
```

**Uzasadnienie**:
- LLaMA Factory nie wspiera multi-user natywnie
- Każdy tenant ma własną instancję
- Izolacja zasobów GPU przez resource quotas

### ADR-004: Orchestracja - Airflow vs Jenkins

| Aspekt | Airflow | Jenkins |
|--------|---------|---------|
| Podgląd postępu | ✅ DAG UI | ❌ Tylko logi |
| Równoległe joby | ⚠️ Problemy z tym samym DAG | ✅ Każdy build niezależny |
| Istniejąca infra | ⚠️ Nowe narzędzie | ✅ Już używamy |
| Długie joby | ✅ Przystosowany | ⚠️ Wymaga konfiguracji |

**Decyzja**: Jenkins dla MVP (prostota), Airflow jako opcja na przyszłość.

---

## Fazy wdrożenia

### Faza 1: MVP (Minimum Viable Product)

**Zakres**:
- [ ] Single-node training (jedna maszyna GPU)
- [ ] YAML/Git workflow (bez WebUI)
- [ ] Predefiniowany słownik modeli bazowych
- [ ] Podstawowa integracja z MLflow (tracking)
- [ ] Manual merge & deploy

**Komponenty do zbudowania**:
1. **Obraz Docker**: `llama-factory-train`
   - Base: Debian 11 + Python 3.10.14 + CUDA 11.8
   - LLaMA Factory 0.9.3 + PyTorch 2.1.2 + MLflow 2.10.0

2. **Kubernetes manifesty**:
   - Namespace, PVC, ConfigMap, Secrets
   - Training Job template

3. **Pipeline CI/CD**:
   - Build image
   - Validate config
   - Trigger training job

**Deliverables**:
- Działający przepływ: commit YAML → trening → model w NFS
- Metryki widoczne w MLflow
- Dokumentacja dla Data Scientistów

### Faza 2: Rozszerzenia

**Zakres**:
- [ ] WebUI (opcjonalnie)
- [ ] Dynamiczny słownik modeli (integracja z HuggingFace proxy)
- [ ] Automatyczny pipeline merge → vLLM deploy
- [ ] Multi-tenant (osobne namespace'y)
- [ ] Model Registry w MLflow

**Komponenty**:
- Zmodyfikowany LLaMA Factory WebUI z autoryzacją
- Integracja z Artifactory jako proxy do HuggingFace
- ArgoCD Application dla automatycznego deploy

### Faza 3: Enterprise

**Zakres**:
- [ ] Multi-node training (distributed)
- [ ] Zaawansowane metryki i benchmarki
- [ ] Integration testy modeli
- [ ] Automatyczne porównanie modeli
- [ ] Self-service portal

---

## Otwarte kwestie i ryzyka

### Kwestie do rozwiązania

| ID | Kwestia | Status | Właściciel |
|----|---------|--------|------------|
| Q1 | Skąd pobierać modele bazowe (HuggingFace, Artifactory)? | Otwarte | TBD |
| Q2 | Jak obsłużyć checkpointy przy padnięciu serwera? | Otwarte | TBD |
| Q3 | Autoryzacja użytkowników w WebUI | Otwarte | TBD |
| Q4 | Monitorowanie postępu długich jobów | Otwarte | TBD |
| Q5 | Integracja z Gateway dla nowych modeli | Otwarte | TBD |

### Ryzyka

| Ryzyko | Wpływ | Prawdopodobieństwo | Mitygacja |
|--------|-------|---------------------|-----------|
| LLaMA Factory nie skaluje się na Enterprise | Wysoki | Średni | Ewaluacja alternatyw (Axolotl, custom) |
| Brak natywnej autoryzacji w WebUI | Średni | Wysoki | Ścieżka YAML/Git jako primary |
| Konflikty GPU między treningiem a inference | Wysoki | Niski | vLLM jako zewnętrzna usługa |
| Długie czasy treningu blokują zasoby | Średni | Średni | Resource quotas, priorytetyzacja |

### Zależności zewnętrzne

- **MLflow**: Musi być dostępny i skonfigurowany
- **NFS Storage**: Wymagany dostęp RWX
- **GPU Nodes**: Minimum 1 węzeł z GPU
- **Artifactory**: Dla cache'owania modeli HuggingFace
- **Jenkins/GitLab CI**: Pipeline do budowania

---

## Następne kroki

1. **Natychmiastowe**:
   - Stworzenie grupy repozytoriów `llm-finetuning`
   - Build pierwszej wersji obrazu `llama-factory-train`
   - Setup namespace na dev cluster

2. **Krótkoterminowe**:
   - Implementacja training job template
   - Integracja z MLflow
   - Dokumentacja dla użytkowników

3. **Średnioterminowe**:
   - Automatyzacja merge → deploy
   - Ewaluacja WebUI
   - Multi-tenant setup

---

## Załączniki

### Dokumenty ADR
- [ADR-001: Model Registry](../adr/001-model-registry.md) - NFS vs Object Storage vs MLflow
- [ADR-002: vLLM Deployment](../adr/002-vllm-deployment.md) - Zewnętrzny vs Wewnętrzny

### Diagramy PlantUML
- [Architektura systemu](./diagrams/platform-architecture.puml) - Pełna architektura platformy
- [Workflow treningu](./diagrams/platform-workflow.puml) - Przepływ od konfiguracji do inference
- [Dwa podejścia](./diagrams/platform-two-approaches.puml) - WebUI vs YAML/Git
- [Komponenty](./diagrams/platform-components.puml) - Szczegółowy opis komponentów
- [Fazy wdrożenia](./diagrams/platform-phases.puml) - MVP → Rozszerzenia → Enterprise
- [Multi-tenancy](./diagrams/platform-multi-tenant.puml) - Izolacja przez namespace'y
- [CI/CD Integration](./diagrams/platform-cicd-integration.puml) - Integracja z pipeline'ami

### Inne
- [Przewodnik użycia](../PRZEWODNIK-UZYCIA.md) - Instrukcja dla Data Scientistów
