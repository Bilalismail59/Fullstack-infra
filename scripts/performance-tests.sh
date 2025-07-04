#!/bin/bash

# Script de tests de performance de l'infrastructure
# Ce script effectue des tests de charge et de performance sur les composants

set -e

echo "=== TESTS DE PERFORMANCE DE L'INFRASTRUCTURE ==="

# Couleurs
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Fonction pour tester les performances d'un service
performance_test() {
    local service_name="$1"
    local namespace="$2"
    local port="$3"
    local endpoint="${4:-/}"
    local requests="${5:-100}"
    
    echo -e "${BLUE}Test de performance:${NC} $service_name"
    
    # Port-forward vers le service
    kubectl port-forward -n "$namespace" "svc/$service_name" "$port:$port" &
    PF_PID=$!
    sleep 5
    
    # Test avec curl (simulation de charge légère)
    echo "Exécution de $requests requêtes vers $service_name..."
    
    start_time=$(date +%s)
    success_count=0
    total_time=0
    
    for i in $(seq 1 $requests); do
        response_time=$(curl -s -w "%{time_total}" -o /dev/null "http://localhost:$port$endpoint" 2>/dev/null || echo "999")
        if [ "$response_time" != "999" ]; then
            success_count=$((success_count + 1))
            total_time=$(echo "$total_time + $response_time" | bc -l)
        fi
        
        if [ $((i % 10)) -eq 0 ]; then
            echo -n "."
        fi
    done
    echo ""
    
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    if [ "$success_count" -gt 0 ]; then
        avg_response_time=$(echo "scale=3; $total_time / $success_count" | bc -l)
        success_rate=$(echo "scale=2; $success_count * 100 / $requests" | bc -l)
        
        echo -e "${GREEN}Résultats:${NC}"
        echo "  - Requêtes réussies: $success_count/$requests ($success_rate%)"
        echo "  - Temps de réponse moyen: ${avg_response_time}s"
        echo "  - Durée totale: ${duration}s"
        echo "  - Débit: $(echo "scale=2; $success_count / $duration" | bc -l) req/s"
    else
        echo -e "${RED}Aucune requête réussie${NC}"
    fi
    
    kill $PF_PID 2>/dev/null || true
    sleep 2
    echo ""
}

test_system_resources() {
    echo -e "${BLUE}=== UTILISATION DES RESSOURCES SYSTÈME ===${NC}"
    echo "Utilisation des ressources par nœud:"
    kubectl top nodes 2>/dev/null || echo "Metrics server non disponible"

    echo ""
    echo "Top 10 des pods consommant le plus de CPU:"
    kubectl top pods --all-namespaces --sort-by=cpu 2>/dev/null | head -11 || echo "Metrics server non disponible"

    echo ""
    echo "Top 10 des pods consommant le plus de mémoire:"
    kubectl top pods --all-namespaces --sort-by=memory 2>/dev/null | head -11 || echo "Metrics server non disponible"
}

test_network_latency() {
    echo -e "${BLUE}=== TESTS DE LATENCE RÉSEAU ===${NC}"
    echo "Test de latence frontend -> backend:"
    kubectl exec -n default deployment/frontend-deployment -- ping -c 5 backend-service.default.svc.cluster.local 2>/dev/null || echo "Test de ping échoué"

    echo ""
    echo "Test de latence frontend -> postgresql:"
    kubectl exec -n default deployment/frontend-deployment -- ping -c 5 postgresql.default.svc.cluster.local 2>/dev/null || echo "Test de ping échoué"
}

test_resilience() {
    echo -e "${BLUE}=== TESTS DE RÉSILIENCE ===${NC}"
    echo "Politiques de redémarrage des déploiements:"
    kubectl get deployments --all-namespaces -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,RESTART-POLICY:.spec.template.spec.restartPolicy,REPLICAS:.spec.replicas"

    echo ""
    echo "Historique des redémarrages (dernières 24h):"
    kubectl get pods --all-namespaces -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,RESTARTS:.status.containerStatuses[0].restartCount" | grep -v "0$" || echo "Aucun redémarrage détecté"
}

test_scalability() {
    echo -e "${BLUE}=== TESTS DE SCALABILITÉ ===${NC}"
    echo "Autoscalers configurés:"
    kubectl get hpa --all-namespaces 2>/dev/null || echo "Aucun HPA configuré"

    echo ""
    echo "Limites de ressources configurées:"
    kubectl get pods --all-namespaces -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,CPU-REQUESTS:.spec.containers[0].resources.requests.cpu,MEMORY-REQUESTS:.spec.containers[0].resources.requests.memory,CPU-LIMITS:.spec.containers[0].resources.limits.cpu,MEMORY-LIMITS:.spec.containers[0].resources.limits.memory" | head -20
}

generate_health_report() {
    echo -e "${BLUE}=== RAPPORT DE SANTÉ GLOBAL ===${NC}"
    echo "État des pods par namespace:"
    for ns in default preprod monitoring sonarqube kube-system; do
        if kubectl get namespace "$ns" &>/dev/null; then
            running=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | grep "Running" | wc -l)
            total=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | wc -l)
            echo "  $ns: $running/$total pods en cours d'exécution"
        fi
    done

    echo ""
    echo "Services exposés:"
    kubectl get services --all-namespaces | grep -E "(LoadBalancer|NodePort|ClusterIP)" | wc -l | xargs echo "Total:"

    echo ""
    echo "Volumes persistants:"
    kubectl get pv | grep "Bound" | wc -l | xargs echo "Volumes liés:"
    kubectl get pv | grep "Available" | wc -l | xargs echo "Volumes disponibles:"

    echo ""
    echo "Certificats TLS (via cert-manager):"
    kubectl get certificates --all-namespaces 2>/dev/null | grep "True" | wc -l | xargs echo "Certificats valides:" || echo "Cert-manager non configuré"
}

if ! command -v bc &> /dev/null; then
    echo "Installation de bc pour les calculs..."
    sudo apt-get update && sudo apt-get install -y bc
fi

echo -e "${YELLOW}Début des tests de performance...${NC}"
echo ""

echo -e "${BLUE}=== TESTS DE PERFORMANCE DES SERVICES ===${NC}"
performance_test "frontend-service" "default" "80" "/" "50"
performance_test "backend-service" "default" "5000" "/health" "30"
performance_test "wordpress" "default" "80" "/" "20"

test_system_resources
test_network_latency
test_resilience
test_scalability
generate_health_report

echo ""
echo -e "${GREEN}=== TESTS DE PERFORMANCE TERMINÉS ===${NC}"
echo "L'infrastructure a été testée pour les performances, la résilience et la scalabilité."
