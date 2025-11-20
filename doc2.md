Jasne – to zróbmy teraz **jedną, spójną, high-level architekturę** pod:

* fine-tuning w LLaMA-Factory,
* serving na **vLLM**,
* multi-tenant na K8s,
* z punktami zaczepienia pod AI Act.

Postaram się żeby to było możliwie „C4-owe”, ale lekkie i wdrożalne.

---

## 1. Warstwy – jak to w ogóle wygląda

Myśl o tym jak o 4 warstwach:

1. **Warstwa użytkowników**

   * Data Scientists / ML Eng (konfigurują trening, śledzą metryki).
   * App Devs / Klienci (wołają API modelu).
   * Compliance / Risk (czyta registry, model cards, logi).

2. **Control plane (GitOps / MLOps)**

   * Git (kody + YAML LLaMA-Factory, Argo Workflows, Helm values dla vLLM).
   * Argo CD (wdrażanie infrastruktury: ArgoWF, vLLM, monitoring).
   * Model Registry + Model Card Repo (metadane modeli + dokumentacja).
   * Secrets (Artifactory/HF tokens, dane dostępowe do GCS).

3. **Training plane (fine-tuning)**

   * Argo Workflows + LLaMA-Factory pods (Jobs) na klastrze K8s.
   * Node pool GPU „training”.
   * Storage na dane i artefakty (GCS / NFS / Artifactory).

4. **Inference plane (serving)**

   * vLLM jako silnik inferencji (OpenAI-compatible API).
   * API Gateway / Ingress (auth, routing, multi-tenant).
   * Node pool GPU „inference”.
   * Monitoring + Logging (Prometheus / Grafana / Loki).

Most między training a inference to: **Artifact Store + Model Registry**.

---

## 2. High-level diagram C4 (Mermaid) – całość z vLLM

Ten diagram możesz wkleić 1:1 do dowolnego narzędzia Mermaid:

```mermaid
flowchart LR
    %% Użytkownicy
    DS[Data Scientist]:::actor
    APP[App / Klient API]:::actor
    RISK[Compliance / Risk]:::actor

    %% Control plane
    subgraph CTRL[Control Plane]
      Git[(Git repo\n(kod, YAML, Helm))]
      ArgoCD[Argo CD\n(GitOps)]
      ModelReg[(Model Registry\n+ Model Cards)]:::ai
    end

    %% Training plane
    subgraph TRAIN[Training Cluster / Namespace]
      ArgoWF[Argo Workflows\n(orchestration)]
      LFTPods[LLaMA-Factory\ntraining pods]
    end

    %% Inference plane
    subgraph INF[Inference Cluster / Namespace]
      APIGW[API Gateway / Ingress\n(auth + routing)]
      subgraph VLLM[vLLM deployment(s)]
        VLLMsvc[vLLM Pods\n(OpenAI-style API)]
      end
    end

    %% Shared storage / obserw.
    Artifact[(Artifact Store\nGCS / Artifactory)]:::ai
    Mon[(Monitoring\nPrometheus + Grafana)]:::ai
    Log[(Logging / Audyt\nLoki / Cloud Logging)]:::ai

    classDef actor fill=#fff,stroke=#333,stroke-width=1;
    classDef ai fill=#fff2e5,stroke=#ff8040,stroke-width=2;

    %% Połączenia – training
    DS --> Git
    DS --> ArgoWF
    ArgoCD --> TRAIN
    ArgoWF --> LFTPods
    LFTPods --> Artifact
    LFTPods --> ModelReg

    %% Połączenia – inference
    ArgoCD --> INF
    ModelReg --> ArgoCD
    ArgoCD --> VLLMsvc
    VLLMsvc --> Artifact

    APP --> APIGW
    APIGW --> VLLMsvc

    %% Observability / AI Act
    VLLMsvc --> Mon
    APIGW --> Mon
    VLLMsvc --> Log
    APIGW --> Log
    ModelReg <-- RISK
    Log <-- RISK
```

**Czytanie tego diagramu:**

* **Training**

  * DS commit’uje config LLaMA-Factory (YAML) do Git.
  * Argo Workflows uruchamia joby treningowe (LFTPods) na GPU.
  * LLaMA-Factory tworzy artefakty (HF-compatible folder z wagami) i zapisuje do Artifact Store.
  * Pipeline rejestruje model (ModelReg) + model card.

* **Inference**

  * ArgoCD czyta z ModelReg (który model/wersja ma być live), wstrzykuje to do Helm values dla vLLM.
  * ArgoCD deployuje **vLLM** jako Deployment/StatefulSet w inference namespace/klastrze, z wolumenem / ścieżką do Artefact Store.
  * vLLM ładuje wagi HF z referencji (Artifact path).
  * Klienci uderzają w API Gateway, który rozsyła requesty do vLLM (OpenAI-style `/v1/chat/completions` itd.).
  * Metryki + logi idą do Mon / Log, compliance ma pełny wgląd.

---

## 3. Jak dokładnie wpiąć vLLM w ten flow

### 3.1. Po stronie LLaMA-Factory (training)

**Cel:** po treningu mieć **folder kompatybilny z HF** (config.json, tokenizer, safetensors) – dokładnie to, co vLLM umie załadować.

Standardowy pattern:

1. LLaMA-Factory trenuje model (pełny SFT albo LoRA/QLoRA).
2. Po treningu:

   * jeśli LoRA → `llamafactory-cli export`/merge do pełnego modelu,
   * wynik zapisujesz jako HF folder: `gs://bucket/models/<tenant>/<model-id>/<version>/`.
