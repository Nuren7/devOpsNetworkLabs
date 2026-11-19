#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CERT_DIR="$ROOT_DIR/nginx/certs"
K8S_DIR="$ROOT_DIR/k8s"
NAMESPACE="devops-lab"
BACKEND_IMAGE="devops-lab-backend:local"
NGINX_IMAGE="devops-lab-nginx:local"

for command in docker kubectl; do
  if ! command -v "$command" >/dev/null 2>&1; then
    printf 'Required command not found: %s\n' "$command" >&2
    exit 1
  fi
done

CURRENT_CONTEXT="$(kubectl config current-context)"
case "$CURRENT_CONTEXT" in
  kind-*)
    if ! command -v kind >/dev/null 2>&1; then
      printf 'The current context is kind, but the kind command is not installed.\n' >&2
      exit 1
    fi
    ;;
  minikube|minikube-*)
    if ! command -v minikube >/dev/null 2>&1; then
      printf 'The current context is Minikube, but the minikube command is not installed.\n' >&2
      exit 1
    fi
    ;;
  docker-desktop)
    ;;
  *)
    printf 'Unsupported Kubernetes context: %s\n' "$CURRENT_CONTEXT" >&2
    printf 'Use a kind, minikube, or docker-desktop context, or load the local images manually.\n' >&2
    exit 1
    ;;
esac

if [[ ! -s "$CERT_DIR/server.crt" || ! -s "$CERT_DIR/server.key" ]]; then
  printf 'Local TLS certificate or key is missing; generating it now.\n'
  bash "$ROOT_DIR/scripts/generate-cert.sh"
fi

if [[ ! -s "$CERT_DIR/server.crt" || ! -s "$CERT_DIR/server.key" ]]; then
  printf 'TLS certificate and key must exist in %s\n' "$CERT_DIR" >&2
  exit 1
fi

docker build --tag "$BACKEND_IMAGE" "$ROOT_DIR/backend"
docker build --tag "$NGINX_IMAGE" "$ROOT_DIR/nginx"

case "$CURRENT_CONTEXT" in
  kind-*)
    KIND_CLUSTER="${CURRENT_CONTEXT#kind-}"
    kind load docker-image "$BACKEND_IMAGE" "$NGINX_IMAGE" --name "$KIND_CLUSTER"
    ;;
  minikube|minikube-*)
    minikube image load "$BACKEND_IMAGE"
    minikube image load "$NGINX_IMAGE"
    ;;
  docker-desktop)
    printf 'Using Docker Desktop Kubernetes; locally built Docker images are shared with the cluster.\n'
    ;;
esac

kubectl apply -f "$K8S_DIR/namespace.yaml"
kubectl create secret tls myapp-tls \
  --namespace "$NAMESPACE" \
  --cert="$CERT_DIR/server.crt" \
  --key="$CERT_DIR/server.key" \
  --dry-run=client \
  -o yaml | kubectl apply -f -
kubectl apply -f "$K8S_DIR/"
kubectl rollout status deployment/backend-api --namespace "$NAMESPACE" --timeout=180s
kubectl rollout status deployment/nginx --namespace "$NAMESPACE" --timeout=180s

printf '\nKubernetes lab is ready in namespace %s.\n' "$NAMESPACE"
printf 'Use: kubectl port-forward --namespace %s service/nginx 8443:443\n' "$NAMESPACE"
printf 'Then test: curl -k --resolve myapp.local:8443:127.0.0.1 https://myapp.local:8443/health\n'
