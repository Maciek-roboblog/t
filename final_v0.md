Obrazy Docker i konfiguracja Kubernetes dla LLaMA-Factory
Aby przygotować pełną infrastrukturę dla LLaMA-Factory (obejmującą trening fine-tuning, serwer inferencyjny API z vLLM, eksport modeli oraz monitorowanie), tworzymy osobne obrazy Docker bazujące na wspólnym środowisku Debian 12 z Pythonem 3.11.2. Wersja Pythona 3.11.2 jest zgodna z wymaganiami bibliotek Hugging Face Transformers, vLLM i PyTorch – oficjalny obraz LLaMA-Factory również używa Pythona 3.11 i PyTorch 2.6.0. Poniżej przedstawiono kolejno definicje Dockerfile dla komponentów (trening, serwer inferencyjny, opcjonalny serwis UI) oraz konfiguracje Kubernetes (Job/Deployment, autoskalowanie GPU, ConfigMap/Secret na tokeny, storage). Na koniec omówiono mechanizm dynamicznego ładowania modeli z różnych źródeł i integrację z vLLM, a także zamieszczono diagram architektury (Mermaid).
Dockerfile dla treningu LLaMA-Factory (GPU)
Ten Dockerfile definiuje obraz do treningu modeli za pomocą LLaMA-Factory na GPU. Bazuje on na Debianie 12 i instaluje Pythona 3.11.2 oraz wszystkie zależności z apt/pip – bez użycia gotowych baz CUDA/PyTorch (instalujemy wymagane biblioteki ręcznie). Zawiera on m.in. PyTorch (z obsługą CUDA), bibliotekę Transformers i samą platformę LLaMA-Factory. Opcjonalnie można doinstalować komponenty takie jak bitsandbytes (8-bit quantization), DeepSpeed (rozproszone trenowanie) czy Flash-Attention dla optymalizacji – poniżej zaznaczono je jako opcjonalne. Python 3.11.2 zapewni kompatybilność z tymi bibliotekami (np. PyTorch 2.x wspiera Python 3.11). Używamy narzędzia pip do instalacji LLaMA-Factory (dostępnego na PyPI jako llamafactory) wraz z dodatkami: torch (by zainstalować PyTorch), metrics (metryki) oraz ewentualnie vllm jeśli chcemy mieć vLLM w obrazie treningowym – choć do samego trenowania nie jest on wymagany. Poniżej definicja Dockerfile:
# Podstawa: Debian 12 (Bookworm) + Python 3.11.2
FROM debian:12 AS base

ENV DEBIAN_FRONTEND=noninteractive
# Instalacja Pythona 3.11 (Debian 12 domyślnie zawiera Python 3.11.2) oraz pip i zależności budowania
RUN apt-get update && apt-get install -y \
    python3.11 python3.11-venv python3-pip \
    build-essential git curl wget \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Ustawienie aliasów, żeby 'python' i 'pip' wskazywały na Python 3.11
RUN ln -s /usr/bin/python3.11 /usr/bin/python && ln -s /usr/bin/pip3 /usr/bin/pip

# Instalacja zależności Pythona wymaganych do trenowania LLM
# (PyTorch z obsługą CUDA, Transformers, Datasets, itp.)
# Uwaga: pip automatycznie zainstaluje odpowiednie koła (wheels) PyTorch z CUDA,
# o ile środowisko ma zainstalowane sterowniki NVIDIA. Zapewniamy, że PyTorch ma CUDA (np. wersja cu118/cu121).
# PIP_INDEX i wersje można dostosować; tu instalujemy bieżące stabilne wersje.
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu118 && \
    pip install --no-cache-dir transformers==4.33.0 datasets==2.14.0

# Instalacja LLaMA-Factory z PyPI wraz z rozszerzeniami:
# - 'torch' aby doinstalować ewentualnie odpowiednią wersję torch (już zainstalowaliśmy, więc to pominie)
# - 'metrics' jeśli chcemy metryki HuggingFace
# - można dodać inne rozszerzenia jak 'deepspeed', 'bitsandbytes', 'vllm' zgodnie z potrzebą
RUN pip install --no-cache-dir llamafactory[torch,metrics]==0.9.3

# (Opcjonalnie) Instalacja dodatkowych pakietów:
# bitsandbytes (8-bit trening), deepspeed (opcjonalne przy multi-GPU), flash-attn (wymaga kompilacji)
#RUN pip install --no-cache-dir bitsandbytes==0.41.1 deepspeed==0.9.6
# FlashAttention wymaga nagłówków CUDA i kompilacji - instalacja tylko jeśli potrzebna:
#RUN apt-get update && apt-get install -y cuda-toolkit && \
#    pip install flash-attn==2.7.4 && \
#    apt-get remove -y cuda-toolkit && apt-get autoremove -y

# Ustawienie katalogu roboczego i ewentualne skopiowanie kodu/konfiguracji
WORKDIR /app
# (Opcjonalnie) Jeśli posiadamy własny kod LLaMA-Factory lub pliki konfiguracyjne, można je skopiować:
# COPY ./train_config.yaml /app/config/train_config.yaml

