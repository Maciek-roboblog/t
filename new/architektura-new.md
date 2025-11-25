# Architektura platformy LLM Fine-tuning

## 1. Wprowadzenie

Dokument opisuje architekturę platformy do fine-tuningu i serwowania modeli LLM w środowisku korporacyjnym. Platforma wykorzystuje LLaMA-Factory do treningu, vLLM do inferencji oraz MLFlow jako rejestr modeli i narzędzie do experiment tracking.

---

## 2. Założenia i polityki organizacji

### 2.1. Infrastruktura

| Komponent | Wartość |
|-----------|---------|
| **Platforma** | Google Kubernetes Engine (GKE) |
| **Region** | EU (Holandia) |
| **GPU** | NVIDIA A100 (zalecane) |
| **System bazowy** | Debian 12 |
| **Python** | 3.11 |

### 2.2. Polityki bezpieczeństwa

| Polityka | Realizacja |
|----------|------------|
| **Autoryzacja** | Workload Identity (GCP) |
| **Ruch sieciowy** | Przez Gateway (brak bezpośredniego dostępu do modeli) |
| **Izolacja** | Namespace per workspace |
| **Logowanie** | Gateway loguje requesty/responsy |
| **Guardrails** | Gateway filtruje treści |

### 2.3. Multitenancy

Platforma wspiera model **workspace'ów** - logicznych jednostek między projektem a zespołem:

- Każdy workspace = osobny namespace w K8s
- Dedykowana instancja MLFlow per workspace
- Możliwość wygaszania/usuwania nieaktywnych workspace'ów
- Wspólne zasoby (Gateway, modele bazowe) w namespace `llm-shared`

---

## 3. Komponenty systemu

### 3.1. Mapa komponentów

```plantuml
@startuml
!theme plain
skinparam componentStyle rectangle
skinparam defaultTextAlignment center

package "CI/CD" {
  [GitLab] as git
  [Jenkins] as jenkins
  [Artifact Registry] as registry
}

package "Namespace: llm-shared" {
  [Gateway] as gateway
  [Strapi CMS] as strapi
  [Konsola Streamlit] as streamlit
  [MLFlow Common] as mlflow_common
}

package "Namespace: llm-workspace-*" {
  [LLaMA-Factory WebUI] as llama_ui
  [MLFlow Workspace] as mlflow_ws
  [vLLM Service] as vllm
  [Training Jobs] as jobs
  database "PVC Storage" as pvc
}

cloud "Airflow" as airflow

actor "Data Scientist" as dev
actor "Aplikacja kliencka" as app

' CI/CD flow
dev --> git : commit
git --> jenkins : webhook
jenkins --> registry : build & push
jenkins --> airflow : trigger DAG

' Training flow
dev --> llama_ui : fine-tuning
llama_ui --> mlflow_common : pobierz model bazowy
llama_ui --> jobs : trigger
airflow --> jobs : orchestration
jobs --> pvc : zapisz model
jobs --> mlflow_ws : rejestruj model

' Inference flow
dev --> streamlit : testowanie
streamlit --> gateway : request
app --> gateway : request
gateway --> vllm : inference
vllm --> pvc : wagi modelu
vllm --> mlflow_ws : pobierz model

' Config
strapi --> gateway : konfiguracja

@enduml
```

### 3.2. Opis komponentów

#### Warstwa CI/CD

| Komponent | Rola | Technologia |
|-----------|------|-------------|
| **GitLab** | Repozytorium kodu, konfiguracji YAML, Dockerfile'ów | GitLab CE/EE |
| **Jenkins** | Pipeline'y CI/CD, budowanie obrazów, triggerowanie Airflow | Jenkins |
| **Artifact Registry** | Przechowywanie obrazów Docker | GCP Artifact Registry |
| **Airflow** | Orkiestracja workflow'ów treningowych | Apache Airflow |

#### Warstwa wspólna (llm-shared)

