Dobra, to **dorzucam wszystko, czego „brakowało”** – bez zewnętrznych include, tak żeby Ci to działało w każdym PlantUML / mermaid offline.

Poniżej masz:

1. C4 **Level 3** – komponenty w *training namespace*.
2. C4 **Level 3** – komponenty w *inference namespace*.
3. **Sequence diagram** – cały lifecycle: od YAML-a do requestu na API.
4. **Minimalny Helm chart** dla `llama-factory-api` (inference + HPA).
5. Sugestia **Model Registry / Model Card** pod AI Act (pola, które warto mieć).

---

## 1. C4 L3 – Training namespace (PlantUML, offline)

```plantuml
@startuml
title C4 L3 – Training namespace (fine-tuning)

actor "Data Scientist" as DS

node "GKE Cluster" {
  frame "Namespace: team-x (training)" {
    package "Argo Workflows" as Argo {
      component "Argo Server\n(UI + API)" as ArgoSrv
      component "Argo Controller\n(Workflow CRD)" as ArgoCtrl
      component "Argo Executor\n(w Podach)" as ArgoExec
    }

    package "LLaMA-Factory Pod" as TrainPod {
      component "Trainer\n(llamafactory-cli train)" as Trainer
      component "Data Loader\n(wejście: GCS/Artifactory)" as DataLoader
      component "Model Loader\n(HF / lokalny cache)" as ModelLoader
      component "Metrics Logger\n(W&B / MLflow / TB)" as Metrics
    }
  }

  database "Config repo (Git)\nYAML eksperymentów" as Git
  database "Artifact Store\n(checkpointy, modele)" as Store
  database "Model Card Repo\n(MD/JSON)" as MCRepo
  database "Model Registry\n(metadane)" as Registry
}

DS --> ArgoSrv : uruchamia\nworkflow z configem
ArgoSrv --> ArgoCtrl : zapis Workflow\n(CRD)
ArgoCtrl --> ArgoExec : tworzy Pod\nz LLaMA-Factory
ArgoExec --> TrainPod : start kontenera

TrainPod --> Git : (read-only)\nconfig.yaml
Trainer --> DataLoader : wczytaj dane
Trainer --> ModelLoader : wczytaj model bazowy
Trainer --> Store : zapis checkpointów\n+ final model
Trainer --> Metrics : log metryk

Trainer --> MCRepo : wygeneruj\nmodel card
Trainer --> Registry : zarejestruj\nmodel + metadane

@enduml
```

---

## 2. C4 L3 – Inference namespace (PlantUML, offline)

```plantuml
@startuml
title C4 L3 – Inference namespace (model jako API)

actor "Klient API" as Client

node "GKE Cluster" {
  frame "Namespace: team-x-api" {
    package "Warstwa sieci" as Net {
      component "Ingress / API Gateway\n(autoryzacja, routing)" as GW
      component "Service (K8s)\nLLM API" as K8sSvc
    }

    package "Deployment: llama-factory-api" as Dep {
      component "Pod: LLaMA-Factory API\n(llamafactory-cli api)" as APIPod
      component "Request Handler\n(REST/OpenAI style)" as Handler
      component "Inference Engine\n(vLLM / HF pipeline)" as Engine
    }
  }

  database "Artifact Store\n(GCS/Artifactory – model)" as Store
  database "Model Registry\n(id wersji, ścieżka)" as Registry
  collections "Monitoring\n(Prometheus/Grafana)" as Mon
  collections "Logging / Audyt\n(Loki / GCP Logging)" as Log
}

Client --> GW : HTTP(s) request\n(prompt, parametry)
GW --> K8sSvc : przekazanie\npo service name
K8sSvc --> APIPod : load balancing
APIPod --> Registry : sprawdź\naktualny id modelu
APIPod --> Store : wczytaj wagi\n(przy starcie / reload)

APIPod --> Handler : obsługa żądania
Handler --> Engine : generate()
Engine --> Handler : odpowiedź modelu
Handler --> GW : wynik JSON
GW --> Client : odpowiedź

GW --> Mon : metryki API
APIPod --> Mon : metryki modelu
GW --> Log : log requestu
APIPod --> Log : log prompt/odpowiedzi\n(pseudonimizowane)

@enduml
```

