#!/bin/bash

# Variables
NAMESPACE="monitoring"
RELEASE_NAME="prometheus"
CRD_BASE_URL="https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd"

# Liste des CRDs nécessaires
CRDS=(
  "monitoring.coreos.com_alertmanagers.yaml"
  "monitoring.coreos.com_podmonitors.yaml"
  "monitoring.coreos.com_prometheuses.yaml"
  "monitoring.coreos.com_prometheusrules.yaml"
  "monitoring.coreos.com_servicemonitors.yaml"
  "monitoring.coreos.com_thanosrulers.yaml"
)

echo " Création du namespace (si non existant)..."
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

echo " Téléchargement et application des CRDs..."
for crd in "${CRDS[@]}"; do
  echo "   $crd"
  kubectl apply -f "$CRD_BASE_URL/$crd"
done

echo " Installation du chart Helm bitnami/kube-prometheus..."
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

helm upgrade --install $RELEASE_NAME bitnami/kube-prometheus \
  --namespace $NAMESPACE \
  --create-namespace

echo " Installation terminée avec succès."