3. Pipeline (Argo Workflow) po zakończeniu:

   * wrzuca wpis do **Model Registry** z:

     * `model_id`, `version`
     * `artifact_path` (ścieżka HF modelu)
     * `risk_class`, `owner`, `metrics`, link do model card.

### 3.2. vLLM jako silnik inference

Dwa warianty:

1. **Native vLLM deployment**

   * Używasz oficjalnego obrazu vLLM (`vllm/vllm-openai`) z parametrami np.:

     ```bash
     python -m vllm.entrypoints.openai.api_server \
       --model /models/<tenant>/<model-id>/<version> \
       --host 0.0.0.0 --port 8000
     ```
   * W K8s: Deployment z wolumenem (CSI GCS / PVC), który montuje folder HF z Artefact Store.
   * API Gateway widzi czyste OpenAI API.

2. **LLaMA-Factory z backendem vLLM**

   * LLaMA-Factory ma tryb `api` z backendem `vllm` – można odpalić:

     ```bash
     llamafactory-cli api \
       --model_name_or_path /models/<...> \
       --infer_backend vllm \
       --host 0.0.0.0 --port 8000
     ```
   * Wtedy w jednym kontenerze masz:

     * warstwę „routera” LLaMA-Factory (np. własne endpointy, prompt templates),
     * backend vLLM jako engine.
   * To wygodne, jeśli chcesz mieć **spójny sposób logiki promptów** i ew. tych samych rozszerzeń co w treningu.

**Ja bym zalecał:**

* do **czystego API dla aplikacji** → **native vLLM** (prościej, wydajniej),
* jeśli chcesz dodatkowe „eksperymentalne” endpointy → oddzielny `llamafactory-api` dla zespołu ML, nadal korzystający z vLLM pod spodem.

---

## 4. Multi-tenant + vLLM

### 4.1. Logical tenancy (wspólny klaster)

* `namespace: team-a-training` / `namespace: team-a-inference`
* w inference:

  * każdy tenant ma osobny **Deployment vLLM** + **Service**,
  * API Gateway routuje po ścieżce / host’cie:

    * `team-a.llm.yourdomain.com` → ns `team-a-inference`,
    * `team-b.llm.yourdomain.com` → `team-b-inference`.
* ResourceQuota per namespace ogranicza GPU (np. `max 4 GPU`).
* Model Registry ma pole `tenant` i ArgoCD generuje manifesty tylko dla odpowiedniego namespace.

### 4.2. Hard tenancy (osobne klastry)

* dokładnie ta sama architektura, tylko:

  * osobny klaster `llm-team-a-training`, `llm-team-a-inference`,
  * ArgoCD w trybie multi-cluster (ApplicationSet).
* vLLM w każdym klastrze ma dostęp tylko do „swoich” bucketów / artefaktów.

---

## 5. AI Act – gdzie są „hot spots” w tej architekturze

Na high level:

1. **Model Registry + Model Cards**

   * definicja klasy ryzyka,
   * dokumentacja datasetów,
   * link do testów i wyników,
   * to jest Twój „rejestr systemów AI”.

2. **Artifact Store**

   * przechowuje wagi → musisz mieć:

     * politykę retencji (np. wersje historyczne modeli high-risk),
     * kontrolę kto ma prawo wgrać/odczytać.

3. **Logging / Audyt**

   * **API Gateway + vLLM**: logowanie requestów (przynajmniej: kto, jaki model, kiedy, metadata).
   * dla high-risk – dodatkowo logowanie decyzji / outputu (z pseudonimizacją danych wejściowych).
   * retencja ≥ 6 miesiące, opcjonalnie archiwum w osobnym storage.

4. **Monitoring**

   * metryki jakości / drift → część „post-market monitoring”.
   * alerty, jeśli model zachowuje się inaczej niż w karcie (np. wzrost odsetka błędów specyficznego typu).

5. **Access control**

   * RBAC w K8s, IAM do bucketów, API keys / OAuth w Gateway.
   * zasada: użytkownik widzi tylko modele, do których ma prawo (per tenant + per risk class).

---

## 6. Minimalne „jak to postawić” w krokach

1. **Infra & control plane**

   * Klaster(y) GKE z node poolami GPU (`training`, `inference`).
   * Helm dla:

     * Argo Workflows + ArgoCD,
     * Prometheus/Grafana, Loki,
     * ewentualnie GCS CSI.
   * Repo Git z:

     * chartem `vllm` lub `llama-factory-api`,
     * workflowami Argo dla fine-tune + export.

2. **Training**

   * Budujesz własny image `llama-factory` (PyTorch + CUDA).
   * Argo Workflow:

     * krok `train` → `llamafactory-cli train config.yaml`,
     * krok `export` → generuje HF folder → zapis do `gs://...`,
     * krok `register` → wpis do Model Registry + generacja model card.

3. **Serving (vLLM)**

   * Chart `vllm-api` (Deployment + Service + HPA) – w values:

     * `model.artifactPath`,
     * `resources` (GPU),
     * `tenant`.
   * ArgoCD tworzy `Release vllm-api` na podstawie wpisu w Model Registry (Automation: ApplicationSet generuje per model/tenant).

4. **Gateway**

   * Ingress / API Gateway z regułami:

     * `Host: tenantA.llm` → Service vLLM tenantA,
     * autoryzacja: JWT / API key.
   * Export metryk + logów do Prometheus/Loki.

---

Jeśli chcesz, mogę w kolejnym kroku:

* rozpisać **konkretny manifest Argo Workflow** “train → export → register → deploy vLLM”,
* albo zrobić **jedno, duże mermaid „architecture + sequence”** które możesz wrzucić do Confluence / Git README i mieć jako oficjalny obrazek architektury.
