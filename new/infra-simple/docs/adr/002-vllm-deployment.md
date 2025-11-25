# ADR-002: vLLM Deployment - Wewnętrzny vs Zewnętrzny

## Status
**Propozycja** - do wyboru przez zespół

## Kontekst

vLLM to wysokowydajny silnik inference dla LLM. W obecnej architekturze vLLM jest **zewnętrzną usługą** - nie wdrażamy go z tego repozytorium. Istnieje jednak możliwość wdrożenia vLLM jako **wewnętrzny komponent** w tym samym klastrze Kubernetes.

**Pytanie architektoniczne:**
- **A) ZEWNĘTRZNY** (obecny stan) - oddzielna infrastruktura, zarządzana niezależnie
- **B) WEWNĘTRZNY** (nowa opcja) - wdrażany z tego repozytorium, wspólny klaster z treningiem

**Tło techniczne (2025):**

- [vLLM Production Stack](https://github.com/vllm-project/production-stack) - oficjalny framework do K8s (styczeń 2025)
- [llm-d](https://llm-d.ai/) - Kubernetes-native distributed inference (Red Hat, Google, NVIDIA - maj 2025)
- vLLM V1 alpha z 1.7x speedup (styczeń 2025)
- vLLM jako hosted project pod PyTorch Foundation (maj 2025)

---

## Opcje

---

### Opcja A: vLLM Zewnętrzny (obecna architektura)

![vLLM Zewnętrzny](../diagrams/adr002-external.puml)

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

![vLLM Wewnętrzny](../diagrams/adr002-internal.puml)

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
| **Latencja model load** | ⭐ | ⭐⭐⭐ | B szybsze (ten sam PVC) |
| **Niezależne skalowanie** | ⭐⭐⭐ | ⭐⭐ | A bardziej elastyczne |
| **Spójność wersji** | ⭐ | ⭐⭐⭐ | B gwarantowana |
| **Szybkość wdrożenia** | ⭐⭐ | ⭐⭐⭐ | B szybsze |
| **Audyt/compliance** | ⭐⭐⭐ | ⭐⭐ | A lepsza separacja |
| **Multi-team** | ⭐⭐⭐ | ⭐ | A dla dużych org |

### Wpływ na GPU

![GPU Management](../diagrams/adr002-gpu-management.puml)

**GPU Sharing Options (dla opcji B):**

| Metoda | Opis | Overhead |
|--------|------|----------|
| **Node affinity** | Różne nody dla training/inference | Brak |
| **Time-slicing** | Współdzielenie GPU w czasie | ~5-10% |
| **MIG (A100/H100)** | Hardware partitioning | ~5% |
| **Preemption** | vLLM ustępuje training | Latency spike |

### Wpływ na operacje

![Operational Impact](../diagrams/adr002-operational.puml)

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
- ✅ **Shared resources** - współdzielone GPU
- ✅ **Prototyping** - szybkie iteracje
- ✅ **Single cluster** - brak multi-region requirements

---

## Migracja (jeśli wybrano B)

### Etapy wdrożenia wewnętrznego vLLM:

![Plan Migracji](../diagrams/adr002-migration.puml)

---

## Rekomendacja

### Dla development/small teams: **Opcja B (Wewnętrzny)**

**Uzasadnienie:**
- Prostsze zarządzanie (jedno repo, jeden zespół)
- Współdzielone zasoby GPU
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
