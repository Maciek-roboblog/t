# LLaMA-Factory - Kubernetes Infrastructure

## Co to jest?

Infrastruktura Kubernetes do **fine-tuningu modeli LLM** przy użyciu [LLaMA-Factory](https://github.com/hiyouga/LLaMA-Factory).

## Dlaczego?

| Problem | Rozwiązanie |
|---------|-------------|
| Fine-tuning wymaga GPU i specyficznej konfiguracji | Gotowe manifesty K8s z GPU affinity |
| Trudne zarządzanie modelami i danymi | Współdzielony NFS storage |
| Brak śledzenia eksperymentów | Integracja z MLflow |
| Skomplikowane wdrożenie inference | Zewnętrzny vLLM czyta z tego samego storage |

## Architektura

![Architektura](docs/diagrams/architecture.puml)

```
ZEWNĘTRZNE USŁUGI                    KUBERNETES
┌────────────────────────┐          ┌─────────────────────────┐
│  MLflow (metryki)      │◄─────────│  Training Job           │
│  NFS (storage)         │◄─────────│  Merge Job              │
│  vLLM (inference)      │◄─────────│  WebUI                  │
└────────────────────────┘          └─────────────────────────┘
```

**Kluczowa decyzja:** vLLM jest **zewnętrzną usługą** - nie wdrażamy go z tego repozytorium.

## Jak to działa?

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│ 1. PREPARE   │────►│ 2. TRAIN     │────►│ 3. MERGE     │────►│ 4. SERVE     │
│              │     │              │     │              │     │              │
│ Model + Data │     │ LoRA/QLoRA   │     │ Full model   │     │ vLLM API     │
│ na NFS       │     │ adapter      │     │ na NFS       │     │ (zewnętrzny) │
└──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘
```

## Szybki start

```bash
# 1. Konfiguracja
export PROJECT_ID="your-gcp-project"

# 2. Build & Deploy
./scripts/build.sh v1.0.0
./scripts/deploy.sh all

# 3. WebUI
./scripts/ui.sh webui
# http://localhost:7860
```

## Komendy

| Komenda | Co robi? |
|---------|----------|
| `./scripts/build.sh [tag]` | Buduje obraz Docker |
| `./scripts/deploy.sh all` | Wdraża całą infrastrukturę |
| `./scripts/train.sh` | Uruchamia job treningowy |
| `./scripts/ui.sh webui` | Port-forward do WebUI |
| `./scripts/ui.sh mlflow` | Port-forward do MLflow |
| `./scripts/status.sh` | Status wdrożenia |

## Wymagania

| Wymaganie | Opis |
|-----------|------|
| **Kubernetes** | Klaster z GPU nodes (NVIDIA) |
| **NFS Storage** | ReadWriteMany z modelami i danymi |
| **MLflow** | Opcjonalnie, do śledzenia eksperymentów |
| **vLLM** | Zewnętrzny serwer z dostępem do NFS |

## Dokumentacja

| Dokument | Cel | Dla kogo? |
|----------|-----|-----------|
| [DOKUMENTACJA.md](docs/DOKUMENTACJA.md) | **Architektura i koncepcje** | Architekci, MLOps |
| [PRZEWODNIK-UZYCIA.md](docs/PRZEWODNIK-UZYCIA.md) | Krok po kroku | ML Engineers |
| [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Rozwiązywanie problemów | Wszyscy |
| [ADR-001](docs/adr/001-model-registry.md) | Decyzja: Model Registry | Architekci |
| [ADR-002](docs/adr/002-vllm-deployment.md) | Decyzja: vLLM Deployment | Architekci |

## Źródła

- [LLaMA-Factory](https://github.com/hiyouga/LLaMA-Factory)
- [vLLM](https://docs.vllm.ai/)
- [MLflow](https://mlflow.org/)
