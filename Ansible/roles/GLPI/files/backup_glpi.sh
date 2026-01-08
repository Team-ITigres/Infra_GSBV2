#!/bin/bash

##############################################
# Script de backup GLPI Database
# Utilise l'inventaire Ansible pour la connexion
# Usage: ./backup_glpi.sh <nom_du_dump>
##############################################

# Couleurs pour l'affichage
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
INVENTORY="/work/Ansible/00_inventory.yml"
HOST="GLPI"
CONTAINER_NAME="mariadb"
DB_USER="glpi_user"
DB_PASSWORD="GlpiUserPassw0rd!"
DB_NAME="glpi"
BACKUP_DIR="/work/Ansible/roles/GLPI/files/docker-entrypoint-initdb.d"

# Vérifier que le nom est fourni
if [ -z "$1" ]; then
    echo -e "${RED}❌ Usage: $0 <nom_du_dump>${NC}"
    echo -e "${YELLOW}💡 Exemple: $0 glpidb_prod${NC}"
    exit 1
fi

# Vérifier que l'inventaire existe
if [ ! -f "$INVENTORY" ]; then
    echo -e "${RED}❌ Erreur: Inventaire Ansible introuvable: $INVENTORY${NC}"
    exit 1
fi

# Nom du backup
CUSTOM_NAME="$1"
BACKUP_FILE="${BACKUP_DIR}/${CUSTOM_NAME}.sql"

echo -e "${YELLOW}🔄 Démarrage du backup GLPI...${NC}"

# Créer le dossier de backup s'il n'existe pas
mkdir -p "${BACKUP_DIR}"

# Vérifier que le conteneur existe et est actif via Ansible
echo -e "${YELLOW}🔍 Vérification du conteneur ${CONTAINER_NAME} sur ${HOST}...${NC}"
CONTAINER_CHECK=$(ansible ${HOST} -i ${INVENTORY} -m shell -a "docker ps --filter name=${CONTAINER_NAME} --format '{{.Names}}'" 2>/dev/null | grep -v "^${HOST}" | grep "${CONTAINER_NAME}")
if [ -z "$CONTAINER_CHECK" ]; then
    echo -e "${RED}❌ Erreur: Le conteneur ${CONTAINER_NAME} n'est pas en cours d'exécution sur ${HOST}${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Conteneur ${CONTAINER_NAME} actif${NC}"

# Effectuer le dump via Ansible
echo -e "${YELLOW}📦 Export de la base '${DB_NAME}' depuis ${HOST}...${NC}"
ansible ${HOST} -i ${INVENTORY} -m shell -a "docker exec ${CONTAINER_NAME} mysqldump \
    -u ${DB_USER} \
    -p'${DB_PASSWORD}' \
    --single-transaction \
    --routines \
    --triggers \
    --add-drop-table \
    ${DB_NAME}" 2>/dev/null | grep -v "^${HOST}" | grep -v "CHANGED" > "${BACKUP_FILE}.tmp"

# Vérifier que le dump a réussi
if [ $? -ne 0 ] || [ ! -s "${BACKUP_FILE}.tmp" ]; then
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

# Afficher tous les backups disponibles
echo ""
echo -e "${YELLOW}📚 Dumps SQL disponibles dans docker-entrypoint-initdb.d:${NC}"
ls -lh "${BACKUP_DIR}"/*.sql 2>/dev/null | awk '{print "   "$9" ("$5")"}'

echo ""
echo -e "${GREEN}🎉 Terminé !${NC}"
echo -e "${YELLOW}💡 Le dump sera automatiquement importé au prochain déploiement avec une base vide${NC}"
