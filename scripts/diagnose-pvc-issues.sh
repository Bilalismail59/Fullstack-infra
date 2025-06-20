#!/bin/bash

# Script de diagnostic et correction des problèmes de PVC

NAMESPACE="sonarqube"

echo " DIAGNOSTIC DES PROBLÈMES PVC POSTGRESQL"
echo "=========================================="

echo ""
echo "=== 1. ÉTAT ACTUEL DES PVC ==="
kubectl get pvc -n $NAMESPACE -o wide 2>/dev/null || echo "Namespace $NAMESPACE n'existe pas encore"

echo ""
echo "=== 2. CLASSES DE STOCKAGE DISPONIBLES ==="
kubectl get storageclass

echo ""
echo "=== 3. VOLUMES PERSISTANTS ==="
kubectl get pv | grep -E "Available|Bound|Released" | head -10

echo ""
echo "=== 4. ÉVÉNEMENTS RÉCENTS ==="
kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' 2>/dev/null | tail -10 || echo "Pas d'événements dans $NAMESPACE"

echo ""
echo "=== 5. NŒUDS ET ZONES ==="
kubectl get nodes -o custom-columns=NAME:.metadata.name,ZONE:.metadata.labels.topology\.kubernetes\.io/zone,INSTANCE:.metadata.labels.node\.kubernetes\.io/instance-type

echo ""
echo "=== 6. DIAGNOSTIC DES PVC EXISTANTS ==="
for pvc in $(kubectl get pvc -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    echo "--- PVC: $pvc ---"
    kubectl describe pvc $pvc -n $NAMESPACE | grep -A 5 -B 5 "Events\|Status\|Volume"
done

echo ""
echo " SOLUTION: NETTOYAGE ET RECRÉATION"
echo "===================================="

echo "Cette solution va:"
echo "1.  Supprimer tous les PVCs existants"
echo "2.  Créer un nouveau PVC avec un nom unique"
echo "3.  Utiliser un timestamp pour éviter les conflits"
echo "4.  Forcer la liaison sur un nœud avec des ressources"

echo ""
echo "Commandes de nettoyage:"
echo "kubectl delete pvc --all -n $NAMESPACE"
echo "kubectl delete deployment postgres sonarqube -n $NAMESPACE"

echo ""
echo "Nouveau PVC sera créé avec:"
echo "- Nom unique: postgres-pvc-\$(date +%s)"
echo "- Classe de stockage: standard-rwo"
echo "- Taille: 10Gi"
echo "- Mode d'accès: ReadWriteOnce"

echo ""
echo " RECOMMANDATION"
echo "=================="
echo "Utilisez le workflow: sonarqube-setup-pvc-fixed.yaml"
echo "Il inclut:"
echo " Nettoyage automatique des anciens PVCs"
echo " Noms uniques avec timestamp"
echo " Monitoring détaillé du processus"
echo " Diagnostic automatique en cas d'échec"
