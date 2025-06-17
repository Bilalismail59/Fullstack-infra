#!/bin/bash

# Script de validation rapide de l'infrastructure
# Version corrigée avec les bons labels

set -e

echo "=== VALIDATION RAPIDE DE L'INFRASTRUCTURE ==="

# Couleurs
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Fonction pour afficher les résultats
check_component() {
    local component="$1"
    local namespace="$2"
    local selector="$3"
    
    echo -n "Vérification de $component... "
    
    if kubectl get pods -n "$namespace" -l "$selector" --no-headers 2>/dev/null | grep -q "Running"; then
        echo -e "${GREEN}✓ OK${NC}"
        return 0
    else
        echo -e "${RED}✗ ÉCHEC${NC}"
        return 1
    fi
}

# Fonction pour vérifier les services
check_service() {
    local service="$1"
    local namespace="$2"
    
    echo -n "Vérification du service $service... "
    
    if kubectl get service "$service" -n "$namespace" &>/dev/null; then
        echo -e "${GREEN}✓ OK${NC}"
        return 0
    else
        echo -e "${RED}✗ ÉCHEC${NC}"
        return 1
    fi
}

# Vérification des composants principaux
echo -e "${BLUE}=== INFRASTRUCTURE DE BASE ===${NC}"
check_component "Traefik" "kube-system" "app.kubernetes.io/name=traefik"

echo -e "\n${BLUE}=== APPLICATIONS ===${NC}"
check_component "Frontend" "default" "app=frontend"
check_component "Backend" "default" "app=backend"

echo -e "\n${BLUE}=== BASES DE DONNÉES ===${NC}"
check_component "MySQL Production" "default" "app=mysql"
check_component "MySQL Pré-production" "preprod" "app=mysql-preprod"

echo -e "\n${BLUE}=== WORDPRESS ===${NC}"
check_component "WordPress Production" "default" "app=wordpress"
check_component "WordPress Pré-production" "preprod" "app=wordpress-preprod"

echo -e "\n${BLUE}=== MONITORING ===${NC}"
check_component "Prometheus" "monitoring" "app.kubernetes.io/name=prometheus"
check_component "Grafana" "monitoring" "app.kubernetes.io/name=grafana"
check_component "Alertmanager" "monitoring" "app.kubernetes.io/name=alertmanager"

echo -e "\n${BLUE}=== SERVICES ===${NC}"
check_service "frontend-service" "default"
check_service "backend-service" "default"
check_service "mysql" "default"
check_service "wordpress" "default"
check_service "grafana" "monitoring"
check_service "prometheus-server" "monitoring"

# Vérification des volumes persistants
echo -e "\n${BLUE}=== STOCKAGE ===${NC}"
echo -n "Vérification des volumes persistants... "
pvc_count=$(kubectl get pvc --all-namespaces --no-headers 2>/dev/null | grep "Bound" | wc -l)
if [ "$pvc_count" -gt 0 ]; then
    echo -e "${GREEN}✓ OK${NC} ($pvc_count volumes liés)"
else
    echo -e "${RED}✗ ÉCHEC${NC}"
fi

# Vérification des IngressRoutes
echo -n "Vérification des IngressRoutes... "
ingress_count=$(kubectl get ingressroute --all-namespaces --no-headers 2>/dev/null | wc -l)
if [ "$ingress_count" -gt 0 ]; then
    echo -e "${GREEN}✓ OK${NC} ($ingress_count routes configurées)"
else
    echo -e "${RED}✗ ÉCHEC${NC}"
fi

# Test de connectivité simple
echo -e "\n${BLUE}=== CONNECTIVITÉ ===${NC}"
echo -n "Test de connectivité interne... "

# Test simple de résolution DNS
if kubectl exec -n default deployment/frontend-deployment -- nslookup backend-service &>/dev/null; then
    echo -e "${GREEN}✓ OK${NC}"
else
    echo -e "${RED}✗ ÉCHEC${NC}"
fi

# Résumé des namespaces
echo -e "\n${BLUE}=== RÉSUMÉ DES NAMESPACES ===${NC}"
kubectl get namespaces | grep -E "(default|preprod|monitoring|sonarqube|kube-system)" | while read ns rest; do
    pod_count=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | grep "Running" | wc -l)
    echo -e "Namespace ${YELLOW}$ns${NC}: $pod_count pods en cours d'exécution"
done

echo -e "\n${GREEN}=== VALIDATION TERMINÉE ===${NC}"
echo "Pour des tests plus détaillés, utilisez: ./validate-infrastructure.sh"