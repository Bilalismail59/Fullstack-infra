#!/bin/bash

# Script d'importation des tableaux de bord Grafana
# Ce script importe automatiquement les tableaux de bord personnalisés dans Grafana

set -e

echo "=== Importation des tableaux de bord Grafana ==="

# Configuration
GRAFANA_URL="http://localhost:3000"
GRAFANA_USER="admin"
GRAFANA_PASSWORD="admin"
DASHBOARD_DIR="/home/ubuntu/monitoring"

# Fonction pour importer un tableau de bord
import_dashboard() {
    local dashboard_file=$1
    local dashboard_name=$(basename "$dashboard_file" .json)
    
    echo "Importation du tableau de bord: $dashboard_name"
    
    # Port-forward vers Grafana si nécessaire
    kubectl port-forward -n monitoring svc/grafana 3000:80 &
    PF_PID=$!
    sleep 5
    
    # Importation du tableau de bord
    curl -X POST \
        -H "Content-Type: application/json" \
        -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
        -d @"$dashboard_file" \
        "$GRAFANA_URL/api/dashboards/db" || echo "Erreur lors de l'importation de $dashboard_name"
    
    # Arrêt du port-forward
    kill $PF_PID 2>/dev/null || true
    sleep 2
}

# Vérification de la connectivité à Grafana
echo "Vérification de la connectivité à Grafana..."
kubectl port-forward -n monitoring svc/grafana 3000:80 &
PF_PID=$!
sleep 10

# Test de connectivité
if curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "$GRAFANA_URL/api/health" > /dev/null; then
    echo "Connexion à Grafana réussie"
    kill $PF_PID 2>/dev/null || true
else
    echo "Erreur: Impossible de se connecter à Grafana"
    kill $PF_PID 2>/dev/null || true
    exit 1
fi

# Importation des tableaux de bord
echo "Importation des tableaux de bord..."

if [ -f "$DASHBOARD_DIR/grafana-dashboard-infrastructure.json" ]; then
    import_dashboard "$DASHBOARD_DIR/grafana-dashboard-infrastructure.json"
fi

if [ -f "$DASHBOARD_DIR/grafana-dashboard-wordpress.json" ]; then
    import_dashboard "$DASHBOARD_DIR/grafana-dashboard-wordpress.json"
fi

echo "=== Importation terminée ==="

# Configuration des sources de données (si nécessaire)
echo "Vérification des sources de données..."
kubectl port-forward -n monitoring svc/grafana 3000:80 &
PF_PID=$!
sleep 5

# Vérification de la source de données Prometheus
PROMETHEUS_DS=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "$GRAFANA_URL/api/datasources" | jq -r '.[] | select(.type=="prometheus") | .name' 2>/dev/null || echo "")

if [ -z "$PROMETHEUS_DS" ]; then
    echo "Configuration de la source de données Prometheus..."
    curl -X POST \
        -H "Content-Type: application/json" \
        -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
        -d '{
            "name": "Prometheus",
            "type": "prometheus",
            "url": "http://prometheus-server:80",
            "access": "proxy",
            "isDefault": true
        }' \
        "$GRAFANA_URL/api/datasources" || echo "Erreur lors de la configuration de Prometheus"
else
    echo "Source de données Prometheus déjà configurée: $PROMETHEUS_DS"
fi

kill $PF_PID 2>/dev/null || true

echo "=== Configuration Grafana terminée ==="
echo "Accès à Grafana: kubectl port-forward -n monitoring svc/grafana 3000:80"
echo "Utilisateur: admin / Mot de passe: admin"