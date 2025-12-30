# Rôle Ansible GLPI

Déploiement automatisé de GLPI (Gestion Libre de Parc Informatique) avec Docker, MariaDB et restauration automatique depuis dump SQL.

## Caractéristiques

- ✅ Déploiement GLPI 11.0.4 via Docker Compose
- ✅ Base de données MariaDB 10.7
- ✅ Restauration automatique depuis dump SQL (docker-entrypoint-initdb.d)
- ✅ Détection intelligente des changements de dump
- ✅ Réinitialisation automatique de la base si le dump change
- ✅ Isolation réseau MariaDB (sécurité renforcée)
- ✅ Volumes Docker persistants pour config, files et marketplace
- ✅ Script de backup intégré avec l'inventaire Ansible
- ✅ Healthcheck MariaDB pour assurer la disponibilité

## Prérequis

- Docker et Docker Compose installés sur la machine cible
- Collection Ansible `community.docker` installée
- Rôle `Install_Docker` appliqué (ou Docker déjà installé)

## Structure du rôle

```
GLPI/
├── defaults/main.yml          # Variables par défaut
├── tasks/main.yml             # Tâches principales de déploiement
├── templates/
│   └── docker-compose.yml.j2  # Template Docker Compose
├── files/
│   ├── backup_glpi.sh         # Script de sauvegarde (exécuté depuis Ansible controller)
│   └── docker-entrypoint-initdb.d/
│       └── *.sql              # Dumps SQL pour initialisation auto
└── README.md                  # Ce fichier
```

## Variables

### Configuration MariaDB

| Variable | Défaut | Description |
|----------|--------|-------------|
| `mariadb_version` | `10.7` | Version de MariaDB |
| `mariadb_root_password` | `StrongRootPassw0rd!` | Mot de passe root MariaDB |
| `mariadb_database` | `glpi` | Nom de la base de données |
| `mariadb_user` | `glpi_user` | Utilisateur MariaDB pour GLPI |
| `mariadb_password` | `GlpiUserPassw0rd!` | Mot de passe utilisateur MariaDB |
| `mariadb_container_name` | `mariadb` | Nom du conteneur MariaDB |

### Configuration GLPI

| Variable | Défaut | Description |
|----------|--------|-------------|
| `glpi_version` | `11.0.4` | Version de GLPI |
| `glpi_container_name` | `glpi` | Nom du conteneur GLPI |
| `glpi_db_host` | `mariadb` | Hôte de la base de données |
| `glpi_db_name` | `glpi` | Nom de la base GLPI |
| `glpi_db_user` | `glpi_user` | Utilisateur GLPI pour la DB |
| `glpi_db_password` | `GlpiUserPassw0rd!` | Mot de passe DB GLPI |

**⚠️ IMPORTANT:** Changez tous les mots de passe par défaut et utilisez Ansible Vault pour les sécuriser !

## Architecture

### Réseau Docker

Le rôle crée deux réseaux Docker pour une sécurité optimale :

- **glpi-internal** : Réseau isolé (`internal: true`) pour la communication GLPI ↔ MariaDB
- **glpi-external** : Réseau externe pour l'accès HTTP à GLPI

MariaDB est **complètement isolé** et n'est accessible que par GLPI.

### Volumes Docker persistants

| Volume | Montage | Contenu |
|--------|---------|---------|
| `mariadb-data` | `/var/lib/mysql` | Base de données MariaDB |
| `glpi-files` | `/var/glpi/files` | Documents et fichiers uploadés |
| `glpi-config` | `/var/glpi/config` | Configuration GLPI |
| `glpi-marketplace` | `/var/glpi/marketplace` | Plugins installés |

### Restauration automatique du dump SQL

Le rôle utilise le mécanisme `docker-entrypoint-initdb.d` de MariaDB :

1. Les fichiers `*.sql` dans `files/docker-entrypoint-initdb.d/` sont copiés vers `/srv/glpi/dump/` sur le LXC
2. Le dossier `dump/` est monté en lecture seule dans MariaDB : `/docker-entrypoint-initdb.d`
3. Au premier démarrage (volume vide), MariaDB importe automatiquement tous les `.sql`

**Détection intelligente des changements :**
- Ansible compare les checksums des fichiers SQL
- Si un dump change, le rôle :
  1. Arrête les conteneurs
  2. Supprime le conteneur MariaDB
  3. Supprime le volume `glpi_mariadb-data`
  4. Relance les conteneurs → import automatique du nouveau dump

## Utilisation

### 1. Déploiement initial

Créer un playbook `deploy_glpi.yml` :