| Komponent | Rola | Technologia |
|-----------|------|-------------|
| **Gateway** | Routing, autoryzacja, guardrails, logowanie | Custom (wewnętrzny) |
| **Strapi** | CMS do konfiguracji Gateway'a (modele, limity, uprawnienia) | Strapi |
| **Konsola Streamlit** | UI do testowania promptów, porównywania modeli | Streamlit |
| **MLFlow Common** | Rejestr modeli bazowych (Llama-3, Mistral, etc.) | MLFlow |

#### Warstwa workspace'u (llm-workspace-*)

| Komponent | Rola | Technologia |
|-----------|------|-------------|
| **LLaMA-Factory WebUI** | UI do fine-tuningu, konfiguracji, monitoringu | LLaMA-Factory |
| **MLFlow Workspace** | Experiment tracking, rejestr wytrenowanych modeli | MLFlow |
| **vLLM Service** | Serwowanie modeli (OpenAI-compatible API) | vLLM |
| **Training Jobs** | Joby treningowe na GPU | Kubernetes Jobs |
| **PVC Storage** | Przechowywanie wag modeli, checkpointów | GKE Persistent Volume |

---

## 4. Narzędzia użytkownika

### 4.1. LLaMA-Factory WebUI

**Przeznaczenie:** Fine-tuning modeli LLM

**Funkcjonalności:**
- Wybór modelu bazowego z MLFlow Common
- Konfiguracja parametrów treningu (LoRA, QLoRA, full fine-tuning)
- Wybór datasetu (lokalne, Hugging Face mirror)
- Monitoring postępu treningu w czasie rzeczywistym
- Eksport konfiguracji do YAML
- Integracja z MLFlow (experiment tracking)

**Ograniczenia:**
- Jedna instancja per workspace (brak natywnego multitenancy)
- Równoległe sesje otrzymują osobne ID zadań

```plantuml
@startuml
!theme plain
skinparam actorStyle awesome

actor "Data Scientist" as user

rectangle "LLaMA-Factory WebUI" {
  usecase "Wybór modelu bazowego" as uc1
  usecase "Konfiguracja treningu" as uc2
  usecase "Monitoring postępu" as uc3
  usecase "Eksport konfiguracji" as uc4
}

database "MLFlow Common" as mlflow_c
database "MLFlow Workspace" as mlflow_w
node "K8s Job (GPU)" as job

user --> uc1
user --> uc2
user --> uc3
user --> uc4

uc1 --> mlflow_c : lista modeli
uc2 --> job : trigger
uc3 --> job : status
job --> mlflow_w : metryki + model

@enduml
```

### 4.2. Konsola Streamlit

**Przeznaczenie:** Testowanie i ewaluacja wytrenowanych modeli

**Funkcjonalności:**
- Lista wszystkich modeli dostępnych przez Gateway
- Testowanie promptów
- Porównywanie odpowiedzi side-by-side
- Historia konwersacji
- Metryki (latency, tokens/s)

**Integracja:**
- Pobiera listę modeli z Strapi
- Komunikuje się z modelami przez Gateway (z autoryzacją)

```plantuml
@startuml
!theme plain
skinparam actorStyle awesome

actor "Data Scientist" as user

rectangle "Konsola Streamlit" {
  usecase "Lista modeli" as uc1
  usecase "Test promptów" as uc2
  usecase "Porównanie modeli" as uc3
  usecase "Historia" as uc4
}

node "Gateway" as gateway
database "Strapi" as strapi
node "vLLM Services" as vllm

user --> uc1
user --> uc2
user --> uc3
user --> uc4

uc1 --> strapi : config
uc2 --> gateway : request
uc3 --> gateway : multi-request
gateway --> vllm : inference

@enduml
```

### 4.3. Porównanie narzędzi UI

