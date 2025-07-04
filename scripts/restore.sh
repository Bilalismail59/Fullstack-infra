#!/bin/sh
# Script de restauration PostgreSQL

# Variables
BACKUP_DIR="./postgres/backup"
DB_HOST="${DB_HOST:-localhost}"
DB_NAME="${DB_NAME:-wordpress_prod}"
DB_USER="${DB_USER:-wp_user}"

# Détecter le dernier fichier de sauvegarde
LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/postgres_backup_*.sql.gz 2>/dev/null | head -n1)

if [ -z "$LATEST_BACKUP" ]; then
  echo " Aucun fichier de sauvegarde trouvé dans $BACKUP_DIR"
  exit 1
fi

echo " Dernière sauvegarde trouvée : $LATEST_BACKUP"
echo " Décompression et restauration en cours..."

# Décompression et restauration dans PostgreSQL
gunzip -c "$LATEST_BACKUP" | psql -h "$DB_HOST" -U "$DB_USER" "$DB_NAME"

if [ $? -eq 0 ]; then
  echo " Restauration terminée avec succès"
else
  echo " Erreur lors de la restauration"
fi
