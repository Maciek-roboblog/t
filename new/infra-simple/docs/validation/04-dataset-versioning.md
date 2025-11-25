# Wersjonowanie Datasetów

## Spis treści

1. [Dlaczego wersjonowanie?](#dlaczego-wersjonowanie)
2. [Strategie wersjonowania](#strategie-wersjonowania)
3. [Implementacja w projekcie](#implementacja-w-projekcie)
4. [Hash i metadata](#hash-i-metadata)
5. [Integracja z MLflow](#integracja-z-mlflow)
6. [Best practices](#best-practices)

---

## Dlaczego wersjonowanie?

### Problemy bez wersjonowania

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                  PROBLEMY BEZ WERSJONOWANIA DANYCH                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Scenariusz 1: Data drift                                                   │
│   ┌─────────────────────────────────────────────────────────────────┐       │
│   │  Styczeń: train_data.json (10,000 samples)                      │       │
│   │  Luty: train_data.json (12,000 samples) ← nadpisany!           │       │
│   │                                                                  │       │
│   │  Problem: Nie można odtworzyć modelu ze stycznia                │       │
│   └─────────────────────────────────────────────────────────────────┘       │
│                                                                              │
│   Scenariusz 2: Debugging                                                    │
│   ┌─────────────────────────────────────────────────────────────────┐       │
│   │  Model A: accuracy 95% (dane z wersji X)                        │       │
│   │  Model B: accuracy 82% (dane z wersji Y)                        │       │
│   │                                                                  │       │
│   │  Problem: Nie wiadomo co się zmieniło w danych                  │       │
│   └─────────────────────────────────────────────────────────────────┘       │
│                                                                              │
│   Scenariusz 3: Compliance                                                   │
│   ┌─────────────────────────────────────────────────────────────────┐       │
│   │  Audytor: "Na jakich danych trenowaliście model w produkcji?"   │       │
│   │  Zespół: "Ehm... te dane zostały zaktualizowane..."             │       │
│   └─────────────────────────────────────────────────────────────────┘       │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Korzyści wersjonowania

| Korzyść | Opis |
|---------|------|
| **Reprodukowalność** | Zawsze możesz odtworzyć trening z tymi samymi danymi |
| **Debugowanie** | Łatwe porównanie danych między eksperymentami |
| **Rollback** | Powrót do poprzedniej wersji danych |
| **Audit trail** | Pełna historia zmian dla compliance |
| **Kolaboracja** | Zespół pracuje na tej samej wersji danych |

---

## Strategie wersjonowania

### 1. Semantic versioning (rekomendowane)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    SEMANTIC VERSIONING DANYCH                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Format: MAJOR.MINOR.PATCH                                                  │
│                                                                              │
│   MAJOR (1.0.0 → 2.0.0)                                                     │
│   └── Zmiana struktury/schematu                                             │
│   └── Usunięcie/zmiana pól                                                  │
│   └── Niekompatybilne z poprzednią wersją                                   │
│                                                                              │
│   MINOR (1.0.0 → 1.1.0)                                                     │
│   └── Nowe dane dodane                                                      │
│   └── Rozszerzenie datasetu                                                 │
│   └── Backward compatible                                                    │
│                                                                              │
│   PATCH (1.0.0 → 1.0.1)                                                     │
│   └── Korekty błędów                                                        │
│   └── Poprawki literówek                                                    │
│   └── Czyszczenie danych                                                    │
│                                                                              │
│   Przykład:                                                                  │
│   company_qa_v1.0.0.json  → Inicjalny dataset                               │
│   company_qa_v1.1.0.json  → +2000 nowych Q&A                                │
│   company_qa_v1.1.1.json  → Poprawione błędy w odpowiedziach               │
│   company_qa_v2.0.0.json  → Zmieniony format (dodano "context" field)      │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2. Hash-based versioning

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      HASH-BASED VERSIONING                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Nazwa pliku: train_data.json                                              │
│   Hash: sha256:a1b2c3d4e5f6g7h8...                                          │
│                                                                              │
│   Zalety:                                                                    │
│   ✓ Automatyczne wykrywanie zmian                                           │
│   ✓ Niemożliwe konflikty nazw                                               │
│   ✓ Content-addressable (jak Git)                                           │
│                                                                              │
│   Wady:                                                                      │
│   ✗ Hash nie mówi nic o zawartości                                          │
│   ✗ Trudne do zapamiętania                                                  │
│                                                                              │
│   Rekomendacja: Używaj hash jako dodatkowy identyfikator,                   │
│   nie jako główne wersjonowanie                                              │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 3. Date-based versioning

```
train_data_20250120.json
train_data_20250125.json
train_data_20250201.json

# Zalety: Łatwe sortowanie chronologiczne
# Wady: Nie mówi o naturze zmian
```

---

## Implementacja w projekcie

### Struktura katalogów

```
/storage/
├── data/
│   ├── current/                     # Symlink do aktualnej wersji
│   │   ├── train.json → ../versions/v2.1.0/train.json
│   │   └── test.json → ../versions/v2.1.0/test.json
│   │
│   ├── versions/                    # Wszystkie wersje
│   │   ├── v1.0.0/
│   │   │   ├── train.json
│   │   │   ├── test.json
│   │   │   └── manifest.json
│   │   │
│   │   ├── v2.0.0/
│   │   │   ├── train.json
│   │   │   ├── test.json
│   │   │   └── manifest.json
│   │   │
│   │   └── v2.1.0/                  # Aktualna
│   │       ├── train.json
│   │       ├── test.json
│   │       └── manifest.json
│   │
│   └── dataset_info.json            # LLaMA-Factory dataset registry
```

### Manifest datasetu

```json
{
  "version": "2.1.0",
  "created_at": "2025-01-25T10:30:00Z",
  "created_by": "data-team",

  "files": {
    "train.json": {
      "samples": 9000,
      "hash_sha256": "a1b2c3d4e5f6789...",
      "size_bytes": 15728640
    },
    "test.json": {
      "samples": 1000,
      "hash_sha256": "9876543210fedcba...",
      "size_bytes": 1747626
    }
  },

  "schema": {
    "format": "alpaca",
    "fields": ["instruction", "input", "output"],
    "added_fields": ["context"],
    "removed_fields": []
  },

  "changes": {
    "from_version": "2.0.0",
    "description": "Added 1000 new Q&A pairs for product support",
    "breaking": false
  },

  "statistics": {
    "avg_instruction_length": 45,
    "avg_output_length": 120,
    "unique_instructions": 8950,
    "language": "en"
  },

  "lineage": {
    "source": "internal_db_export",
    "preprocessing_script": "scripts/prepare_data_v2.py",
    "preprocessing_commit": "abc123def"
  }
}
```

### Skrypt wersjonowania

```bash
#!/bin/bash
# scripts/version_dataset.sh
# Użycie: ./version_dataset.sh v2.1.0 "Added product support Q&A"

set -e

VERSION=$1
DESCRIPTION=$2
DATA_DIR="/storage/data"
VERSIONS_DIR="${DATA_DIR}/versions"
CURRENT_DIR="${DATA_DIR}/current"

if [ -z "$VERSION" ] || [ -z "$DESCRIPTION" ]; then
    echo "Usage: $0 <version> <description>"
    exit 1
fi

# Utwórz katalog wersji
VERSION_DIR="${VERSIONS_DIR}/${VERSION}"
mkdir -p "$VERSION_DIR"

# Skopiuj dane z current
cp "${CURRENT_DIR}/train.json" "${VERSION_DIR}/"
cp "${CURRENT_DIR}/test.json" "${VERSION_DIR}/"

# Oblicz hashe
TRAIN_HASH=$(sha256sum "${VERSION_DIR}/train.json" | cut -d' ' -f1)
TEST_HASH=$(sha256sum "${VERSION_DIR}/test.json" | cut -d' ' -f1)
TRAIN_SIZE=$(wc -c < "${VERSION_DIR}/train.json")
TEST_SIZE=$(wc -c < "${VERSION_DIR}/test.json")
TRAIN_SAMPLES=$(jq length "${VERSION_DIR}/train.json")
TEST_SAMPLES=$(jq length "${VERSION_DIR}/test.json")

# Utwórz manifest
cat > "${VERSION_DIR}/manifest.json" << EOF
{
  "version": "${VERSION}",
  "created_at": "$(date -Iseconds)",
  "created_by": "${USER}",
  "files": {
    "train.json": {
      "samples": ${TRAIN_SAMPLES},
      "hash_sha256": "${TRAIN_HASH}",
      "size_bytes": ${TRAIN_SIZE}
    },
    "test.json": {
      "samples": ${TEST_SAMPLES},
      "hash_sha256": "${TEST_HASH}",
      "size_bytes": ${TEST_SIZE}
    }
  },
  "changes": {
    "description": "${DESCRIPTION}"
  }
}
EOF

# Zaktualizuj symlinki
ln -sfn "../versions/${VERSION}/train.json" "${CURRENT_DIR}/train.json"
ln -sfn "../versions/${VERSION}/test.json" "${CURRENT_DIR}/test.json"

echo "Dataset version ${VERSION} created successfully"
echo "Train hash: ${TRAIN_HASH}"
echo "Test hash: ${TEST_HASH}"
```

---

## Hash i metadata

### Obliczanie hash

```python
# scripts/hash_dataset.py
import hashlib
import json
from pathlib import Path

def compute_dataset_hash(file_path: str) -> str:
    """Oblicz SHA256 hash datasetu."""
    sha256_hash = hashlib.sha256()

    with open(file_path, 'rb') as f:
        # Czytaj w chunkach dla dużych plików
        for chunk in iter(lambda: f.read(4096), b""):
            sha256_hash.update(chunk)

    return sha256_hash.hexdigest()


def compute_content_hash(file_path: str) -> str:
    """
    Oblicz hash zawartości (niezależny od formatowania JSON).
    Przydatne gdy JSON jest przeformatowany ale dane te same.
    """
    with open(file_path, 'r') as f:
        data = json.load(f)

    # Sortuj klucze dla determinizmu
    normalized = json.dumps(data, sort_keys=True, ensure_ascii=False)
    return hashlib.sha256(normalized.encode()).hexdigest()


def verify_dataset(file_path: str, expected_hash: str) -> bool:
    """Zweryfikuj integralność datasetu."""
    actual_hash = compute_dataset_hash(file_path)
    return actual_hash == expected_hash


if __name__ == "__main__":
    import sys
    file_path = sys.argv[1]
    print(f"File hash: {compute_dataset_hash(file_path)}")
    print(f"Content hash: {compute_content_hash(file_path)}")
```

### Weryfikacja przed treningiem

```yaml
# k8s/06-training-job.yaml (fragment)
args:
- |
  echo "=== Verifying dataset integrity ==="

  # Wczytaj oczekiwany hash z manifest
  EXPECTED_HASH=$(jq -r '.files["train.json"].hash_sha256' \
    ${DATASET_PATH}/versions/${DATASET_VERSION}/manifest.json)

  # Oblicz aktualny hash
  ACTUAL_HASH=$(sha256sum ${DATASET_PATH}/current/train.json | cut -d' ' -f1)

  # Porównaj
  if [ "$EXPECTED_HASH" != "$ACTUAL_HASH" ]; then
    echo "ERROR: Dataset hash mismatch!"
    echo "Expected: $EXPECTED_HASH"
    echo "Actual: $ACTUAL_HASH"
    exit 1
  fi

  echo "Dataset verified: $ACTUAL_HASH"

  # Kontynuuj trening...
```

---

## Integracja z MLflow

### Logowanie wersji datasetu

```python
# W skrypcie treningowym lub jako callback
import mlflow
import json
from pathlib import Path

def log_dataset_info(dataset_path: str, version: str):
    """Zaloguj informacje o datasecie do MLflow."""

    manifest_path = Path(dataset_path) / "versions" / version / "manifest.json"

    with open(manifest_path, 'r') as f:
        manifest = json.load(f)

    # Loguj jako parametry
    mlflow.log_params({
        "dataset_version": version,
        "dataset_train_samples": manifest["files"]["train.json"]["samples"],
        "dataset_test_samples": manifest["files"]["test.json"]["samples"],
        "dataset_train_hash": manifest["files"]["train.json"]["hash_sha256"][:16],
        "dataset_test_hash": manifest["files"]["test.json"]["hash_sha256"][:16],
    })

    # Loguj manifest jako artefakt
    mlflow.log_artifact(str(manifest_path), "dataset")

    # Tagi dla łatwego wyszukiwania
    mlflow.set_tags({
        "dataset.version": version,
        "dataset.format": manifest.get("schema", {}).get("format", "unknown"),
    })
```

### Wyszukiwanie runów po wersji datasetu

```python
import mlflow

# Znajdź wszystkie runy z daną wersją datasetu
runs = mlflow.search_runs(
    experiment_names=["llama-finetuning"],
    filter_string="params.dataset_version = '2.1.0'"
)

print(runs[["run_id", "metrics.eval_loss", "params.dataset_train_samples"]])
```

### Konfiguracja w ConfigMap

```yaml
# k8s/04-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: llm-config
  namespace: llm-training
data:
  # ... inne zmienne ...

  # DATASET VERSIONING
  DATASET_VERSION: "v2.1.0"
  DATASET_PATH: "/storage/data"

  # Opcjonalnie: oczekiwany hash dla weryfikacji
  EXPECTED_TRAIN_HASH: "a1b2c3d4e5f6789..."
```

---

## Best practices

### 1. Nigdy nie modyfikuj istniejących wersji

```
✗ NIE:
/storage/data/versions/v1.0.0/train.json  ← zmodyfikowany!

✓ TAK:
/storage/data/versions/v1.0.0/train.json  ← niezmieniony
/storage/data/versions/v1.0.1/train.json  ← nowa wersja z poprawkami
```

### 2. Zawsze oddzielaj test set

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    TEST SET BEST PRACTICES                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ✓ Test set wydzielony PRZED jakimkolwiek treningiem                       │
│   ✓ Ten sam test set dla WSZYSTKICH eksperymentów                           │
│   ✓ Test set NIGDY nie używany podczas treningu                             │
│   ✓ Test set NIGDY nie używany do tuning hiperparametrów                    │
│                                                                              │
│   Procedura:                                                                 │
│   1. Pobierz surowe dane                                                    │
│   2. Wydziel test set (np. 10%) z seedem                                    │
│   3. Test set zablokowany - nie zmieniaj!                                   │
│   4. Reszta to train + validation (val_size w LLaMA-Factory)               │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 3. Dokumentuj preprocessing

```python
# scripts/prepare_data_v2.py
"""
Dataset preprocessing script v2.0

Input: raw_export.json (z bazy danych)
Output: train.json, test.json (format Alpaca)

Kroki:
1. Filtrowanie pustych odpowiedzi
2. Deduplikacja instrukcji
3. Normalizacja whitespace
4. Split train/test (90/10, seed=42)
5. Walidacja formatu

Changelog v2.0:
- Dodano pole "context" dla RAG
- Zmieniono separator z \n na \n\n
"""

SEED = 42
TEST_RATIO = 0.1

# ... reszta kodu ...
```

### 4. Retention policy

```yaml
# Przykładowa polityka przechowywania
retention_policy:
  # Trzymaj wszystkie wersje używane w produkcji
  production_versions: forever

  # Trzymaj ostatnie N wersji development
  development_versions: 10

  # Automatyczne usuwanie starszych po X dni
  cleanup_after_days: 90

  # Wyjątki - zawsze trzymaj
  never_delete:
    - "v1.0.0"  # Baseline
    - "v2.0.0"  # Major release
```

### 5. Checklist wersjonowania

```
□ Wersja w formacie semantic (vX.Y.Z)
□ Hash SHA256 obliczony i zapisany
□ Manifest z metadanymi
□ Test set wydzielony i zablokowany
□ Preprocessing script w repozytorium
□ Changelog dla każdej wersji
□ Zintegrowane z MLflow logging
□ Backup na zewnętrzny storage
```

---

## Źródła

- [Data Versioning Best Practices](https://labelyourdata.com/articles/machine-learning/data-versioning)
- [DVC - Data Version Control](https://dvc.org/doc)
- [MLflow Dataset Tracking](https://mlflow.org/docs/latest/ml/tracking/)
- [LLM Fine-tuning Dataset Guide - Comet](https://www.comet.com/site/blog/llm-fine-tuning-dataset/)
- [Semantic Versioning](https://semver.org/)