```plantuml
@startuml
!theme plain
skinparam defaultTextAlignment center

rectangle "WORKFLOW DATA SCIENTISTA" {

  rectangle "1. FINE-TUNING" #LightBlue {
    rectangle "LLaMA-Factory WebUI" as ui1 {
      (Wybór modelu) as f1
      (Konfiguracja) as f2
      (Trening) as f3
      (Monitoring) as f4
    }
  }

  rectangle "2. TESTOWANIE" #LightGreen {
    rectangle "Konsola Streamlit" as ui2 {
      (Test promptów) as t1
      (Porównanie) as t2
      (Ewaluacja) as t3
    }
  }

  f4 -right-> t1 : Model\ngotowy

}

database "MLFlow" as mlflow
node "Gateway" as gw
node "vLLM" as vllm

ui1 -down-> mlflow
ui2 -down-> gw
gw -down-> vllm

@enduml
```

---

## 5. Przepływy danych

### 5.1. Flow: Fine-tuning przez WebUI

```plantuml
@startuml
!theme plain
skinparam sequenceMessageAlign center

actor "Data Scientist" as dev
participant "LLaMA-Factory\nWebUI" as ui
database "MLFlow\nCommon" as mlflow_c
database "MLFlow\nWorkspace" as mlflow_w
participant "Kubernetes" as k8s
participant "Training Job\n(GPU)" as job
database "PVC" as pvc

== Inicjalizacja ==
dev -> ui : Otwarcie WebUI
ui -> mlflow_c : GET /models
mlflow_c --> ui : Lista modeli bazowych\n(Llama-3-8B, Mistral-7B, ...)

== Konfiguracja ==
dev -> ui : Wybór modelu: Llama-3-8B
dev -> ui : Wybór datasetu: corp-qa-v1
dev -> ui : Parametry:\n- LoRA rank: 8\n- Learning rate: 1e-4\n- Epochs: 3

== Trening ==
dev -> ui : START
ui -> k8s : Create Job\n(GPU request: 1)
k8s -> job : Schedule on GPU node
activate job

job -> mlflow_c : Download base model
mlflow_c --> job : Model weights (~16GB)
job -> pvc : Cache model

loop Każda epoka
  job -> mlflow_w : Log metrics\n(loss, lr, step)
  job --> ui : Progress update
  ui --> dev : Wizualizacja\n(loss curve)
end

job -> pvc : Save checkpoint
job -> mlflow_w : Register model\n"ft-llama3-8b-corp-v1"
deactivate job

mlflow_w --> ui : Model registered
ui --> dev : SUKCES:\nModel: ft-llama3-8b-corp-v1

@enduml
```

### 5.2. Flow: Testowanie przez Streamlit

```plantuml
@startuml
!theme plain
skinparam sequenceMessageAlign center

actor "Data Scientist" as dev
participant "Konsola\nStreamlit" as console
participant "Gateway" as gw
database "Strapi" as strapi
participant "vLLM\nService" as vllm
database "MLFlow\nWorkspace" as mlflow

== Inicjalizacja ==
dev -> console : Otwarcie konsoli
console -> strapi : GET /models
strapi --> console : Lista modeli:\n- ft-llama3-8b-corp-v1\n- ft-mistral-7b-code-v2\n- ...

== Testowanie ==
dev -> console : Wybór: ft-llama3-8b-corp-v1
dev -> console : Prompt:\n"Jak złożyć reklamację?"

console -> gw : POST /v1/chat/completions\n+ Authorization header
gw -> gw : Sprawdź uprawnienia
gw -> gw : Apply guardrails

gw -> vllm : Forward request
note right of vllm : Model już załadowany\nz MLFlow przy starcie

vllm --> gw : Response:\n"Aby złożyć reklamację..."
gw -> gw : Log request/response
gw --> console : Response + metadata

console --> dev : Odpowiedź + metryki:\n- Latency: 1.2s\n- Tokens: 156\n- Tokens/s: 130

@enduml
```

