#!/usr/bin/env bash
# Bootstraps a single-node k3s cluster with kube-prometheus-stack and KEDA.
# Tested on Ubuntu 24.04, 4 vCPU / 8 GB.
set -euo pipefail

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik" sh -
mkdir -p ~/.kube && cp /etc/rancher/k3s/k3s.yaml ~/.kube/config && chmod 600 ~/.kube/config

if ! command -v helm >/dev/null; then
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add kedacore https://kedacore.github.io/charts
helm repo update

helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --set grafana.adminPassword=lab \
  --set prometheus.prometheusSpec.retention=30d \
  --set prometheus.prometheusSpec.scrapeInterval=15s \
  --set alertmanager.enabled=false

helm upgrade --install keda kedacore/keda --namespace keda --create-namespace

echo "Waiting for pods..."
kubectl wait --for=condition=Ready pods --all -A --timeout=300s
kubectl get nodes