```yaml
---
- name: Déployer GLPI avec Docker
  hosts: GLPI
  become: yes
  roles:
    - Install_Docker  # Si Docker n'est pas déjà installé
    - GLPI
```

Exécuter :
```bash
ansible-playbook -i 00_inventory.yml deploy_glpi.yml
```

### 2. Ajouter votre dump SQL initial

Placez votre dump SQL dans :
```
roles/GLPI/files/docker-entrypoint-initdb.d/votre_dump.sql
```

**Format requis du dump :**
```sql
USE glpi;

DROP TABLE IF EXISTS `glpi_users`;
CREATE TABLE `glpi_users` ...
-- etc.
```

Le dump **doit** contenir `USE glpi;` au début pour sélectionner la bonne base.

### 3. Sécuriser les mots de passe avec Ansible Vault

Créer un fichier vault `group_vars/all/vault.yml` :

```bash
ansible-vault create group_vars/all/vault.yml
```

Contenu :
```yaml
---
vault_mariadb_root_password: "VotreMotDePasseRootTresSecurise123!"
vault_mariadb_password: "VotreMotDePasseGlpiTresSecurise456!"
```

Référencer dans `group_vars/all/vars.yml` :
```yaml
---
mariadb_root_password: "{{ vault_mariadb_root_password }}"
mariadb_password: "{{ vault_mariadb_password }}"
glpi_db_password: "{{ vault_mariadb_password }}"
```

Exécuter avec vault :
```bash
ansible-playbook -i 00_inventory.yml deploy_glpi.yml --ask-vault-pass
```

## Accès à GLPI

Après le déploiement, GLPI est accessible à l'adresse :
```
http://172.16.0.5
```

Les identifiants dépendent de votre dump SQL importé.

## Sauvegarde de la base de données

### Script de backup

Le script `backup_glpi.sh` est disponible dans `roles/GLPI/files/` et s'exécute **depuis le serveur Ansible** (pas depuis le LXC).

**Caractéristiques :**
- Utilise l'inventaire Ansible pour la connexion SSH
- Se connecte au LXC GLPI via Ansible
- Exécute `mysqldump` dans le conteneur MariaDB
- Sauvegarde directement dans `roles/GLPI/files/docker-entrypoint-initdb.d/`
- Ajoute automatiquement `USE glpi;` au début du dump

**Usage :**
```bash
./roles/GLPI/files/backup_glpi.sh nom_du_dump
```

**Exemple :**
```bash
# Créer un backup nommé "glpidb_prod"
./roles/GLPI/files/backup_glpi.sh glpidb_prod

# Résultat : roles/GLPI/files/docker-entrypoint-initdb.d/glpidb_prod.sql
```

**Workflow complet backup → restauration :**
```bash
# 1. Faire un backup
./roles/GLPI/files/backup_glpi.sh glpidb_20250130

# 2. Supprimer l'ancien dump (optionnel)
rm roles/GLPI/files/docker-entrypoint-initdb.d/ancien_dump.sql

# 3. Relancer Ansible → détection du changement → réimport automatique
ansible-playbook -i 00_inventory.yml deploy_glpi.yml
```

### Configuration du script

Éditer les variables dans `backup_glpi.sh` si nécessaire :

```bash
INVENTORY="/work/Ansible/00_inventory.yml"  # Chemin de l'inventaire
HOST="GLPI"                                  # Nom du host dans l'inventaire
CONTAINER_NAME="mariadb"                     # Nom du conteneur MariaDB
DB_USER="glpi_user"                          # Utilisateur DB
DB_PASSWORD="GlpiUserPassw0rd!"              # Mot de passe DB
DB_NAME="glpi"                               # Nom de la base
BACKUP_DIR="/work/Ansible/roles/GLPI/files/docker-entrypoint-initdb.d"
```

## Maintenance

### Mettre à jour GLPI

Modifier la version dans `defaults/main.yml` :
```yaml
glpi_version: "11.0.5"  # Nouvelle version
```

Relancer le playbook :
```bash
ansible-playbook -i 00_inventory.yml deploy_glpi.yml
```

Le conteneur sera recréé avec la nouvelle version.

### Changer le dump SQL

1. Placez le nouveau dump dans `files/docker-entrypoint-initdb.d/`
2. Supprimez l'ancien dump (optionnel mais recommandé)
3. Relancez le playbook → Ansible détectera le changement et réinitialisera automatiquement la base

### Accéder aux logs

**Logs GLPI :**
```bash
docker logs glpi
```

**Logs MariaDB :**
```bash
docker logs mariadb
```

**Logs en temps réel :**
```bash
docker logs -f glpi
docker logs -f mariadb
```

