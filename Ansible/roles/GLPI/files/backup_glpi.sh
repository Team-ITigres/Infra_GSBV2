#!/bin/bash

##############################################
# Script de backup GLPI Database
# Exécution depuis la VM Ansible
# Usage: ./backup_glpi.sh <host_lxc> [nom_optionnel]
##############################################

# Couleurs pour l'affichage
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
LXC_HOST="${1}"
CONTAINER_NAME="mariadb"
DB_USER="glpi_user"
DB_PASSWORD="GlpiUserPassw0rd!"
DB_NAME="glpi"
BACKUP_DIR="/root/backups/glpi"

# Vérifier que l'hôte est fourni
if [ -z "$LXC_HOST" ]; then
    echo -e "${RED}❌ Usage: $0 <host_lxc> [nom_optionnel]${NC}"
    echo -e "${YELLOW}💡 Exemple: $0 172.16.0.10 prod_avant_maj${NC}"
    exit 1
fi

# Nom personnalisé optionnel (ex: ./backup_glpi.sh 172.16.0.10 prod_avant_maj)
CUSTOM_NAME="${2:-$(date +%Y%m%d_%H%M%S)}"
BACKUP_FILE="${BACKUP_DIR}/glpidb_${CUSTOM_NAME}.sql"

echo -e "${YELLOW}🔄 Démarrage du backup GLPI sur ${LXC_HOST}...${NC}"

# Créer le dossier de backup s'il n'existe pas
mkdir -p "${BACKUP_DIR}"

# Vérifier que le conteneur existe et est actif sur le LXC distant
echo -e "${YELLOW}🔍 Vérification du conteneur ${CONTAINER_NAME} sur ${LXC_HOST}...${NC}"
if ! ssh root@${LXC_HOST} "docker ps --format '{{.Names}}' | grep -q '^${CONTAINER_NAME}$'"; then
    echo -e "${RED}❌ Erreur: Le conteneur ${CONTAINER_NAME} n'est pas en cours d'exécution sur ${LXC_HOST}${NC}"
    exit 1
fi

# Effectuer le dump via SSH
echo -e "${YELLOW}📦 Export de la base '${DB_NAME}' depuis ${LXC_HOST}...${NC}"
ssh root@${LXC_HOST} "docker exec ${CONTAINER_NAME} mysqldump \
    -u ${DB_USER} \
    -p'${DB_PASSWORD}' \
    --single-transaction \
    --routines \
    --triggers \
    --add-drop-table \
    ${DB_NAME}" > "${BACKUP_FILE}.tmp"

# Vérifier que le dump a réussi
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Erreur lors du dump de la base de données${NC}"
    rm -f "${BACKUP_FILE}.tmp"
    exit 1
fi

# Ajouter "USE glpi;" au début (nécessaire pour l'auto-restore)
echo "USE ${DB_NAME};" | cat - "${BACKUP_FILE}.tmp" > "${BACKUP_FILE}"
rm -f "${BACKUP_FILE}.tmp"

# Vérifier la taille du fichier
FILE_SIZE=$(du -h "${BACKUP_FILE}" | cut -f1)

echo -e "${GREEN}✅ Backup réussi !${NC}"
echo -e "${GREEN}📁 Fichier: ${BACKUP_FILE}${NC}"
echo -e "${GREEN}📊 Taille: ${FILE_SIZE}${NC}"

# Afficher les 5 derniers backups
echo ""
echo -e "${YELLOW}📚 Derniers backups disponibles:${NC}"
ls -lht "${BACKUP_DIR}"/glpidb_*.sql 2>/dev/null | head -5 | awk '{print "   "$9" ("$5")"}'

# Optionnel: Nettoyer les backups de plus de 30 jours
OLD_BACKUPS=$(find "${BACKUP_DIR}" -name "glpidb_*.sql" -mtime +30 -type f)
if [ -n "$OLD_BACKUPS" ]; then
    echo ""
    echo -e "${YELLOW}🗑️  Backups de plus de 30 jours trouvés:${NC}"
    echo "$OLD_BACKUPS"
    read -p "Voulez-vous les supprimer ? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        find "${BACKUP_DIR}" -name "glpidb_*.sql" -mtime +30 -type f -delete
        echo -e "${GREEN}✅ Anciens backups supprimés${NC}"
    fi
fi

echo ""
echo -e "${GREEN}🎉 Terminé !${NC}"
echo -e "${YELLOW}💡 Pour restaurer: cat ${BACKUP_FILE} | ssh root@${LXC_HOST} 'docker exec -i ${CONTAINER_NAME} mysql -u${DB_USER} -p${DB_PASSWORD} ${DB_NAME}'${NC}"
