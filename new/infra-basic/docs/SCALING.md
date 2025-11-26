# Skalowanie LLaMA-Factory + vLLM

## TL;DR

| Co chcesz | Jak skalować |
|-----------|--------------|
| Więcej userów | GPU time-slicing → więcej GPU |
| Większe modele | Tensor parallelism (vLLM) |
| Szybszy trening | Więcej GPU + distributed training |
| Production inference | vLLM replicas + load balancer |

## Poziomy Skalowania

### Poziom 0: Single GPU (ten setup)

```
1x GPU → time-slicing → 2 logical GPUs
         ├── LLaMA-Factory (training)
         └── vLLM (inference)
```

**Ograniczenia**:
- Trening i inference współdzielą pamięć GPU
- Małe modele (≤7B) z QLoRA
- 1-2 użytkowników

### Poziom 1: Multi-GPU, Single Node

```
4x GPU → dedykowane
         ├── GPU 0-1: Training
         └── GPU 2-3: vLLM (tensor parallel)
```

**Zmiany**:

```yaml
# 04-llama-webui.yaml
resources:
  limits:
    nvidia.com/gpu: "2"  # 2 GPU dla treningu

# 05-vllm.yaml
args:
- "--tensor-parallel-size"
- "2"  # 2 GPU dla inference
resources:
  limits:
    nvidia.com/gpu: "2"
```

### Poziom 2: Multi-Node Cluster

```
Node 1 (4x GPU): Training jobs
Node 2 (4x GPU): vLLM inference
Node 3 (4x GPU): vLLM inference (replica)
```

**Zmiany**:
- Zmień `hostPath` na NFS/GCS
- Dodaj node selectors/affinity
- vLLM replicas + LoadBalancer

## Skalowanie Treningu

### Distributed Training (DeepSpeed)

LLaMA-Factory wspiera DeepSpeed dla multi-GPU training.

```yaml
# training-distributed.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: training-distributed
spec:
  template:
    spec:
      containers:
      - name: trainer
        image: ghcr.io/hiyouga/llamafactory:latest
        command: ["llamafactory-cli"]
        args:
        - "train"
        - "--deepspeed"
        - "ds_config.json"
        - "--model_name_or_path"
        - "/storage/models/base-model"
        # ... inne parametry
        resources:
          limits:
            nvidia.com/gpu: "4"
```

### DeepSpeed Config

```json
{
  "train_batch_size": 16,
  "gradient_accumulation_steps": 4,
  "fp16": {"enabled": true},
  "zero_optimization": {
    "stage": 2,
    "offload_optimizer": {"device": "cpu"}
  }
}
```

## Skalowanie Inference (vLLM)

### Horizontal Scaling (replicas)

```yaml
# 05-vllm-scaled.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vllm
spec:
  replicas: 3  # 3 instancje vLLM
  template:
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchLabels:
                app: vllm
            topologyKey: kubernetes.io/hostname
      containers:
      - name: vllm
        resources:
          limits:
            nvidia.com/gpu: "1"
---
apiVersion: v1
kind: Service
metadata:
  name: vllm
spec:
  type: LoadBalancer  # lub ClusterIP + Ingress
```

### Vertical Scaling (tensor parallelism)

```yaml
# Dla większych modeli (70B+)
args:
- "--tensor-parallel-size"
- "4"  # Rozłóż model na 4 GPU
resources:
  limits:
    nvidia.com/gpu: "4"
```

### vLLM Production Stack

Dla dużej skali użyj oficjalnego [vLLM Production Stack](https://github.com/vllm-project/production-stack):

```bash
helm repo add vllm https://vllm-project.github.io/production-stack
helm install vllm vllm/vllm-stack \
  --set replicaCount=3 \
  --set model=/storage/models/merged-model
```

## Skalowanie Storage

### Od hostPath do NFS

```yaml
# 02-storage-nfs.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: llm-storage-nfs
spec:
  capacity:
    storage: 500Gi
  accessModes:
    - ReadWriteMany  # Multi-node access
  nfs:
    server: nfs-server.example.com
    path: /exports/llm-storage
```

### Do Cloud Storage (GCS/S3)

Dla multi-cluster:

```yaml
# Używaj huggingface_hub z cloud credentials
env:
- name: HF_HOME
  value: "gs://my-bucket/hf-cache"
- name: GOOGLE_APPLICATION_CREDENTIALS
  value: "/secrets/gcs-key.json"
```

## GPU Time-Slicing → Dedicated

Migracja z time-slicing do dedykowanych GPU:

### Krok 1: Usuń time-slicing config

```bash
kubectl delete configmap time-slicing-config -n gpu-operator
kubectl patch clusterpolicy/cluster-policy -n gpu-operator \
  --type merge -p '{"spec": {"devicePlugin": {"config": {"name": ""}}}}'
```

### Krok 2: Zaktualizuj manifesty

```yaml
# Każdy pod dostaje pełne GPU
resources:
  limits:
    nvidia.com/gpu: "1"  # = 1 pełne GPU
```

### Krok 3: Dodaj node affinity

```yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: nvidia.com/gpu.product
          operator: In
          values:
          - NVIDIA-A100-SXM4-80GB
```

## Metryki i Monitoring

### Prometheus + Grafana

```bash
helm install prometheus prometheus-community/kube-prometheus-stack
```

### GPU Metrics

```yaml
# ServiceMonitor dla GPU metrics
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: gpu-metrics
spec:
  selector:
    matchLabels:
      app: nvidia-dcgm-exporter
  endpoints:
  - port: metrics
```

## Rekomendacje

| Rozmiar modelu | Min GPU | Rekomendacja |
|----------------|---------|--------------|
| ≤3B | 8GB | 1x RTX 3060/4060 |
| 7B | 16GB | 1x RTX 4080/A4000 |
| 13B | 24GB | 1x RTX 4090/A5000 |
| 30B | 48GB | 2x A6000 lub 1x A100-40GB |
| 70B | 80GB+ | 4x A100-80GB (tensor parallel) |

## Źródła

- [vLLM Production Stack](https://github.com/vllm-project/production-stack)
- [DeepSpeed](https://www.deepspeed.ai/)
- [LLaMA-Factory Distributed Training](https://github.com/hiyouga/LLaMA-Factory#distributed-training)
- [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/)
