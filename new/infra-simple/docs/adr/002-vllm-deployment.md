# ADR-002: vLLM Deployment - Wewnętrzny vs Zewnętrzny

## Status
**Propozycja** - do wyboru przez zespół

## Kontekst

vLLM to wysokowydajny silnik inference dla LLM. W obecnej architekturze vLLM jest **zewnętrzną usługą** - nie wdrażamy go z tego repozytorium. Istnieje jednak możliwość wdrożenia vLLM jako **wewnętrzny komponent** w tym samym klastrze Kubernetes.

```
┌────────────────────────────────────────────────────────────────────────┐
│                    PYTANIE ARCHITEKTONICZNE                             │
├────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   Czy vLLM powinien być:                                               │
│                                                                         │
│   A) ZEWNĘTRZNY (obecny stan)                                          │
│      └── Oddzielna infrastruktura, zarządzana niezależnie              │
│                                                                         │
│   B) WEWNĘTRZNY (nowa opcja)                                           │
│      └── Wdrażany z tego repozytorium, wspólny klaster z treningiem   │
│                                                                         │
└────────────────────────────────────────────────────────────────────────┘
```

**Tło techniczne (2025):**

- [vLLM Production Stack](https://github.com/vllm-project/production-stack) - oficjalny framework do K8s (styczeń 2025)
- [llm-d](https://llm-d.ai/) - Kubernetes-native distributed inference (Red Hat, Google, NVIDIA - maj 2025)
- vLLM V1 alpha z 1.7x speedup (styczeń 2025)
- vLLM jako hosted project pod PyTorch Foundation (maj 2025)

---

## Opcje

---

### Opcja A: vLLM Zewnętrzny (obecna architektura)

```
┌────────────────────────────────────────────────────────────────────────┐
│                         ARCHITEKTURA ZEWNĘTRZNA                         │
├────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   KUBERNETES CLUSTER (Training)      │    ZEWNĘTRZNA INFRASTRUKTURA   │
│   ┌────────────────────────────┐    │    ┌────────────────────────┐   │
│   │  Namespace: llm-training   │    │    │     vLLM Server(s)     │   │
│   │  ┌──────────────────────┐  │    │    │  ┌────────────────┐    │   │
│   │  │   LLaMA-Factory      │  │    │    │  │  GPU Node 1    │    │   │
│   │  │   - WebUI            │  │    │    │  │  vLLM instance │    │   │
│   │  │   - Training Job     │  │    │    │  └────────────────┘    │   │
│   │  │   - Merge Job        │  │    │    │  ┌────────────────┐    │   │
│   │  └──────────┬───────────┘  │    │    │  │  GPU Node 2    │    │   │
│   │             │              │    │    │  │  vLLM instance │    │   │
│   └─────────────┼──────────────┘    │    │  └────────────────┘    │   │
│                 │                    │    └──────────┬─────────────┘   │
│                 │                    │               │                  │
│                 ▼                    │               ▼                  │
│   ┌──────────────────────────────────┴───────────────────────────────┐ │
│   │                    NFS Storage (SharedStorage)                    │ │
│   │              /storage/models/merged-model                         │ │
│   └──────────────────────────────────────────────────────────────────┘ │
│                                                                         │
└────────────────────────────────────────────────────────────────────────┘
```

**Charakterystyka:**

| Aspekt | Opis |
|--------|------|
| **Zarządzanie** | Oddzielne repo/team dla vLLM |
| **GPU** | Dedykowane GPU dla inference |
| **Skalowanie** | Niezależne od training |
| **Sieć** | Może być inny klaster/region |
| **Aktualizacje** | Oddzielne cykle release |

**Implementacja:**

Brak manifestów vLLM w tym repozytorium. vLLM uruchamiany oddzielnie:

```bash
# Na zewnętrznym serwerze/klastrze
vllm serve /storage/models/merged-model \
  --host 0.0.0.0 \
  --port 8000 \
  --tensor-parallel-size 1 \
  --gpu-memory-utilization 0.9
```

---

### Opcja B: vLLM Wewnętrzny (nowa możliwość)

```
┌────────────────────────────────────────────────────────────────────────┐
│                         ARCHITEKTURA WEWNĘTRZNA                         │
├────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   KUBERNETES CLUSTER (Unified)                                         │
│   ┌────────────────────────────────────────────────────────────────┐   │
│   │  Namespace: llm-training                                        │   │
│   │  ┌──────────────────────┐        ┌──────────────────────┐      │   │
│   │  │   LLaMA-Factory      │        │      vLLM Server      │      │   │
│   │  │   - WebUI            │        │   (Deployment/Helm)   │      │   │
│   │  │   - Training Job     │        │                       │      │   │
│   │  │   - Merge Job        │        │   OpenAI-compatible   │      │   │
│   │  └──────────┬───────────┘        │   API :8000           │      │   │
│   │             │                     └───────────┬───────────┘      │   │
│   │             │                                 │                   │   │
│   │             ▼                                 ▼                   │   │
│   │  ┌──────────────────────────────────────────────────────────┐   │   │
│   │  │              PVC: llama-storage (NFS)                     │   │   │
│   │  │           /storage/models/merged-model                    │   │   │
│   │  └──────────────────────────────────────────────────────────┘   │   │
│   │                                                                  │   │
│   │  GPU Nodes:                                                      │   │
│   │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │   │
│   │  │   Node 1     │  │   Node 2     │  │   Node 3     │          │   │
│   │  │ Training GPU │  │ Training GPU │  │ vLLM GPU     │          │   │
│   │  │   (Jobs)     │  │   (spare)    │  │ (inference)  │          │   │
│   │  └──────────────┘  └──────────────┘  └──────────────┘          │   │
│   │                                                                  │   │
│   └──────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└────────────────────────────────────────────────────────────────────────┘
```

**Charakterystyka:**

| Aspekt | Opis |
|--------|------|
| **Zarządzanie** | Jedno repo, jeden team |
| **GPU** | Współdzielone lub dedykowane w tym samym klastrze |
| **Skalowanie** | Koordynowane |
| **Sieć** | Wewnętrzna komunikacja (niższa latencja) |
| **Aktualizacje** | Skoordynowane cykle release |

**Implementacja (nowy manifest `k8s/07-vllm-inference.yaml`):**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vllm-inference
  namespace: llm-training
spec:
  replicas: 1
  selector:
    matchLabels:
      app: vllm-inference
  template:
    metadata:
      labels:
        app: vllm-inference
    spec:
      nodeSelector:
        nvidia.com/gpu: "true"
      tolerations:
      - key: "nvidia.com/gpu"
        operator: "Exists"
        effect: "NoSchedule"
      containers:
      - name: vllm
        image: vllm/vllm-openai:v0.6.4
        args:
        - "--model"
        - "/storage/models/merged-model"
        - "--host"
        - "0.0.0.0"
        - "--port"
        - "8000"
        - "--gpu-memory-utilization"
        - "0.9"
        - "--trust-remote-code"
        ports:
        - containerPort: 8000
        volumeMounts:
        - name: storage
          mountPath: /storage
        resources:
          limits:
            nvidia.com/gpu: "1"
      volumes:
      - name: storage
        persistentVolumeClaim:
          claimName: llama-storage
---
apiVersion: v1
kind: Service
metadata:
  name: vllm-inference
  namespace: llm-training
spec:
  selector:
    app: vllm-inference
  ports:
  - port: 8000
    targetPort: 8000
  type: ClusterIP
```

---

## Porównanie szczegółowe

### Matryca decyzyjna

| Kryterium | Zewnętrzny (A) | Wewnętrzny (B) | Komentarz |
|-----------|----------------|----------------|-----------|
| **Złożoność operacyjna** | ⭐⭐⭐ | ⭐⭐ | B łatwiejsze, jedno repo |
| **Izolacja błędów** | ⭐⭐⭐ | ⭐ | A lepsza izolacja |
| **Izolacja zasobów GPU** | ⭐⭐⭐ | ⭐⭐ | A dedykowane GPU |
| **Koszt infrastruktury** | ⭐ | ⭐⭐⭐ | B tańsze (shared) |
| **Latencja model load** | ⭐ | ⭐⭐⭐ | B szybsze (ten sam PVC) |
| **Niezależne skalowanie** | ⭐⭐⭐ | ⭐⭐ | A bardziej elastyczne |
| **Spójność wersji** | ⭐ | ⭐⭐⭐ | B gwarantowana |
| **Szybkość wdrożenia** | ⭐⭐ | ⭐⭐⭐ | B szybsze |
| **Audyt/compliance** | ⭐⭐⭐ | ⭐⭐ | A lepsza separacja |
| **Multi-team** | ⭐⭐⭐ | ⭐ | A dla dużych org |

### Wpływ na GPU

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    GPU RESOURCE MANAGEMENT                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   OPCJA A: ZEWNĘTRZNY                                                   │
│   ┌─────────────────────┐    ┌─────────────────────┐                   │
│   │  Training Cluster   │    │  Inference Cluster  │                   │
│   │  GPU 1: Training    │    │  GPU 1: vLLM        │                   │
│   │  GPU 2: Training    │    │  GPU 2: vLLM        │                   │
│   │  GPU 3: (idle)      │    │  GPU 3: vLLM        │                   │
│   └─────────────────────┘    └─────────────────────┘                   │
│   + Pełna izolacja                                                      │
│   + Niezależne skalowanie                                               │
│   - Wyższy koszt (idle GPU)                                            │
│   - Duplikacja infrastruktury                                           │
│                                                                          │
│   ═══════════════════════════════════════════════════════════════════   │
│                                                                          │
│   OPCJA B: WEWNĘTRZNY                                                   │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │  Unified Cluster                                                 │   │
│   │  GPU 1: Training (podczas treningu) → vLLM (po merge)           │   │
│   │  GPU 2: Training / spare                                        │   │
│   │  GPU 3: vLLM (dedicated)                                        │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│   + Lepsze wykorzystanie GPU                                            │
│   + Niższy koszt                                                        │
│   - Potencjalne konflikty zasobów                                      │
│   - Wymaga GPU time-slicing lub MIG                                    │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

**GPU Sharing Options (dla opcji B):**

| Metoda | Opis | Overhead |
|--------|------|----------|
| **Node affinity** | Różne nody dla training/inference | Brak |
| **Time-slicing** | Współdzielenie GPU w czasie | ~5-10% |
| **MIG (A100/H100)** | Hardware partitioning | ~5% |
| **Preemption** | vLLM ustępuje training | Latency spike |

### Wpływ na operacje

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    OPERATIONAL IMPACT                                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   DEPLOYMENT                                                            │
│   ├── Zewnętrzny: 2 zespoły, 2 procesy CI/CD                          │
│   └── Wewnętrzny: 1 zespół, 1 proces CI/CD                            │
│                                                                          │
│   MONITORING                                                            │
│   ├── Zewnętrzny: Oddzielne dashboardy                                │
│   └── Wewnętrzny: Unified observability                               │
│                                                                          │
│   TROUBLESHOOTING                                                       │
│   ├── Zewnętrzny: "To nie nasz problem" syndrom                       │
│   └── Wewnętrzny: End-to-end visibility                               │
│                                                                          │
│   UPGRADES                                                              │
│   ├── Zewnętrzny: Niezależne, potencjalne incompatibility             │
│   └── Wewnętrzny: Atomowe, testowane razem                            │
│                                                                          │
│   ROLLBACK                                                              │
│   ├── Zewnętrzny: Skomplikowane (koordynacja)                         │
│   └── Wewnętrzny: Proste (jeden helm release)                         │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Wpływ na architekturę repozytorium

**Zewnętrzny (obecny):**
```
infra-simple/
├── docker/
│   └── Dockerfile.train        # Tylko training
├── k8s/
│   ├── 01-namespace.yaml
│   ├── 02-secrets.yaml
│   ├── 03-pvc.yaml
│   ├── 04-configmap.yaml
│   ├── 05-llama-webui.yaml
│   ├── 06-training-job.yaml
│   └── 09-merge-model-job.yaml
└── scripts/
    ├── deploy.sh               # Bez inference
    └── ui.sh                   # webui, mlflow only
```

**Wewnętrzny (zmiana):**
```
infra-simple/
├── docker/
│   └── Dockerfile.train        # Bez zmian (vLLM używa oficjalnego obrazu)
├── k8s/
│   ├── 01-namespace.yaml
│   ├── 02-secrets.yaml
│   ├── 03-pvc.yaml
│   ├── 04-configmap.yaml
│   ├── 05-llama-webui.yaml
│   ├── 06-training-job.yaml
│   ├── 07-vllm-inference.yaml  # ← NOWY
│   ├── 08-vllm-service.yaml    # ← NOWY (lub w 07)
│   └── 09-merge-model-job.yaml
├── helm/                        # ← OPCJONALNIE
│   └── vllm-production-stack/   # vLLM official Helm chart
└── scripts/
    ├── deploy.sh               # + opcja inference
    ├── ui.sh                   # + opcja vllm (port-forward)
    └── reload-model.sh         # ← NOWY (restart vLLM po merge)
```

### Wpływ na bezpieczeństwo

| Aspekt | Zewnętrzny | Wewnętrzny |
|--------|------------|------------|
| **Network exposure** | Wymaga external LB/Ingress | ClusterIP wystarczy |
| **Blast radius** | Ograniczony do inference | Training + Inference |
| **Secret management** | Oddzielne sekrety | Wspólne sekrety |
| **RBAC** | Prostsze (izolacja) | Bardziej złożone |
| **Compliance** | Łatwiejsze SOC2/ISO | Wymaga dodatkowej pracy |

### Wpływ na koszty

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    COST COMPARISON (przykład)                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   Założenia:                                                            │
│   - 2 GPU nodes dla training (A100 40GB)                               │
│   - Trening: 20 godzin/tydzień                                         │
│   - Inference: 24/7                                                     │
│   - GCP pricing: ~$2.9/GPU/godz (A100)                                 │
│                                                                          │
│   OPCJA A: ZEWNĘTRZNY                                                   │
│   ├── Training cluster: 2 GPU × 168h × $2.9 = $975/tydzień            │
│   ├── Inference cluster: 2 GPU × 168h × $2.9 = $975/tydzień           │
│   └── RAZEM: ~$1,950/tydzień                                           │
│                                                                          │
│   OPCJA B: WEWNĘTRZNY (z GPU sharing)                                  │
│   ├── Unified cluster: 3 GPU × 168h × $2.9 = $1,461/tydzień           │
│   │   - 1 GPU: dedicated inference (24/7)                              │
│   │   - 2 GPU: training (20h) + inference overflow                     │
│   └── RAZEM: ~$1,461/tydzień                                           │
│                                                                          │
│   OSZCZĘDNOŚĆ: ~25% ($489/tydzień, ~$25k/rok)                          │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Scenariusze użycia

### Kiedy wybrać ZEWNĘTRZNY (A):

- ✅ **Duża organizacja** z oddzielnymi zespołami ML/Platform
- ✅ **Wysokie SLA** dla inference (99.99% uptime)
- ✅ **Compliance** wymaga izolacji (SOC2, HIPAA)
- ✅ **Multi-region** deployment inference
- ✅ **Różne cykle życia** - inference zmienia się rzadziej
- ✅ **vLLM already exists** - nie reinvent the wheel

### Kiedy wybrać WEWNĘTRZNY (B):

- ✅ **Mały zespół** (< 5 osób) zarządzający wszystkim
- ✅ **Development/staging** environment
- ✅ **Tight integration** - szybkie testy po treningu
- ✅ **Cost optimization** - współdzielone GPU
- ✅ **Prototyping** - szybkie iteracje
- ✅ **Single cluster** - brak multi-region requirements

---

## Migracja (jeśli wybrano B)

### Etapy wdrożenia wewnętrznego vLLM:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    PLAN MIGRACJI                                         │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   FAZA 1: Przygotowanie (1-2 dni)                                      │
│   ├── [ ] Dodaj k8s/07-vllm-inference.yaml                            │
│   ├── [ ] Zaktualizuj scripts/deploy.sh                               │
│   ├── [ ] Zaktualizuj scripts/ui.sh (port-forward)                    │
│   └── [ ] Przetestuj na dev cluster                                   │
│                                                                          │
│   FAZA 2: Parallel run (1 tydzień)                                     │
│   ├── [ ] Deploy wewnętrzny vLLM (nie eksponowany)                    │
│   ├── [ ] Porównaj odpowiedzi z zewnętrznym                           │
│   ├── [ ] Zmierz latencję i throughput                                │
│   └── [ ] Monitoruj GPU utilization                                   │
│                                                                          │
│   FAZA 3: Cutover                                                       │
│   ├── [ ] Przełącz ruch na wewnętrzny vLLM                            │
│   ├── [ ] Zatrzymaj zewnętrzny (ale nie usuwaj)                       │
│   └── [ ] Monitoruj przez 48h                                         │
│                                                                          │
│   FAZA 4: Cleanup                                                       │
│   ├── [ ] Usuń zewnętrzną infrastrukturę vLLM                         │
│   └── [ ] Zaktualizuj dokumentację                                    │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Rekomendacja

### Dla development/small teams: **Opcja B (Wewnętrzny)**

**Uzasadnienie:**
- Prostsze zarządzanie (jedno repo, jeden zespół)
- Niższe koszty (współdzielone GPU)
- Szybsze iteracje (deploy → train → merge → test)
- End-to-end visibility

### Dla production/enterprise: **Opcja A (Zewnętrzny)**

**Uzasadnienie:**
- Lepsza izolacja błędów
- Niezależne skalowanie
- Łatwiejsze compliance
- Oddzielne SLA

### Hybrydowe podejście:

```
DEV/STAGING: Wewnętrzny vLLM (w tym repo)
     │
     │ promote model
     ▼
PRODUCTION: Zewnętrzny vLLM (oddzielna infrastruktura)
```

---

## Decyzja

**[DO UZUPEŁNIENIA]**

Wybrana opcja: ________________

Uzasadnienie: ________________

---

## Konsekwencje wybranej opcji

### Jeśli wybrano A (Zewnętrzny):

| Zmiana | Wpływ |
|--------|-------|
| Repo | Bez zmian |
| Dokumentacja | Jasne wskazanie że vLLM jest zewnętrzny |
| Deploy | Oddzielny proces dla vLLM |
| Monitoring | Oddzielne dashboardy |

### Jeśli wybrano B (Wewnętrzny):

| Zmiana | Wpływ |
|--------|-------|
| Repo | + `k8s/07-vllm-inference.yaml`, + scripts |
| Dokumentacja | Aktualizacja architecture docs |
| Deploy | `./deploy.sh all` zawiera vLLM |
| Monitoring | Unified observability |
| GPU | Konfiguracja node affinity/taints |

---

## Źródła

- [vLLM Production Stack](https://github.com/vllm-project/production-stack) - oficjalny K8s deployment
- [vLLM Kubernetes Docs](https://docs.vllm.ai/en/latest/deployment/k8s/)
- [llm-d: Kubernetes-native distributed inference](https://llm-d.ai/)
- [Deploying vLLM on Kubernetes with HPA](https://medium.com/@shivank1128/deploying-a-production-ready-vllm-stack-on-kubernetes-with-hpa-autoscaling-107501b8b687)
- [Why vLLM is the best choice for AI inference (2025)](https://developers.redhat.com/articles/2025/10/30/why-vllm-best-choice-ai-inference-today)
- [AI/ML on Kubernetes with vLLM](https://dzone.com/articles/ai-ml-kubernetes-mlflow-kserve-vllm)
- [vLLM 2025 Vision](https://blog.vllm.ai/2025/01/10/vllm-2024-wrapped-2025-vision.html)

---

*ADR utworzony: 2025-11-25*
