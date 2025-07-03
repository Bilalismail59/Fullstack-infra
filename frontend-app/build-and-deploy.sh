#!/bin/bash

# Variables
SRC_WIN="/mnt/c/Users/ismob/Documents/Fullstack-infra"
DST_LINUX="$HOME/Fullstack-infra"
VM_USER="bilal"
VM_INSTANCE="chrome-entropy-464618-v3-prod-instance-frontend"
VM_ZONE="europe-west9-b"
VM_PROJECT="chrome-entropy-464618-v3"

echo " Copie du projet depuis Windows vers Linux natif..."
rm -rf "$DST_LINUX"
cp -r "$SRC_WIN" "$DST_LINUX"

cd "$DST_LINUX/frontend-app" || exit 1

echo " Nettoyage des dépendances..."
rm -rf node_modules pnpm-lock.yaml

echo " Installation de pnpm globalement (si nécessaire)..."
if ! command -v pnpm &> /dev/null; then
    sudo npm install -g pnpm
fi

echo " Installation des dépendances avec pnpm..."
pnpm install || exit 1

echo " Build du frontend React..."
pnpm run build || exit 1

echo " Création de l'archive dist.tar.gz..."
tar czf dist.tar.gz dist/ || exit 1

echo " Transfert de l'archive vers la VM GCP..."
gcloud compute scp dist.tar.gz "$VM_USER@$VM_INSTANCE:~/dist.tar.gz" \
  --zone="$VM_ZONE" \
  --project="$VM_PROJECT" || exit 1

echo " Extraction et déploiement sur la VM..."
gcloud compute ssh "$VM_USER@$VM_INSTANCE" \
  --zone="$VM_ZONE" \
  --project="$VM_PROJECT" \
  --command="rm -rf dist/ && tar xzf dist.tar.gz && sudo rm -rf /var/www/html/* && sudo cp -r dist/* /var/www/html/ && sudo systemctl restart nginx" || exit 1

echo " Déploiement terminé avec succès. Accède à : http://$(gcloud compute instances describe $VM_INSTANCE --zone=$VM_ZONE --format='get(networkInterfaces[0].accessConfigs[0].natIP)')"