---

## 3. Sequence diagram – pełen lifecycle (PlantUML)

Od YAML-a → trening → rejestr modelu → deployment → request klienta.

```plantuml
@startuml
title Lifecycle: od configu do użycia modelu

actor DS as "Data Scientist"
actor APP as "Klient API"

participant Git as "Git repo\n(config YAML)"
participant Argo as "Argo UI"
participant ArgoCtrl as "Argo Controller"
participant Train as "Train Pod\n(LLaMA-Factory)"
participant Store as "Artifact Store"
participant Registry as "Model Registry"
participant ArgoCD as "Argo CD"
participant K8s as "K8s API\n(Deployment modelu)"
participant GW as "API Gateway"
participant APIPod as "llama-factory-api Pod"

== Przygotowanie konfiguracji ==
DS -> Git : commit config.yaml\n(i ewentualnie workflow.yaml)

== Uruchomienie treningu ==
DS -> Argo : start workflow\n(z referencją do config.yaml)
Argo -> ArgoCtrl : utwórz Workflow CRD
ArgoCtrl -> Train : utwórz Pod\nz LLaMA-Factory

Train -> Git : pobierz config.yaml
Train -> Store : pobierz dane / model bazowy\n(jeśli trzymasz w Store)
Train -> Train : trening (SFT/LoRA/QLoRA)

Train -> Store : zapis checkpointów\n+ final model
Train -> Registry : rejestruj model\n(id, ścieżka, metadata)
Train -> Store : zapis model card\n(plik MD/JSON)

== Deployment modelu ==
DS -> ArgoCD : commit manifestu\nDeployment + Service\nz id modelu
ArgoCD -> K8s : apply Deployment/Service
K8s -> APIPod : stworzenie podu
APIPod -> Store : load model\nz podanej ścieżki

== Użycie modelu ==
APP -> GW : POST /v1/chat/completions\nz tokenem
GW -> APIPod : przekazanie requestu
APIPod -> APIPod : inferencja\n(vLLM / HF)
APIPod -> GW : odpowiedź JSON
GW -> APP : zwróć wynik

@enduml
```

---

## 4. Minimalny Helm chart – `llama-factory-api`

To jest **szkielet**, który możesz wkleić do repo i dopieścić pod swoje potrzeby / wartości.

### 4.1. `Chart.yaml`

```yaml
apiVersion: v2
name: llama-factory-api
description: Minimalny chart do uruchomienia LLaMA-Factory jako API (inference)
type: application
version: 0.1.0
appVersion: "0.1.0"
```

### 4.2. `values.yaml` (przykład)

```yaml
image:
  repository: europe-docker.pkg.dev/YOUR-PROJECT/llm/llama-factory
  tag: "api-0.1.0"
  pullPolicy: IfNotPresent

replicaCount: 1

resources:
  limits:
    cpu: "4"
    memory: "16Gi"
    nvidia.com/gpu: 1
  requests:
    cpu: "2"
    memory: "8Gi"
    nvidia.com/gpu: 1

service:
  type: ClusterIP
  port: 8000

model:
  id: "team-x/llm-qa-v1"
  artifactPath: "gs://my-bucket/models/team-x/llm-qa-v1"
  # lub: "s3://..." / "artifactory://..."

env:
  # endpoint Artifactory / HF proxy
  HF_ENDPOINT: ""
  HF_TOKEN_SECRET_NAME: "hf-token"
  HF_TOKEN_SECRET_KEY: "token"

ingress:
  enabled: false
  className: ""
  hosts:
    - host: llama-api.example.com
      paths:
        - path: /
          pathType: Prefix
  tls: []
```

