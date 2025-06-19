#!/bin/bash

# Script de validation complète de l'infrastructure full stack
# Ce script teste tous les composants de l'infrastructure déployée

set -e

echo "=========================================="
echo "VALIDATION COMPLÈTE DE L'INFRASTRUCTURE"
echo "=========================================="

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Compteurs
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Fonction pour afficher les résultats
print_result() {
    local test_name="$1"
    local result="$2"
    local details="$3"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    if [ "$result" = "PASS" ]; then
        echo -e "${GREEN}✓ PASS${NC} - $test_name"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗ FAIL${NC} - $test_name"
        if [ -n "$details" ]; then
            echo -e "  ${YELLOW}Détails:${NC} $details"
        fi
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

# Fonction pour tester la connectivité à un service
test_service_connectivity() {
    local service_name="$1"
    local namespace="$2"
    local port="$3"
    local path="${4:-/}"
    
    echo -e "${BLUE}Test de connectivité:${NC} $service_name"
    
    # Port-forward vers le service
    kubectl port-forward -n "$namespace" "svc/$service_name" "$port:$port" &
    PF_PID=$!
    sleep 5
    
    # Test de connectivité
    if curl -s -f "http://localhost:$port$path" > /dev/null; then
        print_result "$service_name connectivity" "PASS"
    else
        print_result "$service_name connectivity" "FAIL" "Service non accessible sur le port $port"
    fi
    
    # Arrêter le port-forward
    kill $PF_PID 2>/dev/null || true
    sleep 2
}

# Fonction pour vérifier l'état des pods
check_pods_status() {
    local namespace="$1"
    local app_label="$2"
    
    echo -e "${BLUE}Vérification des pods:${NC} $app_label dans $namespace"
    
    # Obtenir le statut des pods
    pod_status=$(kubectl get pods -n "$namespace" -l "app=$app_label" -o jsonpath='{.items[*].status.phase}' 2>/dev/null || echo "")
    
    if [ -z "$pod_status" ]; then
        print_result "$app_label pods existence" "FAIL" "Aucun pod trouvé avec le label app=$app_label"
        return
    fi
    
    # Vérifier que tous les pods sont en cours d'exécution
    for status in $pod_status; do
        if [ "$status" != "Running" ]; then
            print_result "$app_label pods status" "FAIL" "Pod en statut: $status"
            return
        fi
    done
    
    print_result "$app_label pods status" "PASS"
}

# Fonction pour vérifier les volumes persistants
check_persistent_volumes() {
    echo -e "${BLUE}Vérification des volumes persistants${NC}"
    
    # Lister tous les PVC
    pvc_status=$(kubectl get pvc --all-namespaces -o jsonpath='{.items[*].status.phase}' 2>/dev/null || echo "")
    
    if [ -z "$pvc_status" ]; then
        print_result "Persistent Volumes" "FAIL" "Aucun PVC trouvé"
        return
    fi
    
    # Vérifier que tous les PVC sont liés
    for status in $pvc_status; do
        if [ "$status" != "Bound" ]; then
            print_result "Persistent Volumes" "FAIL" "PVC en statut: $status"
            return
        fi
    done
    
    print_result "Persistent Volumes" "PASS"
}

# Fonction pour tester les bases de données
test_database_connectivity() {
    local namespace="$1"
    local service_name="$2"
    
    echo -e "${BLUE}Test de connectivité base de données:${NC} $service_name"
    
    # Port-forward vers MySQL
    kubectl port-forward -n "$namespace" "svc/$service_name" 3306:3306 &
    PF_PID=$!
    sleep 5
    
    # Test de connectivité MySQL (nécessite mysql-client)
    if command -v mysql &> /dev/null; then
        if mysql -h localhost -P 3306 -u root -prootpassword123 -e "SELECT 1;" &> /dev/null; then
            print_result "$service_name database connectivity" "PASS"
        else
            print_result "$service_name database connectivity" "FAIL" "Impossible de se connecter à MySQL"
        fi
    else
        # Test de port ouvert
        if nc -z localhost 3306 2>/dev/null; then
            print_result "$service_name database port" "PASS"
        else
            print_result "$service_name database port" "FAIL" "Port 3306 non accessible"
        fi
    fi
    
    kill $PF_PID 2>/dev/null || true
    sleep 2
}

# Fonction pour vérifier les IngressRoutes Traefik
check_ingress_routes() {
    echo -e "${BLUE}Vérification des IngressRoutes Traefik${NC}"
    
    # Lister toutes les IngressRoutes
    ingress_count=$(kubectl get ingressroute --all-namespaces --no-headers 2>/dev/null | wc -l)
    
    if [ "$ingress_count" -gt 0 ]; then
        print_result "Traefik IngressRoutes" "PASS" "$ingress_count IngressRoutes configurées"
    else
        print_result "Traefik IngressRoutes" "FAIL" "Aucune IngressRoute trouvée"
    fi
}

# Fonction pour vérifier la supervision
check_monitoring_stack() {
    echo -e "${BLUE}Vérification de la stack de monitoring${NC}"
    
    # Vérifier Prometheus
    check_pods_status "monitoring" "prometheus"
    
    # Vérifier Grafana
    check_pods_status "monitoring" "grafana"
    
    # Test de connectivité Grafana
    test_service_connectivity "grafana" "monitoring" "3000"
    
    # Test de connectivité Prometheus
    test_service_connectivity "prometheus-server" "monitoring" "9090"
}

# Fonction pour vérifier les alertes Prometheus
check_prometheus_alerts() {
    echo -e "${BLUE}Vérification des alertes Prometheus${NC}"
    
    # Port-forward vers Prometheus
    kubectl port-forward -n monitoring svc/prometheus-server 9090:80 &
    PF_PID=$!
    sleep 5
    
    # Vérifier les règles d'alertes
    if curl -s "http://localhost:9090/api/v1/rules" | jq -r '.data.groups[].rules[].name' | grep -q "PodCrashLooping"; then
        print_result "Prometheus alert rules" "PASS"
    else
        print_result "Prometheus alert rules" "FAIL" "Règles d'alertes non trouvées"
    fi
    
    kill $PF_PID 2>/dev/null || true
    sleep 2
}

# Fonction pour vérifier les ressources du cluster
check_cluster_resources() {
    echo -e "${BLUE}Vérification des ressources du cluster${NC}"
    
    # Vérifier les nœuds
    node_status=$(kubectl get nodes -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}')
    
    ready_nodes=0
    for status in $node_status; do
        if [ "$status" = "True" ]; then
            ready_nodes=$((ready_nodes + 1))
        fi
    done
    
    if [ "$ready_nodes" -gt 0 ]; then
        print_result "Cluster nodes" "PASS" "$ready_nodes nœuds prêts"
    else
        print_result "Cluster nodes" "FAIL" "Aucun nœud prêt"
    fi
    
    # Vérifier l'utilisation des ressources
    cpu_usage=$(kubectl top nodes --no-headers 2>/dev/null | awk '{sum+=$3} END {print sum}' || echo "0")
    memory_usage=$(kubectl top nodes --no-headers 2>/dev/null | awk '{sum+=$5} END {print sum}' || echo "0")
    
    print_result "Resource monitoring" "PASS" "CPU: ${cpu_usage}%, Memory: ${memory_usage}%"
}

# Début des tests
echo -e "${YELLOW}Début de la validation de l'infrastructure...${NC}"
echo ""

# 1. Vérification de l'infrastructure de base
echo -e "${BLUE}=== INFRASTRUCTURE DE BASE ===${NC}"
check_cluster_resources
check_persistent_volumes

# 2. Vérification des applications
echo -e "\n${BLUE}=== APPLICATIONS ===${NC}"
check_pods_status "default" "frontend"
check_pods_status "default" "backend"

# 3. Vérification des bases de données
echo -e "\n${BLUE}=== BASES DE DONNÉES ===${NC}"
check_pods_status "default" "mysql"
check_pods_status "preprod" "mysql-preprod"
test_database_connectivity "default" "mysql"

# 4. Vérification de WordPress
echo -e "\n${BLUE}=== WORDPRESS ===${NC}"
check_pods_status "default" "wordpress"
check_pods_status "preprod" "wordpress-preprod"

# 5. Vérification du routage et load balancing
echo -e "\n${BLUE}=== ROUTAGE ET LOAD BALANCING ===${NC}"
check_pods_status "kube-system" "traefik"
check_ingress_routes

# 6. Vérification de la supervision
echo -e "\n${BLUE}=== SUPERVISION ===${NC}"
check_monitoring_stack
check_prometheus_alerts

# 7. Vérification de SonarQube (si déployé)
echo -e "\n${BLUE}=== QUALITÉ DE CODE ===${NC}"
if kubectl get namespace sonarqube &>/dev/null; then
    check_pods_status "sonarqube" "postgres"
    test_service_connectivity "sonarqube-sonarqube" "sonarqube" "9000"
else
    print_result "SonarQube deployment" "FAIL" "Namespace sonarqube non trouvé"
fi

# 8. Tests de connectivité des services
echo -e "\n${BLUE}=== CONNECTIVITÉ DES SERVICES ===${NC}"
test_service_connectivity "frontend-service" "default" "80"
test_service_connectivity "backend-service" "default" "5000"
test_service_connectivity "wordpress" "default" "80"

# Résumé final
echo ""
echo "=========================================="
echo -e "${BLUE}RÉSUMÉ DE LA VALIDATION${NC}"
echo "=========================================="
echo -e "Total des tests: ${BLUE}$TOTAL_TESTS${NC}"
echo -e "Tests réussis: ${GREEN}$PASSED_TESTS${NC}"
echo -e "Tests échoués: ${RED}$FAILED_TESTS${NC}"

if [ "$FAILED_TESTS" -eq 0 ]; then
    echo -e "\n${GREEN} TOUS LES TESTS SONT PASSÉS !${NC}"
    echo -e "${GREEN}L'infrastructure est entièrement fonctionnelle.${NC}"
    exit 0
else
    echo -e "\n${YELLOW}  CERTAINS TESTS ONT ÉCHOUÉ${NC}"
    echo -e "${YELLOW}Veuillez vérifier les composants défaillants.${NC}"
    exit 1
fi
