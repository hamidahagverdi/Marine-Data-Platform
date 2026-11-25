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
echo ""
echo "Hazırdır!"
kubectl get nodes -L workload
kubectl get pods -n storage