### Commandes utiles

**Redémarrer les conteneurs :**
```bash
cd /srv/glpi && docker compose restart
```

**Arrêter les conteneurs :**
```bash
cd /srv/glpi && docker compose down
```

**Supprimer complètement (y compris volumes) :**
```bash
cd /srv/glpi && docker compose down -v
```

**Accéder au shell GLPI :**
```bash
docker exec -it glpi bash
```

**Accéder à la console MySQL :**
```bash
docker exec -it mariadb mysql -uglpi_user -p'GlpiUserPassw0rd!' glpi
```

**Vérifier l'état des conteneurs :**
```bash
docker ps | grep -E "glpi|mariadb"
```

**Inspecter les volumes :**
```bash
docker volume ls | grep glpi
docker volume inspect glpi_mariadb-data
```

## Workflow de développement/production

### Développement

1. Travaillez sur votre GLPI de dev
2. Faites un backup :
   ```bash
   ./backup_glpi.sh glpidb_dev_$(date +%Y%m%d)
   ```

### Passage en production

1. Faites un backup de la prod actuelle :
   ```bash
   ./backup_glpi.sh glpidb_prod_backup_$(date +%Y%m%d)
   ```

2. Copiez votre dump de dev dans `files/docker-entrypoint-initdb.d/` :
   ```bash
   cp glpidb_dev_20250130.sql roles/GLPI/files/docker-entrypoint-initdb.d/
   rm roles/GLPI/files/docker-entrypoint-initdb.d/glpidb_prod_*.sql
   ```

3. Relancez Ansible sur la prod :
   ```bash
   ansible-playbook -i 00_inventory.yml deploy_glpi.yml --limit GLPI
   ```

### Rollback

Si besoin de revenir en arrière :
```bash
# 1. Remettre l'ancien dump
cp roles/GLPI/files/docker-entrypoint-initdb.d/glpidb_prod_backup_20250130.sql \
   roles/GLPI/files/docker-entrypoint-initdb.d/glpidb_prod.sql

# 2. Supprimer le dump problématique
rm roles/GLPI/files/docker-entrypoint-initdb.d/glpidb_dev_*.sql

# 3. Relancer Ansible
ansible-playbook -i 00_inventory.yml deploy_glpi.yml --limit GLPI
```

## Dépannage

### GLPI ne démarre pas

Vérifier les logs détaillés :
```bash
docker logs glpi
docker inspect glpi --format='{{.State.Status}}: {{.State.Error}}'
```

Vérifier que MariaDB est healthy :
```bash
docker ps | grep mariadb
# Doit afficher "(healthy)" dans la colonne STATUS
```

### La base n'est pas restaurée

Vérifier que le dump est bien présent :
```bash
ls -lh /srv/glpi/dump/
```

Vérifier que le volume MariaDB a bien été supprimé et recréé :
```bash
docker volume ls | grep mariadb
```

Forcer la réinitialisation :
```bash
cd /srv/glpi
docker compose down -v
docker volume rm glpi_mariadb-data
docker compose up -d
docker logs -f mariadb  # Suivre l'import
```

### Erreur "no such file or directory" au démarrage GLPI

Vérifiez que les volumes pointent bien vers `/var/glpi/*` et non `/var/www/html/glpi/*`.

L'image officielle GLPI utilise `/var/glpi` comme répertoire de données et crée automatiquement les liens symboliques vers `/var/www/html/glpi`.

### MariaDB n'importe pas le dump

Le dump doit :
1. Commencer par `USE glpi;`
2. Avoir l'extension `.sql`
3. Être dans `/srv/glpi/dump/` sur le LXC
4. Le volume MariaDB doit être **vide** (première création)

### Réinitialiser complètement GLPI

**⚠️ ATTENTION : Ceci supprime toutes les données !**

Depuis le serveur Ansible :
```bash
ansible GLPI -i 00_inventory.yml -m shell -a "cd /srv/glpi && docker compose down -v"
ansible-playbook -i 00_inventory.yml deploy_glpi.yml --limit GLPI
```

Ou directement sur le LXC :
```bash
cd /srv/glpi
docker compose down -v
# Relancer le playbook Ansible
```

## Support et documentation

- Documentation officielle GLPI : https://glpi-install.readthedocs.io/
- Image Docker GLPI : https://github.com/glpi-project/docker-images
- Documentation MariaDB : https://mariadb.com/kb/en/docker-official-image/
- GitHub GLPI : https://github.com/glpi-project/glpi

## Licence

Ce rôle Ansible est fourni tel quel, sans garantie.
