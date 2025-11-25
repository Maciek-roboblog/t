# LLM Platform - Infrastructure as Code

Kompletna konfiguracja infrastruktury dla platformy LLM fine-tuning i inference.

## Struktura katalogów

```
infra/
├── terraform/                    # Infrastruktura GCP
│   ├── modules/
│   │   ├── gke/                 # Klaster GKE + GPU nodes
│   │   ├── networking/          # VPC, subnety, NAT
│   │   ├── storage/             # Cloud SQL, GCS, Artifact Registry
│   │   └── iam/                 # Service Accounts, Workload Identity
│   └── environments/
│       ├── dev/                 # Środowisko developerskie
│       └── prod/                # Środowisko produkcyjne
├── k8s/                         # Manifesty Kubernetes (Kustomize)
│   ├── base/
│   │   ├── shared/              # Zasoby wspólne (Gateway, MLFlow Common)
│   │   └── workspace-template/  # Szablon workspace'u
│   └── overlays/
│       ├── team-alpha/          # Konfiguracja team-alpha
│       └── team-beta/           # Konfiguracja team-beta
├── scripts/                     # Skrypty automatyzacji
│   ├── create-workspace.sh
│   ├── deploy-workspace.sh
│   ├── verify-deployment.sh
│   ├── build-images.sh
│   └── port-forward.sh
└── README.md
```

## Wymagania

- `gcloud` CLI
- `terraform` >= 1.5.0
- `kubectl`
- `kustomize`
- `docker`

## Szybki start

### 1. Konfiguracja GCP

```bash
# Logowanie
gcloud auth login
gcloud auth application-default login

# Ustaw projekt
export PROJECT_ID="your-project-id"
gcloud config set project $PROJECT_ID

# Włącz wymagane API
gcloud services enable \
    container.googleapis.com \
    sqladmin.googleapis.com \
    artifactregistry.googleapis.com \
    servicenetworking.googleapis.com
```

### 2. Wdrożenie infrastruktury (Terraform)

```bash
cd terraform/environments/dev

# Skopiuj i uzupełnij zmienne
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars

# Utwórz bucket na state
gsutil mb -l europe-west4 gs://${PROJECT_ID}-tfstate-dev

# Init i apply
terraform init
terraform plan
terraform apply
```

### 3. Połączenie z klastrem

```bash
# Pobierz credentials
gcloud container clusters get-credentials llm-platform-dev \
    --region europe-west4 \
    --project $PROJECT_ID

# Weryfikacja
kubectl get nodes
```

### 4. Budowa obrazów Docker

```bash
cd scripts
./build-images.sh v1.0.0
```

### 5. Wdrożenie warstwy wspólnej

```bash
# Zaktualizuj wartości w kustomization.yaml
cd ../k8s/base/shared
# Zamień PROJECT_ID na właściwy

# Deploy
kubectl apply -k .
```

### 6. Utworzenie workspace'u

```bash
cd ../../../scripts

# Utwórz nowy workspace
./create-workspace.sh team-alpha

# Uzupełnij konfigurację w overlay
vim ../k8s/overlays/team-alpha/kustomization.yaml

# Wdróż
./deploy-workspace.sh team-alpha
```

### 7. Weryfikacja

```bash
./verify-deployment.sh team-alpha
```

## Użycie

### Dostęp do UI

```bash
# LLaMA-Factory WebUI (fine-tuning)
./port-forward.sh webui team-alpha
# -> http://localhost:7860

# Konsola Streamlit (testowanie)
./port-forward.sh streamlit
# -> http://localhost:8501

# MLFlow (experiment tracking)
./port-forward.sh mlflow team-alpha
# -> http://localhost:5000
```

### Zarządzanie workspace'ami

```bash
# Nowy workspace
./create-workspace.sh team-gamma

# Wdrożenie
./deploy-workspace.sh team-gamma

# Usunięcie
kubectl delete -k ../k8s/overlays/team-gamma
```

### Aktualizacja obrazów

```bash
# Nowa wersja
./build-images.sh v1.1.0

# Rolling update (zmień tag w overlay)
# vim ../k8s/overlays/team-alpha/kustomization.yaml
# images:
#   - name: llama-factory-train
#     newTag: v1.1.0

kubectl apply -k ../k8s/overlays/team-alpha
```

## Zmienne do uzupełnienia

W plikach konfiguracyjnych zamień następujące placeholder'y:

| Placeholder | Opis | Gdzie |
|-------------|------|-------|
| `PROJECT_ID` | ID projektu GCP | terraform/*.tf, k8s/*.yaml |
| `MLFLOW_DB_HOST` | IP Cloud SQL | k8s/overlays/*/kustomization.yaml |
| `*_PASSWORD` | Hasła do baz | terraform.tfvars, secrets |

## Troubleshooting

### GPU nodes nie startują

```bash
# Sprawdź quota
gcloud compute regions describe europe-west4 \
    --format="table(quotas.metric,quotas.limit,quotas.usage)"

# Sprawdź node pool
kubectl describe nodes -l node-type=gpu
```

### MLFlow nie łączy się z bazą

```bash
# Sprawdź Cloud SQL
gcloud sql instances describe llm-platform-mlflow-dev

# Test połączenia z poda
kubectl -n llm-shared exec -it deploy/mlflow-common -- \
    python -c "import psycopg2; print('OK')"
```

### Workload Identity nie działa

```bash
# Sprawdź annotację SA
kubectl -n llm-workspace-team-alpha get sa llm-workload-sa -o yaml

# Test z poda
kubectl -n llm-workspace-team-alpha run test --rm -it \
    --serviceaccount=llm-workload-sa \
    --image=google/cloud-sdk:slim \
    -- gcloud auth list
```

## Architektura

Zobacz dokumentację:
- `../architektura-new.md` - opis architektury, narzędzi, diagramy
- `../wdrozenie-new.md` - przewodnik wdrożeniowy krok po kroku
