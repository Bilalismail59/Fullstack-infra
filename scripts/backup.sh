#!/bin/sh
# Script de sauvegarde PostgreSQL

# Variables
BACKUP_DIR="/backup"
DB_HOST="${DB_HOST:-postgres}"
DB_NAME="${DB_NAME:-wordpress_prod}"
DB_USER="${DB_USER:-wp_user}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"

# Créer le répertoire de sauvegarde
mkdir -p "${BACKUP_DIR}"

# Fonction de sauvegarde
backup_database() {
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    BACKUP_FILE="${BACKUP_DIR}/postgres_backup_${TIMESTAMP}.sql.gz"

    echo "$(date): Début de la sauvegarde de ${DB_NAME}"

    # Sauvegarde avec compression
    pg_dump -h "$DB_HOST" -U "$DB_USER" "$DB_NAME" | gzip > "$BACKUP_FILE"

    if [ $? -eq 0 ]; then
        echo "$(date): Sauvegarde réussie: ${BACKUP_FILE}"
        # Suppression des anciennes sauvegardes
        find "$BACKUP_DIR" -name "postgres_backup_*.sql.gz" -mtime +$RETENTION_DAYS -exec rm {} \;
        echo "$(date): Nettoyage des sauvegardes de plus de $RETENTION_DAYS jours terminé"
    else
        echo "$(date): Erreur lors de la sauvegarde de la base de données"
        exit 1
    fi
}

# Création du fichier de cron si inexistant
if [ ! -f /etc/crontabs/root ]; then
    touch /etc/crontabs/root
fi

# Ajouter tâche cron (à 2h chaque jour)
echo "0 2 * * * /backup.sh backup >> /var/log/backup.log 2>&1" > /etc/crontabs/root

# Démarrer cron si pas encore lancé (utile en conteneur)
crond

# Exécution immédiate si demandé
if [ "$1" = "backup" ]; then
    backup_database
fi

# Garde le conteneur actif si besoin
tail -f /dev/null