### 5.3. Flow: CI/CD (Jenkins + Airflow)

```plantuml
@startuml
!theme plain
skinparam sequenceMessageAlign center

actor "Data Scientist" as dev
participant "GitLab" as git
participant "Jenkins" as jenkins
participant "Airflow" as airflow
database "MLFlow\nCommon" as mlflow_c
database "MLFlow\nWorkspace" as mlflow_w
participant "Kubernetes" as k8s
participant "Download\nJob" as job_dl
participant "Training\nJob" as job_train
database "PVC" as pvc

== Commit ==
dev -> git : git push\n(train_config.yaml)
git -> jenkins : Webhook trigger

== Pipeline ==
jenkins -> jenkins : Validate YAML
jenkins -> airflow : Trigger DAG:\nllm_finetune_workflow\n+ params

== Airflow DAG ==
airflow -> mlflow_w : Create experiment
mlflow_w --> airflow : experiment_id

airflow -> k8s : Create Job:\ndownload-base-model
k8s -> job_dl : Start
activate job_dl
job_dl -> mlflow_c : Download model
job_dl -> pvc : Save to /models
deactivate job_dl

airflow -> k8s : Create Job:\nllama-fine-tune
k8s -> job_train : Start (GPU)
activate job_train
job_train -> pvc : Load base model
job_train -> mlflow_w : Log metrics
job_train -> pvc : Save trained model
job_train -> mlflow_w : Register model
deactivate job_train

airflow --> dev : Slack/Email:\nTraining complete

@enduml
```

---

## 6. Architektura sieciowa

### 6.1. Diagram sieci

```plantuml
@startuml
!theme plain
skinparam linetype ortho

cloud "Internet" as inet

rectangle "GKE Cluster" {

  rectangle "Namespace: llm-shared" #LightBlue {
    node "Gateway\n(LoadBalancer)" as gw
    node "Strapi" as strapi
    node "Streamlit" as streamlit
    node "MLFlow Common" as mlflow_c
  }

  rectangle "Namespace: llm-workspace-alpha" #LightGreen {
    node "WebUI" as ui_a
    node "MLFlow" as mlflow_a
    node "vLLM" as vllm_a
  }

  rectangle "Namespace: llm-workspace-beta" #LightYellow {
    node "WebUI" as ui_b
    node "MLFlow" as mlflow_b
    node "vLLM" as vllm_b
  }

}

inet --> gw : HTTPS (443)
gw --> vllm_a : HTTP (8000)
gw --> vllm_b : HTTP (8000)
streamlit --> gw : HTTP
strapi --> gw : config

ui_a --> mlflow_a : HTTP (5000)
ui_a --> mlflow_c : HTTP (5000)
ui_b --> mlflow_b : HTTP (5000)
ui_b --> mlflow_c : HTTP (5000)

note right of gw
  NetworkPolicy:
  Tylko Gateway może
  łączyć się z vLLM
end note

@enduml
```

### 6.2. NetworkPolicy

Ruch do serwisów vLLM jest ograniczony tylko do Gateway'a:

```plantuml
@startuml
!theme plain

rectangle "llm-shared" #LightBlue {
  node "Gateway\napp=llm-gateway" as gw
  node "Streamlit" as st
}

rectangle "llm-workspace-alpha" #LightGreen {
  node "vLLM\napp=llama-infer" as vllm
}

gw -[#green,bold]-> vllm : ALLOW\n(TCP 8000)
st -[#red,dashed]-> vllm : DENY

note bottom of vllm
  NetworkPolicy:
  ingress tylko z
  namespace: llm-shared
  pod: app=llm-gateway
end note

@enduml
```

---

## 7. Model danych MLFlow

### 7.1. Struktura rejestrów

