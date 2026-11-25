#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="marine"

echo "==> 1. kind yoxlanılır"
if ! command -v kind >/dev/null 2>&1; then
  echo "kind tapılmadı, quraşdırılır..."
  curl -fsSLo /tmp/kind https://github.com/kubernetes-sigs/kind/releases/latest/download/kind-linux-amd64
  chmod +x /tmp/kind
  sudo mv /tmp/kind /usr/local/bin/kind
fi
kind version

echo "==> 2. Cluster yoxlanılır"
if kind get clusters | grep -qx "$CLUSTER_NAME"; then
  echo "Cluster artıq var, kubeconfig bərpa olunur"
  kind export kubeconfig --name "$CLUSTER_NAME"
else
  kind create cluster --config k8s/kind-config.yaml
fi

echo "==> 3. Node-lar hazır olana qədər gözlənilir"
kubectl wait --for=condition=Ready nodes --all --timeout=180s

echo "==> 4. Namespace-lər"
kubectl apply -f k8s/namespaces.yaml

echo "==> 5. MinIO Secret"
if kubectl get secret minio-credentials -n storage >/dev/null 2>&1; then
  echo "Secret artıq var"
else
  PASSWORD=$(openssl rand -base64 16)
  kubectl create secret generic minio-credentials -n storage \
    --from-literal=MINIO_ROOT_USER=admin \
    --from-literal=MINIO_ROOT_PASSWORD="$PASSWORD"
fi

echo "==> 6. MinIO"
kubectl apply -f k8s/minio/minio.yaml
kubectl rollout status statefulset/minio -n storage --timeout=180s


echo "==> 6b. MinIO bucket-ləri"
kubectl delete job create-buckets -n storage --ignore-not-found
kubectl apply -f k8s/minio/create-buckets.yaml
kubectl wait --for=condition=complete job/create-buckets -n storage --timeout=180s

echo "==> 7. helm yoxlanılır"
if ! command -v helm >/dev/null 2>&1; then
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi
helm version --short
echo "==> 8. Strimzi operator"
if helm status strimzi -n kafka >/dev/null 2>&1; then
  echo "Strimzi artıq quraşdırılıb"
else
  helm install strimzi oci://quay.io/strimzi-helm/strimzi-kafka-operator -n kafka
fi
kubectl rollout status deployment/strimzi-cluster-operator -n kafka --timeout=300s

echo "==> 9. Kafka cluster"
kubectl apply -f k8s/kafka/kafka.yaml
kubectl wait kafka/marine-kafka -n kafka --for=condition=Ready --timeout=600s

echo "==> 10. Kafka topic-ləri"
kubectl apply -f k8s/kafka/topics.yaml


echo "==> 11. AIS ingestor image"
if docker image inspect ais-ingestor:0.1 >/dev/null 2>&1; then
  echo "Image artıq var"
else
  if [ ! -d ingestors/ais/wheels ]; then
    pip download -r ingestors/ais/requirements.txt -d ingestors/ais/wheels \
      --only-binary=:all: --python-version 3.12 --implementation cp \
      --platform manylinux_2_28_x86_64 --platform manylinux_2_17_x86_64 --platform manylinux2014_x86_64
  fi
  docker build -t ais-ingestor:0.1 ingestors/ais/
fi
kind load docker-image ais-ingestor:0.1 --name "$CLUSTER_NAME"

echo "==> 12. AIS ingestor Secret və Deployment"
if kubectl get secret aisstream-credentials -n ingestion >/dev/null 2>&1; then
  echo "Secret artıq var"
else
  kubectl create secret generic aisstream-credentials -n ingestion \
    --from-literal=AISSTREAM_API_KEY="$AISSTREAM_API_KEY"
fi
kubectl apply -f k8s/ingestion/ais-ingestor.yaml
kubectl rollout status deployment/ais-ingestor -n ingestion --timeout=120s



echo "==> 13. Hava ingestor image və CronJob"
if docker image inspect weather-ingestor:0.1 >/dev/null 2>&1; then
  echo "Image artıq var"
else
  if [ ! -d ingestors/weather/wheels ]; then
    pip download -r ingestors/weather/requirements.txt -d ingestors/weather/wheels \
      --only-binary=:all: --python-version 3.12 --implementation cp \
      --platform manylinux_2_28_x86_64 --platform manylinux_2_17_x86_64 --platform manylinux2014_x86_64
  fi
  docker build -t weather-ingestor:0.1 ingestors/weather/
fi
kind load docker-image weather-ingestor:0.1 --name "$CLUSTER_NAME"
kubectl apply -f k8s/ingestion/weather-ingestor.yaml

kubectl get nodes -L workload
kubectl get pods -n storage
kubectl get pods -n kafka
kubectl get kafkatopic -n kafka
kubectl get pods -n ingestion
kubectl get cronjob -n ingestion
echo ""
echo "Hazırdır!"