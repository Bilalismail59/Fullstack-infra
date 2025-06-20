#!/bin/bash

# Script pour trouver la bonne version du chart SonarQube Helm

echo " RECHERCHE DES VERSIONS SONARQUBE HELM DISPONIBLES"
echo "===================================================="

echo ""
echo "=== 1. MISE À JOUR DES REPOSITORIES HELM ==="
helm repo add sonarqube https://SonarSource.github.io/helm-chart-sonarqube
helm repo update

echo ""
echo "=== 2. VERSIONS DISPONIBLES ==="
echo "Recherche des versions SonarQube disponibles..."
helm search repo sonarqube/sonarqube --versions | head -10

echo ""
echo "=== 3. DERNIÈRE VERSION STABLE ==="
LATEST_VERSION=$(helm search repo sonarqube/sonarqube --versions | grep -v "CHART VERSION" | head -1 | awk '{print $2}')
echo "Dernière version trouvée: $LATEST_VERSION"

echo ""
echo "=== 4. INFORMATIONS DÉTAILLÉES ==="
helm show chart sonarqube/sonarqube --version $LATEST_VERSION | grep -E "version|appVersion|description"

echo ""
echo "=== 5. VERSIONS RECOMMANDÉES ==="
echo "Voici les versions les plus stables récentes:"
helm search repo sonarqube/sonarqube --versions | grep -E "^sonarqube/sonarqube" | head -5

echo ""
echo " RECOMMANDATION"
echo "=================="
echo "Utilisez la version: $LATEST_VERSION"
echo ""
echo "Commande corrigée:"
echo "helm upgrade --install sonarqube sonarqube/sonarqube \\"
echo "  --namespace sonarqube \\"
echo "  --version $LATEST_VERSION \\"
echo "  --set postgresql.enabled=false \\"
echo "  --set postgresql.postgresqlServer=postgres.sonarqube.svc.cluster.local \\"
echo "  --set postgresql.postgresqlDatabase=sonarqube \\"
echo "  --set postgresql.postgresqlUsername=sonarqube \\"
echo "  --set postgresql.postgresqlPassword=\$POSTGRES_PASSWORD \\"
echo "  --set persistence.enabled=true \\"
echo "  --set persistence.size=10Gi \\"
echo "  --set service.type=LoadBalancer \\"
echo "  --set resources.requests.memory=1Gi \\"
echo "  --set resources.requests.cpu=500m \\"
echo "  --set resources.limits.memory=2Gi \\"
echo "  --set resources.limits.cpu=1000m"