```plantuml
@startuml
!theme plain

package "MLFlow Common (llm-shared)" {
  rectangle "Registered Models" {
    [llama-3-8b-base] as m1
    [llama-3-70b-base] as m2
    [mistral-7b-base] as m3
    [qwen2-7b-base] as m4
  }
  note right: Modele bazowe\n(tylko do odczytu)
}

package "MLFlow Workspace: team-alpha" {
  rectangle "Experiments" {
    [exp-corp-qa-001] as e1
    [exp-code-assist-002] as e2
  }
  rectangle "Registered Models" {
    [ft-llama3-8b-corp-v1] as fm1
    [ft-llama3-8b-corp-v2] as fm2
  }
  e1 --> fm1 : version 1
  e1 --> fm2 : version 2
}

m1 ..> e1 : base model

@enduml
```

### 7.2. Cykl życia modelu

```plantuml
@startuml
!theme plain

[*] --> Staging : Register

state "Staging" as staging {
  staging : Nowy model
  staging : Testowanie
}

state "Production" as prod {
  prod : Aktywny w vLLM
  prod : Dostępny przez Gateway
}

state "Archived" as arch {
  arch : Nieaktywny
  arch : Zachowane artefakty
}

staging --> prod : Promote\n(po testach)
prod --> arch : Deprecate\n(nowa wersja)
staging --> arch : Reject

@enduml
```

---

## 8. Macierz odpowiedzialności (RACI)

| Działanie | Data Scientist | MLOps | Platform Team |
|-----------|:-------------:|:-----:|:-------------:|
| Konfiguracja treningu | **R** | C | I |
| Uruchomienie treningu | **R** | I | I |
| Monitoring treningu | **R** | C | I |
| Promocja modelu do prod | A | **R** | C |
| Konfiguracja Gateway | I | **R** | C |
| Zarządzanie workspace'ami | I | **R** | A |
| Infrastruktura K8s | I | C | **R** |

**R** = Responsible, **A** = Accountable, **C** = Consulted, **I** = Informed

---

## 9. Wymagania techniczne

### 9.1. Wymagania GPU

| Typ treningu | Min. GPU | Zalecane GPU | VRAM |
|--------------|----------|--------------|------|
| LoRA 7B | 1x A100 | 1x A100 | 40GB |
| LoRA 13B | 1x A100 | 2x A100 | 80GB |
| Full fine-tune 7B | 4x A100 | 8x A100 | 320GB |
| Inference 7B | 1x A100 | 1x A100 | 16GB |

### 9.2. Storage

| Zasób | Rozmiar | Typ |
|-------|---------|-----|
| Model bazowy 7B | ~14GB | SSD (premium-rwo) |
| Model bazowy 70B | ~140GB | SSD (premium-rwo) |
| Checkpointy (per training) | ~20-50GB | SSD |
| MLFlow artifacts | ~100GB/workspace | Standard |

### 9.3. Wersje oprogramowania

| Komponent | Wersja |
|-----------|--------|
| LLaMA-Factory | 0.9.3 |
| vLLM | 0.4.0 |
| MLFlow | 2.10.0 |
| PyTorch | 2.2.0 |
| CUDA | 11.8 |
| Transformers | 4.37.0 |

---

## 10. Słownik pojęć

| Termin | Definicja |
|--------|-----------|
| **Workspace** | Izolowane środowisko (namespace) dla zespołu/projektu |
| **Gateway** | Centralny punkt dostępu do modeli z autoryzacją i logowaniem |
| **Fine-tuning** | Dostosowanie modelu bazowego do specyficznego zadania |
| **LoRA** | Low-Rank Adaptation - efektywna metoda fine-tuningu |
| **Experiment tracking** | Śledzenie metryk, parametrów i artefaktów treningu |
| **Model Registry** | Rejestr wersjonowanych modeli w MLFlow |
| **Guardrails** | Mechanizmy filtrowania niebezpiecznych treści |
| **Workload Identity** | Mechanizm GCP mapujący konta K8s na konta GCP |