### 4.3. `templates/deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "llama-factory-api.fullname" . }}
  labels:
    app.kubernetes.io/name: {{ include "llama-factory-api.name" . }}
    app.kubernetes.io/instance: {{ .Release.Name }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app.kubernetes.io/name: {{ include "llama-factory-api.name" . }}
      app.kubernetes.io/instance: {{ .Release.Name }}
  template:
    metadata:
      labels:
        app.kubernetes.io/name: {{ include "llama-factory-api.name" . }}
        app.kubernetes.io/instance: {{ .Release.Name }}
    spec:
      containers:
        - name: api
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          args:
            - "llamafactory-cli"
            - "api"
            - "--model-id={{ .Values.model.id }}"
            - "--model-path={{ .Values.model.artifactPath }}"
            - "--host=0.0.0.0"
            - "--port={{ .Values.service.port }}"
          env:
            - name: HF_ENDPOINT
              value: "{{ .Values.env.HF_ENDPOINT }}"
            - name: HF_TOKEN
              valueFrom:
                secretKeyRef:
                  name: {{ .Values.env.HF_TOKEN_SECRET_NAME }}
                  key: {{ .Values.env.HF_TOKEN_SECRET_KEY }}
          ports:
            - containerPort: {{ .Values.service.port }}
          resources:
{{ toYaml .Values.resources | indent 12 }}
```

### 4.4. `templates/service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ include "llama-factory-api.fullname" . }}
spec:
  type: {{ .Values.service.type }}
  selector:
    app.kubernetes.io/name: {{ include "llama-factory-api.name" . }}
    app.kubernetes.io/instance: {{ .Release.Name }}
  ports:
    - name: http
      port: {{ .Values.service.port }}
      targetPort: {{ .Values.service.port }}
```

### 4.5. `templates/hpa.yaml` – auto-scaling inference

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ include "llama-factory-api.fullname" . }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ include "llama-factory-api.fullname" . }}
  minReplicas: 1
  maxReplicas: 5
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

> GPU HPA jest trudniejszy (brak standardowych metryk), ale możesz dodać metryki custom przez Prometheus + Prometheus Adapter.

---

## 5. Model Registry & Model Card – pola, które warto mieć (AI Act)

### 5.1. Model Registry – przykładowy „schemat”

Myśl o tym jak o tabeli SQL / dokumencie NoSQL:

* `model_id` – globalny identyfikator (np. `team-x.llm-qa.v1`)
* `version` – semver / hash (`1.0.0`, `git_sha`)
* `base_model` – np. `meta-llama/Llama-3-8B`
* `tenant` – nazwa zespołu / klienta
* `risk_class` – `HIGH_RISK` / `GENERAL_PURPOSE` / inne
* `status` – `TRAINED`, `VALIDATED`, `DEPLOYED`, `DEPRECATED`
* `artifact_path` – ścieżka w GCS/Artifactory do wag
* `config_path` – ścieżka do config.yaml w Git
* `data_id` – identyfikator zbioru danych (link do repo datasetu)
* `metrics` – np. JSON z kluczowymi metrykami (accuracy, BLEU, itd.)
* `owner` – osoba/rola odpowiedzialna
* `created_at`, `updated_at`
* `ai_act_notes` – specjalne pole (np. odnośnik do decyzji oceny ryzyka, procedury zgodności)

### 5.2. Model Card – sekcje (zgodnie z AI Act)

W praktyce możesz zrobić szablon Markdown:

1. **Identyfikacja modelu**

   * nazwa, wersja, model_id, właściciel.
2. **Cel i zastosowanie**

   * do czego model jest przeznaczony, do czego **nie** jest.
3. **Klasa ryzyka (AI Act)**

   * np. high-risk, general-purpose; link do analizy ryzyka.
4. **Dane treningowe**

   * źródła, typy danych, preprocessing, potencjalne biasy.
5. **Metody treningu**

   * baza (np. LLaMA-3), technika (SFT, LoRA, QLoRA), hiperparametry (skrót).
6. **Wyniki i metryki**

   * metryki na zbiorach walidacyjnych/testowych, porównanie z baseline.
7. **Ograniczenia**

   * znane problemy, scenariusze, gdzie wynik może być fałszywy/niebezpieczny.
8. **Kontrola i nadzór**

   * jak monitorowany jest model, jakie są procedury wycofania/rollback.
9. **Logowanie / audyt**

   * jakie logi są zbierane, na jak długo, kto ma dostęp.
10. **Kontakt / odpowiedzialność**

    * do kogo zgłaszać incydenty.

---

Jeśli chcesz, następnym krokiem mogę:

* przerobić któryś z tych diagramów/Helmów **pod konkretny Twój naming / namespace / registry**,
* albo dorzucić **mermaid sequence diagram** (jeśli wolisz mieć pełny komplet w jednym stylu).