# Domyślny punkt wejścia: uruchamiamy powłokę – komenda treningowa zostanie podana przez K8s (Job)
ENTRYPOINT ["/bin/bash"]
Objaśnienia: Powyższy Dockerfile instaluje środowisko do trenowania modelu. Instalujemy PyTorch z obsługą GPU przez pip (używając oficjalnego indeksu PyTorch dla kół z CUDA 11.8; można dostosować do wersji CUDA dostępnej na hoście). Wgrywamy też bibliotekę Hugging Face Transformers oraz Datasets do wczytywania danych treningowych. Następnie instalujemy LLaMA-Factory z pip (wersja 0.9.3 z czerwca 2025) wraz z dodatkami. W razie potrzeby doinstalowujemy kolejne pakiety: np. bitsandbytes do 8-bitowego fine-tuningu, Deepspeed do przyspieszenia treningu dużych modeli lub FlashAttention (flash-attn) do wydajniejszego działania mechanizmu attention – instalacja flash-attn wymaga jednak dostarczenia narzędzi CUDA do kompilacji (można tymczasowo zainstalować CUDA toolkit, skompilować, a następnie usunąć, by obraz nie był zbyt duży). Wspólny obraz bazowy jest Debian 12 + Python 3.11, co spełnia wymagania (zgodność PyTorch z Python 3.11 została potwierdzona). Kontener domyślnie uruchamia /bin/bash – w Jobie Kubernetes podamy komendę llamafactory-cli train ... z odpowiednią konfiguracją.
Dockerfile dla serwisu inferencyjnego (vLLM, GPU)
Drugi Dockerfile służy do zbudowania obrazu inference API, czyli serwera obsługującego zapytania do wytrenowanego modelu. Ten serwis wykorzystuje bibliotekę vLLM do wydajnego serwowania modeli z API stylizowanym na OpenAI. Również bazuje na Debianie 12 + Python 3.11.2 i współdzieli wiele zależności z obrazem treningowym, jednak nie potrzebuje narzędzi stricte treningowych (np. deepspeed). Kluczowe jest zainstalowanie vLLM oraz samej platformy LLaMA-Factory (jeśli korzystamy z jej CLI do uruchomienia serwera). LLaMA-Factory oferuje komendę llamafactory-cli api ... która uruchamia serwer API zgodny z protokołem OpenAI, wspierany przez backend vLLM. Poniżej Dockerfile:
# Obraz bazowy może być ten sam co w treningu, aby wykorzystać cache
FROM debian:12

ENV DEBIAN_FRONTEND=noninteractive
# Podstawowe pakiety systemowe i Python 3.11
RUN apt-get update && apt-get install -y python3.11 python3-pip && \
    apt-get clean && rm -rf /var/lib/apt/lists/*
RUN ln -s /usr/bin/python3.11 /usr/bin/python && ln -s /usr/bin/pip3 /usr/bin/pip

# Instalacja wymaganych bibliotek Python: PyTorch (GPU), Transformers, vLLM, LLaMA-Factory
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir torch torchvision --extra-index-url https://download.pytorch.org/whl/cu118 && \
    pip install --no-cache-dir transformers==4.33.0 vllm==0.1.5 llamafactory[torch]==0.9.3

# Uwaga: LLaMA-Factory zainstalowano dla skorzystania z jej API serwera.
# vLLM zapewnia wydajne inferencje, a LLaMA-Factory integruje się z nim.

WORKDIR /app
# (Opcjonalnie) Kopiowanie pliku konfiguracyjnego inferencji, jeśli chcemy go zawrzeć w obrazie:
# COPY ./inference_config.yaml /app/config/inference.yaml

# Ustawienie domyślnej komendy uruchamiającej serwer API na porcie 8000 z użyciem vLLM.
# (Zakładamy, że /app/config/inference.yaml istnieje lub zostanie zamontowany; 
# alternatywnie można przekazać parametry modelu przez zmienne środowiskowe).
CMD ["llamafactory-cli", "api", "/app/config/inference.yaml", "infer_backend=vllm", "API_PORT=8000"]
Objaśnienia: Obraz inferencyjny instaluje vLLM (np. wersję 0.1.5) oraz LLaMA-Factory. Potrzebny jest też PyTorch i Transformers – vLLM wykorzystuje modele Hugging Face pod spodem. W przykładzie zakładamy, że konfiguracja inferencji (YAML zawierający m.in. model_name_or_path i inne parametry) będzie dostępna pod /app/config/inference.yaml (np. przez kopiowanie podczas budowy lub montowanie ConfigMapy w Kubernetes). Domyślna komenda (CMD) uruchamia serwer: llamafactory-cli api <config> infer_backend=vllm API_PORT=8000. Ta komenda startuje w kontenerze serwis API kompatybilny z OpenAI, wykorzystujący vLLM do obsługi żądań. Dzięki temu możemy wysyłać zapytania REST (np. POST /v1/completions) do naszego modelu podobnie jak do API OpenAI.
Note: Kontener wymaga dostępu do plików modelu, które nie są częścią obrazu – omówiono to w sekcji o dynamicznym ładowaniu modeli. W skrócie, model zostanie pobrany lub zamontowany przy uruchomieniu podu.
Dockerfile dla serwisu UI (opcjonalny dashboard)
Jako opcjonalny komponent możemy dostarczyć lekki serwis UI zapewniający interfejs do monitorowania eksperymentów, zarządzania modelami lub prostego interaktywnego korzystania z modelu. Przykładem takiego serwisu jest dashboard do monitoringu/eksperymentów (MLflow) lub wbudowany w LLaMA-Factory LLaMA Board (Gradio). Poniżej przedstawiamy Dockerfile dla przykładowego rozwiązania opartego o MLflow, które może pełnić rolę panelu do śledzenia metryk treningu i wersjonowania modeli (model registry):
FROM debian:12

RUN apt-get update && apt-get install -y python3.11 python3-pip && \
    apt-get clean && rm -rf /var/lib/apt/lists/*
RUN ln -s /usr/bin/python3.11 /usr/bin/python && ln -s /usr/bin/pip3 /usr/bin/pip

# Instalacja MLflow i potrzebnych zależności (np. gunicorn, jeśli chcemy używać go jako serwer WSGI)
RUN pip install --no-cache-dir mlflow[sqlalchemy]==2.6.0 psycopg2-binary

WORKDIR /app

# Port 5000 to domyślny port interfejsu MLflow
EXPOSE 5000

# Uruchomienie serwera MLflow (tracking UI) słuchającego na wszystkich interfejsach
CMD ["mlflow", "server", "--host", "0.0.0.0", "--port", "5000"]
Objaśnienia: Ten obraz instaluje MLflow (wersja 2.6.0) – narzędzie do śledzenia eksperymentów i przechowywania modeli. Domyślnie mlflow server używa lokalnej bazy SQLite i zapisuje dane w katalogu roboczym; w środowisku produkcyjnym można przekazać parametry do użycia zewnętrznej bazy danych (np. PostgreSQL) i zewnętrznego magazynu artefaktów (np. bucket S3/GCS lub serwer Artifactory). W razie potrzeby do obrazu można dodać np. Grafanę/Prometeusza lub inne narzędzia monitorujące – zależnie od wymagań monitoringu. Alternatywnie, jeśli zamiast MLflow chcemy użyć wbudowanego UI LLaMA-Factory (LLaMA Board oparte o Gradio), można utworzyć obraz rozszerzający obraz treningowy o pakiet Gradio i uruchamiający llamafactory-cli webui (co wystawia web-aplikację do trenowania/inferencji przez przeglądarkę).
Konfiguracja Kubernetes
Poniżej przedstawiamy pliki YAML z konfiguracją obiektów Kubernetes potrzebnych do uruchomienia całej infrastruktury:
Job Kubernetes dla treningu LLaMA-Factory
Do uruchomienia procesu treningu fine-tune wykorzystujemy Job (obiekt typu Batch Job), ponieważ trening jest zadaniem wsadowym wykonywanym jednorazowo (nie jest to serwis). Job zapewni ponawianie podu w razie ewentualnego niepowodzenia i zakończy działanie po ukończeniu procesu treningowego. Poniższy YAML definiuje Job, który uruchamia kontener z wcześniej zbudowanym obrazem treningowym. W podzie żądamy GPU i podpinamy potrzebne wolumeny (np. na dane lub wyniki). Zmiennymi środowiskowymi przekazujemy token Hugging Face oraz dane dostępu do Artifactory, żeby podczas treningu można było pobrać model bazowy z Hugging Face (jeśli prywatny) oraz ewentualnie wysłać wytrenowany model do Artifactory. Komenda treningowa wskazuje na plik konfiguracyjny (zamontowany do kontenera) lub bezpośrednio podaje parametry. Przykładowa konfiguracja:
apiVersion: batch/v1
kind: Job
metadata:
  name: llama-factory-train
spec:
  backoffLimit: 1                   # w razie błędu ponów maksymalnie raz
  template:
    spec:
      restartPolicy: OnFailure
      containers:
      - name: training
        image: myregistry/llama-factory-train:latest
        imagePullPolicy: IfNotPresent
        args: ["llamafactory-cli", "train", "/app/config/train_config.yaml"]  # uruchomienie treningu
        env:
        - name: HF_TOKEN                  # Hugging Face token dla prywatnych modeli
          valueFrom:
            secretKeyRef:
              name: hf-secret
              key: HF_TOKEN
        - name: ARTIFACTORY_URL           # URL instancji Artifactory (repozytorium modeli)
          valueFrom:
            secretKeyRef:
              name: artifactory-secret
              key: ARTIFACTORY_URL
        - name: ARTIFACTORY_USERNAME      # Poświadczenia Artifactory (jeśli wymagane do upload)
          valueFrom:
            secretKeyRef:
              name: artifactory-secret
              key: ARTIFACTORY_USERNAME
        - name: ARTIFACTORY_PASSWORD
          valueFrom:
            secretKeyRef:
              name: artifactory-secret
              key: ARTIFACTORY_PASSWORD
        resources:
          limits:
            nvidia.com/gpu: 1            # przydzielenie 1 GPU do podu treningowego
          requests:
            nvidia.com/gpu: 1
        volumeMounts:
        - name: train-data
          mountPath: /app/data           # (opcjonalnie) dataset do treningu
        - name: train-output
          mountPath: /app/output         # (opcjonalnie) miejsce zapisu wynikowego modelu
      volumes:
      - name: train-data
        persistentVolumeClaim:
          claimName: training-data-pvc   # PVC z danymi treningowymi (jeśli używamy)
      - name: train-output
        persistentVolumeClaim:
          claimName: model-output-pvc    # PVC na wyniki (model) - do odbioru lub współdzielenia z inferencją
Objaśnienia: Job uruchamia pojedynczy kontener z obrazem treningowym. W args przekazujemy komendę do wykonania (można też użyć pola command). Zakładamy, że plik konfiguracyjny treningu (YAML z parametrami modelu, treningu, danych) został umieszczony w obrazie lub zamontowany – tutaj podajemy ścieżkę /app/config/train_config.yaml. Kontener otrzymuje dostęp do GPU poprzez dyrektywy resources.limits.requests nvidia.com/gpu. Wymaga to działającego w klastrze plugina NVIDIA (Device Plugin) oraz zainstalowanych sterowników na węzłach – zakładamy, że środowisko Kubernetes jest przygotowane do obsługi GPU. Montujemy dwa wolumeny: train-data (z danymi treningowymi, np. jeśli mamy duży zbiór na PVC) oraz train-output (gdzie zapiszemy wytrenowany model lub checkpointy). train-output PVC może posłużyć do przeniesienia wyniku do serwisu inferencyjnego lub do późniejszego pobrania. Zmienna HF_TOKEN jest ustawiona z Sekretu – pozwoli to LLaMA-Factory pobrać model bazowy z Hugging Face Hub, jeśli model_name_or_path wskazuje na prywatny model (token będzie automatycznie użyty przez bibliotekę huggingface_hub[1]). Z kolei zmienne Artifactory (URL i poświadczenia) mogą być użyte przez skrypt po zakończeniu treningu do wysłania artefaktów modelu do repozytorium (np. można skonfigurować w pliku YAML treningu wykonywanie hook-u eksportującego model, lub uruchomić dodatkowy krok w kontenerze – np. skrypt curl do Artifactory). W restartPolicy ustawiono OnFailure – po zakończonym sukcesem treningu pod się nie wznawia.
Deployment Kubernetes dla inference API (z autoskalowaniem GPU)
Inferencja będzie realizowana przez serwis API wdrożony jako Deployment z replikami. Każda replika (pod) uruchamia nasz obraz inferencyjny, nasłuchując na określonym porcie (np. 8000) i obsługując zapytania użytkowników. Ponieważ zapytania do modelu mogą być kosztowne, można uruchomić kilka replik oraz włączyć autoskalowanie horyzontalne zależne od obciążenia. Poniższy YAML definiuje Deployment dla serwisu API oraz HorizontalPodAutoscaler (HPA), który będzie skalował liczba replik w zależności od użycia zasobów. Każdy pod wymaga GPU do działania (vLLM wykorzystuje GPU do inferencji). Konfiguracja modelu (np. który model serwujemy) może być przekazana przez zmienne środowiskowe lub plik konfig. Podobnie jak w Job, ustawiamy token HF i ewentualne parametry pobierania modelu. Przykład:
apiVersion: apps/v1
kind: Deployment
metadata:
  name: llama-factory-inference
spec:
  replicas: 1
  selector:
    matchLabels:
      app: llama-infer
  template:
    metadata:
      labels:
        app: llama-infer
    spec:
      containers:
      - name: inference
        image: myregistry/llama-factory-infer:latest
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 8000                      # port API (OpenAI-style)
        env:
        - name: HF_TOKEN
          valueFrom:
            secretKeyRef:
              name: hf-secret
              key: HF_TOKEN
        - name: MODEL_PATH                         # przykład: przekazanie ścieżki lub nazwy modelu
          value: "/models/Meta-Llama-3-8B"         # (jeśli model montowany lokalnie)
        resources:
          limits:
            nvidia.com/gpu: 1                     # każda replika używa 1 GPU
          requests:
            nvidia.com/gpu: 1
        volumeMounts:
        - name: model-storage
          mountPath: /models                      # montujemy wolumen z plikami modelu
      volumes:
      - name: model-storage
        persistentVolumeClaim:
          claimName: model-output-pvc             # PVC zawierający wytrenowany model (lub dynamicznie załadowany)
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: llama-inference-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: llama-factory-inference
  minReplicas: 1
  maxReplicas: 4
  metrics:
  - type: Resource
    resource:
      name: cpu
      targetAverageUtilization: 50
Objaśnienia: Deployment uruchamia początkowo 1 replikę serwisu inferencyjnego. Każdy pod jest podobny – korzysta z obrazu inferencyjnego i nasłuchuje na porcie 8000 (można wystawić go na zewnątrz przez Service typu LoadBalancer lub Ingress, co nie jest tu pokazane). W env ustawiamy HF_TOKEN (jeśli serwer miałby w razie potrzeby pobierać model z Hugging Face – np. w przypadku przeładowania innego modelu). Ustawiliśmy też przykładową zmienną MODEL_PATH – w alternatywnym scenariuszu można by przekazać do kontenera, jaki model ma załadować. Nasz Dockerfile ustawia domyślnie, że będzie szukał konfiguracji w /app/config/inference.yaml. Zamiast budować inny obraz dla każdego modelu, możemy więc dynamicznie montować plik konfiguracyjny lub przekazywać parametry (np. przez zmienne). Tutaj zakładamy, że model zostanie zamontowany w ścieżce /models (np. poprzez PVC model-output-pvc – to ten sam, na który trening zapisał wyniki). Dzięki temu serwis wstanie z gotowymi wagami modelu lokalnie. Autoskalowanie: HPA jest skonfigurowany, by monitorować zużycie CPU – gdy średnie wykorzystanie CPU przekroczy 50%, zwiększy liczbę replik (maksymalnie do 4). Można w produkcji podpiąć HPA pod metryki GPU lub opóźnienia zapytań, co byłoby bardziej miarodajne (wymaga to jednak custom metrics – np. poprzez Prometheus Adapter – albo wykorzystania metryk wbudowanych jeśli vLLM je eksponuje). Tu dla prostoty użyto CPU jako proxy obciążenia. Autoskalowanie zapewni, że w czasie większego ruchu liczba podów z serwisem inferencyjnym wzrośnie, a w czasie mniejszego – zmaleje (nawet do 0 replik, jeśli chcemy scale-to-zero, aczkolwiek wtedy zimny start będzie opóźniony). Podkreślmy, że każda replika wymaga dostępnego GPU – HPA musi współdziałać z autoskalerem klastrowym dodającym węzły GPU w razie potrzeby.
ConfigMap i Secret dla tokenów (Hugging Face, Artifactory)
Do przekazania wrażliwych danych jak token dostępu Hugging Face czy hasła/API key do Artifactory używamy Secretów Kubernetes. Poniżej dwa Sekrety: jeden zawiera token Hugging Face (HF_TOKEN), drugi – dane dostępowe do Artifactory. Jeśli jakieś mniej wrażliwe informacje konfiguracyjne są potrzebne (np. domyślna nazwa modelu, parametry nie będące tajne), można je umieścić w ConfigMap. W naszym wypadku URL repozytorium modeli nie jest tajny, ale dla prostoty grupujemy go z poświadczeniami w sekrecie. Przykład definicji:
apiVersion: v1
kind: Secret
metadata:
  name: hf-secret
type: Opaque
stringData:
  HF_TOKEN: "hf_xxxxxxx"   # tutaj wstaw swój HuggingFace User Access Token
---
apiVersion: v1
kind: Secret
metadata:
  name: artifactory-secret
type: Opaque
stringData:
  ARTIFACTORY_URL: "https://artifactory.example.com/models"   # URL repozytorium modeli/artefaktów
  ARTIFACTORY_USERNAME: "myuser"
  ARTIFACTORY_PASSWORD: "mypassword"
Objaśnienia: Używamy stringData dla czytelności – w realnym środowisku wartości powinny być zakodowane base64 lub załadowane przez kubectl create secret. Token Hugging Face jest używany przez bibliotekę huggingface_hub do autoryzacji przy pobieraniu modeli (gdy wskazujemy model prywatny lub przekraczamy limit niezalogowanego użytkownika)[1]. Z kolei dane Artifactory posłużą np. do uwierzytelnienia przy wysyłaniu plików modelu (z poziomu skryptu w kontenerze treningowym) lub do pobierania modelu przez kontener inferencyjny (jeśli model ma być ściągany z Artifactory). Np. można napisać w kontenerze inicjującym komendę: curl -u $ARTIFACTORY_USERNAME:$ARTIFACTORY_PASSWORD $ARTIFACTORY_URL/model.bin -o /models/model.bin – pobierze to model z repozytorium.
PersistentVolume (i StorageClass) dla modeli
W zależności od infrastruktury, możemy potrzebować skonfigurować wolumeny do przechowywania danych i modeli. Jeśli klaster Kubernetes ma włączone dynamiczne provisioning (np. na chmurze istnieje domyślny StorageClass dla dysków), wystarczy utworzyć PersistentVolumeClaim – tak jak training-data-pvc czy model-output-pvc we wcześniejszych sekcjach – a system sam utworzy odpowiedni PersistentVolume. Jeśli jednak dynamiczne wolumeny nie są dostępne (np. klaster on-premises bez domyślnego SC), musimy zdefiniować StorageClass i PersistentVolume manualnie.
Przykład: załóżmy, że chcemy wykorzystać lokalny dysk węzła do przechowania wytrenowanego modelu. Możemy stworzyć PersistentVolume z typem hostPath (ten wariant przypnie nas do konkretnego węzła – jest to więc prostszy przykład, choć w produkcji lepszy byłby sieciowy wolumen współdzielony, np. NFS lub Ceph, pozwalający na dostęp z wielu węzłów):
apiVersion: v1
kind: PersistentVolume
metadata:
  name: llama-model-pv
spec:
  capacity:
    storage: 50Gi
  accessModes:
  - ReadWriteOnce
  hostPath:
    path: /mnt/llamafactory/models   # ścieżka na węźle, gdzie pliki modelu będą przechowywane
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname   # PV przypięty do konkretnego węzła (nazwa węzła1)
          operator: In
          values:
          - gpu-node-1
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: model-output-pvc
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 50Gi
  volumeName: llama-model-pv
Objaśnienia: Powyżej utworzono PersistentVolume o rozmiarze 50Gi, wskazujący na katalog na węźle gpu-node-1. PersistentVolumeClaim o tej samej nazwie volumeName zarezerwuje ten PV dla naszych podów. StorageClass: W tym przykładzie użyliśmy statycznego wolumenu. Alternatywnie można zdefiniować StorageClass z provisioner: kubernetes.io/no-provisioner (dla lokalnych dysków) lub ze sterownikiem sieciowym (np. nfs-provisioner lub csi driver chmurowy). Jeśli klaster jest na chmurze (GKE/AKS/EKS), zazwyczaj mamy StorageClass standard lub gp2 – wtedy wystarczy PVC (system utworzy dysk w chmurze). W każdym razie, w naszych definicjach Deployment/Job odwołujemy się do PVC (model-output-pvc czy training-data-pvc), więc należy upewnić się, że takie PVC istnieją i są podpięte do odpowiednich PV/SC. Wolumen model-output-pvc jest kluczowy, bo służy do przekazania wynikowego modelu z etapu treningu do etapu inferencji (tutaj jako przykład – można też zamiast tego polegać wyłącznie na Artifactory/GCS do przekazania modelu, wtedy PVC nie jest konieczny).
Dynamiczne ładowanie modeli i integracja z vLLM
Jedną z wymagań jest możliwość dynamicznego ładowania modeli w serwisie inferencyjnym – tzn. nasz system powinien elastycznie pozyskiwać wytrenowane modele z różnych źródeł (Google Cloud Storage, Artifactory, lokalny dysk itp.) i uruchamiać je z wykorzystaniem vLLM. Poniżej opisujemy, jak to osiągnąć w przedstawionej infrastrukturze:
    • Ładowanie modelu z Hugging Face Hub: LLaMA-Factory i vLLM domyślnie wspierają podawanie modelu po nazwie z Hugging Face. W pliku konfiguracyjnym inferencji (np. examples/inference/llama3.yaml) pole model_name_or_path może wskazywać identyfikator modelu na HF Hub (np. "meta-llama/Meta-Llama-3-8B-Instruct") albo ścieżkę lokalną do folderu z modelem. Jeśli podamy nazwę z HF, przy starcie serwera nastąpi pobranie modelu przez Internet i cache’owanie go (dane trafiają domyślnie do ~/.cache/huggingface w kontenerze). Dzięki ustawieniu zmiennej HF_TOKEN serwis ma uprawnienia by pobrać modele prywatne/gated[1]. Uwaga: Pobieranie dużego modelu (kilkanaście GB) przy starcie podu może być czasochłonne. Dlatego zaleca się:
    • Podłączenie wolumenu hosta do ścieżki cache Hugging Face (w Dockerfile LLaMA-Factory sugerowano VOLUME ["/root/.cache/huggingface", ...]). W Kubernetes możemy zamontować np. persistent volume do ~/.cache/huggingface, aby kolejne pode korzystały z już pobranych wag zamiast ściągać je za każdym razem.
    • Alternatywnie, pobranie modelu wcześniej i udostępnienie go lokalnie (patrz niżej). LLaMA-Factory umożliwia też korzystanie z mirrorów (ModelScope Hub, Modelers Hub) poprzez zmienne środowiskowe USE_MODELSCOPE_HUB lub USE_OPENMIND_HUB.
    • Ładowanie modelu z lokalnego wolumenu (PVC): W naszym rozwiązaniu trening zapisuje model na PVC model-output-pvc. Ten sam wolumen jest montowany do podów inferencyjnych pod ścieżką, np. /models/<model-folder>. Jeżeli w konfiguracji inferencji model_name_or_path wskażemy ten lokalny katalog, serwis vLLM załaduje model bez próby pobierania z internetu. Na przykład, po treningu model może zostać wyeksportowany do formatu HuggingFace (np. pliki pytorch_model.bin, config.json, tokenizer.json w folderze). Jeśli podmontujemy ten folder do inferencji i ustawimy model_name_or_path: "/models/Meta-Llama-3-8B-Instruct" (zgodnie z nazwą folderu), to przy starcie llamafactory-cli api załaduje on model z lokalnej ścieżki. vLLM wymaga, by w momencie inicjalizacji modele były dostępne lokalnie – nie obsługuje sam streamowania z zewnętrznych źródeł, dlatego korzystamy z mechanizmów K8s do dostarczenia plików do podu przed uruchomieniem serwera.
    • Ładowanie modelu z GCS (Google Cloud Storage): Możemy traktować GCS podobnie jak inny magazyn plików. Dwa podejścia:
    • Montowanie bucketu GCS jako wolumenu: W GKE dostępny jest mechanizm Cloud Storage FUSE (oraz możliwość montowania bucketu jako wolumen w Cloud Run/Kubernetes). Pozwala to podłączyć bucket bezpośrednio do ścieżki w podzie. W tym scenariuszu np. wytrenowany model mógł zostać przekonwertowany do plików i zapisany w GCS (skryptem po treningu). Pod inferencyjny montujemy ten bucket (np. jako ReadOnlyMany) pod /models/modelX. vLLM przy starcie odczytuje pliki jakby były lokalne (Fuse zadba o streaming bloków w tle). Ten sposób eliminuje potrzebę kopiowania plików przy każdym starcie podu – model wczytuje się bezpośrednio z zewnętrznego magazynu.
    • Init Container do pobrania z GCS: Jeżeli nie chcemy lub nie możemy montować FUSE, możemy użyć init-containera, który uruchomi się przed głównym kontenerem serwera i pobierze pliki modelu z GCS do pustego wolumenu (EmptyDir lub PVC). Np. init-container mógłby użyć narzędzia gsutil:
    • initContainers:
- name: download-model
  image: google/cloud-sdk:latest    # zawiera gsutil
  env:
  - name: GOOGLE_APPLICATION_CREDENTIALS
    value: /var/secrets/gcp/key.json   # referencja do klucza serwice account (zamontowanego jako secret)
  args:
  - /bin/bash
  - -c 
  - |
    gsutil cp gs://my-bucket/models/model.bin /models/ && \
    gsutil cp gs://my-bucket/models/*tokenizer* /models/ && \
    gsutil cp gs://my-bucket/models/config.json /models/
  volumeMounts:
  - name: model-storage
    mountPath: /models
  - name: gcp-cred
    mountPath: /var/secrets/gcp
    • Powyżej init-container używa narzędzia gsutil do skopiowania plików modelu z bucketu do wolumenu współdzielonego (model-storage). Główna aplikacja vLLM startuje dopiero gdy init-container zakończy pracę, mając w /models gotowe pliki.
Podejście z GCS można dostosować do innych zewnętrznych magazynów zgodnych z S3.
    • Ładowanie modelu z Artifactory: Artifactory może przechowywać pliki modeli jako artefakty (np. spakowany katalog modelu albo poszczególne pliki binarne). Najprostszą metodą integracji jest również użycie init-containera lub skryptu pobierającego:
    • Można wykorzystać curl/wget jeśli Artifactory udostępnia pliki po HTTP(S). Mając URL i poświadczenia (jak przekazane w sekrecie), init-container może pobrać np. archiwum .zip modelu i rozpakować je do katalogu lokalnego.
    • Inną opcją jest użycie API Artifactory (JFrog) – np. komendy jfrog rt dl z JFrog CLI – ale to wymaga narzędzia w obrazie.
Przykład prostego init-containera pobierającego model z Artifactory:
initContainers:
- name: download-model
  image: curlimages/curl:latest
  env:
  - name: ARTIFACTORY_USER
    valueFrom: 
      secretKeyRef: {name: artifactory-secret, key: ARTIFACTORY_USERNAME}
  - name: ARTIFACTORY_PASS
    valueFrom:
      secretKeyRef: {name: artifactory-secret, key: ARTIFACTORY_PASSWORD}
  - name: ARTIFACTORY_URL
    valueFrom:
      secretKeyRef: {name: artifactory-secret, key: ARTIFACTORY_URL}
  args:
  - /bin/sh
  - -c
  - |
    echo "Downloading model from Artifactory...";
    curl -u $ARTIFACTORY_USER:$ARTIFACTORY_PASS -O $ARTIFACTORY_URL/model.zip && \
    unzip model.zip -d /models;
  volumeMounts:
  - name: model-storage
    mountPath: /models
Powyższy init-container używa oficjalnego minimalnego obrazu curl i zmiennych z sekretu. Pobiera plik model.zip (URL powinien wskazywać konkretny zasób w Artifactory) i rozpakowuje go do katalogu /models. Po starcie główna aplikacja vLLM ma dostęp do plików.
Integracja z vLLM: W każdym z powyższych scenariuszy kluczowe jest to, że vLLM w ramach llamafactory-cli api załaduje model przy starcie. LLaMA-Factory używając opcji infer_backend=vllm uruchamia serwer, który mapuje model do pamięci i udostępnia endpointy OpenAI API. vLLM jest zoptymalizowany pod kątem szybkiego przetwarzania wielu zapytań (dynamic batching, paged attention itp.[2]). Jednak nie przechowuje on stanu modeli poza pamięcią – to znaczy, jeśli chcemy przełączyć serwer na inny model, najprostszym podejściem jest uruchomienie nowego podu z wskazaniem innego modelu (czy to przez zmienną, czy konfigurację). Możliwe jest posiadanie wielu Deploymentów inference obsługujących różne modele jednocześnie (np. llama-factory-inference-modelA, ...-modelB) – wtedy każdy może ładować inny model z innego źródła. Istnieją prace nad dynamicznym przełączaniem modeli bez restartu (np. w społeczności vLLM rozważano mechanizmy snapshot-based hot swap), ale obecnie produkcyjnie typowe jest podejście "jeden pod – jeden model".
Monitorowanie i eksponowanie metryk: Nasza infrastruktura uwzględnia również komponenty do monitoringu: - Trening: LLaMA-Factory umożliwia raportowanie metryk do systemów takich jak Weights & Biases (W&B) – wystarczy dodać w konfiguracji treningu report_to: wandb i ustawić klucz API W&B. W podobny sposób można logować przebieg do MLflow – np. za pomocą wywołań w kodzie (jeśli korzystamy z callbacków lub ręcznie logujemy metryki). Job treningowy może zostać wzbogacony o sidecar kontener z narzędziem monitorującym GPU (np. nvidia-dcgm exporter do Prometheusa) – to pozwoli zbierać metryki sprzętowe podczas treningu. - Inference: Kontener z vLLM można rozszerzyć o eksport metryk (jeśli vLLM ich nie udostępnia natywnie, można np. opakować jego serwer w aplikację FastAPI/Starlette i dodać endpoint /metrics dla Prometheusa). Alternatywnie, wykorzystując rozwiązania takie jak KServe czy Seldon, można by osiągnąć dynamiczne przełączanie modeli i wbudowany monitoring, ale to poza scope pytania. - Dashboard UI (opcjonalny): W naszym rozwiązaniu opcjonalny serwis MLflow może służyć jako centralny panel. Trening konfigurowany może automatycznie rejestrować model i parametry do MLflow (np. używając MLflow Tracking API w kodzie treningu lub poprzez plugin). W efekcie po zakończeniu treningu model pojawi się w MLflow Model Registry (jako wersja modelu), skąd można go pobrać lub zautomatyzować wdrożenie. MLflow UI udostępni wykresy metryk, historię eksperymentów, a także artefakty (np. plik modelu, logi). W scenariuszu enterprise można zamiast MLflow wykorzystać istniejące narzędzia monitoringu lub dashboard LLaMA-Factory (Gradio) który umożliwia pewną kontrolę i podgląd generacji odpowiedzi w czasie rzeczywistym.
Podsumowując, dynamiczne ładowanie modeli polega na tym, że oddzielamy cykl życia modelu od cyklu życia obrazu kontenera. Obrazy są wspólne i niezależne od konkretnych wag modelu, a konkretne instancje modelu są ładowane do podów w momencie uruchomienia poprzez: - Montowanie gotowych plików (z PVC lub zewnętrznego storage), - Albo pobieranie ich w init fazie (z Hub/Artifactory). To zapewnia elastyczność – możemy wdrożyć nowy model dostarczając tylko jego parametry przez storage, bez konieczności budowania nowego obrazu Docker. vLLM w połączeniu z LLaMA-Factory umożliwia łatwe wystawienie interfejsu API dla dowolnego modelu zgodnego z HuggingFace (np. LLaMA, Mistral, GPT-J etc.), co czyni całą platformę bardzo uniwersalną.
Diagram architektury
Poniżej zamieszczono diagram (w formacie Mermaid) obrazujący architekturę całego rozwiązania – od treningu po serwowanie i monitoring. Zawiera on zależności między komponentami i przepływ danych (modele, metryki):
flowchart LR
    subgraph Kubernetes Cluster
        subgraph Training
            direction TB
            trainJob[Job: Fine-tuning<br/>LLaMA-Factory<br/>(PyTorch, GPU)] -->|zapisuje wytrenowany model| outputVolume[(PersistentVolume/Output)]
            trainJob -.logi/metryki.-> mlflowUI[(MLflow Tracking<br/>UI - Monitoring)] 
        end
        subgraph Inference
            direction TB
            infDeployment[Deployment: vLLM API<br/>(OpenAI-like, GPU pods)] -- ładuje model --> outputVolume
            infDeployment -.pobiera model.-> repo[(Model Repo:<br/>Artifactory/GCS)]
            infDeployment -.HF Hub--> hfHub[(HuggingFace Hub)]
        end
        uiDashboard[Optional UI Dashboard<br/>(Gradio or MLflow UI)] -->|monitoruje<br/>zarządza| trainJob
        uiDashboard -->|monitoruje| infDeployment
        HPA[[GPU HPA]] --> infDeployment
    end
    user(User) -->|Konfiguruje<br/>uruchamia trening| uiDashboard
    user -->|Wysyła zapytania<br/>do API (inferencja)| infDeployment
    trainJob -->|upload modelu| repo
    hfHub ==> trainJob
    hfHub ==> infDeployment
Legenda: Prostokąty reprezentują pody/serwisy w klastrze K8s; cylinder to wolumen (PV/PVC); elementy poza klastrem (HuggingFace Hub, Artifactory/GCS repo) są zaznaczone jako oddzielne komponenty z którymi klaster się komunikuje. Strzałki opisują przepływ: np. trening pobiera model bazowy z HuggingFace (jeśli wskazano) oraz po zakończeniu wysyła wytrenowany model do Artifactory lub zapisuje na PV. Serwis inferencyjny przy starcie pobiera model z PVC lub zewnętrznego repo (bądź z HF Hub, zależnie od konfiguracji) – jest to właśnie dynamiczne ładowanie modelu. Użytkownik może poprzez UI (np. Gradio Web UI lub MLflow) inicjować treningi nowych modeli oraz przeglądać dostępne modele, a także wysyłać zapytania do API modelu. Autoscaler (HPA) monitoruje obciążenie i skaluje Deployment inferencyjny (dodając kolejne instancje podów z GPU, gdy zwiększa się ruch). W zakresie monitoringu: metryki z treningu trafiają do MLflow/W&B (pokazane jako strzałka do MLflow UI), zaś inferencja może być monitorowana np. poprzez logi i ewentualne metryki w dashboardzie.
Źródła potwierdzają zastosowane technologie: oficjalny obraz LLaMA-Factory używa Python 3.11 z PyTorch (co zapewnia zgodność środowiska), LLaMA-Factory umożliwia wdrożenie serwisu API z backendem vLLM, a zmienne środowiskowe (jak HF_TOKEN) umożliwiają uwierzytelniony dostęp do modeli Hugging Face[1]. Ponadto, dobre praktyki zakładają przechowywanie modeli poza obrazami Docker – np. w zewnętrznym bucketcie – co opisano w kontekście integracji GCS z vLLM (mount FUSE lub init download). W zakresie monitorowania, LLaMA-Factory wspiera integrację z narzędziami typu W&B, co można wykorzystać obok zaproponowanego MLflow. Powyższa architektura jest więc kompletna i spełnia założone wymagania, pozwalając na efektywne trenowanie i serwowanie modeli LLM z wykorzystaniem LLaMA-Factory.
Źródła:
    1. Oficjalny obraz LLaMA-Factory – środowisko (Ubuntu 22.04, CUDA 12, Python 3.11, PyTorch 2.6), potwierdzający kompatybilność Python 3.11 z PyTorch/vLLM
    2. Dokumentacja LLaMA-Factory – uruchamianie API z vLLM
    3. Hugging Face docs – użycie tokena HF poprzez zmienną środowiskową HF_TOKEN[1]
    4. Google Cloud Blog – skalowanie vLLM z Cloud Storage (ładowanie modeli z GCS Fuse vs. obrazy)
    5. LLaMA-Factory docs – integracja Weights & Biases do monitorowania treningu

[1] Quickstart
https://huggingface.co/docs/huggingface_hub/en/quick-start
[2] LLM Inference with vLLM, Cloud Run and GCS | Google Cloud - Community
https://medium.com/google-cloud/scale-to-zero-llm-inference-with-vllm-cloud-run-and-cloud-storage-fuse-42c7e62f6ec6