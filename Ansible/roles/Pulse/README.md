# Rôle Ansible Pulse

Déploiement automatisé de Pulse (Proxmox/PBS/PMG monitoring dashboard) avec Docker sur le même LXC que GLPI.

## Caractéristiques

- ✅ Déploiement Pulse via Docker Compose
- ✅ Base de données SQLite intégrée (pas de MariaDB externe requis)
- ✅ Configuration via variables d'environnement
- ✅ Monitoring Proxmox VE, Proxmox Backup Server et Proxmox Mail Gateway
- ✅ Healthcheck intégré pour assurer la disponibilité
- ✅ Cohabitation avec GLPI sur le même LXC (ports et réseaux séparés)
- ✅ Authentification bcrypt sécurisée
- ✅ Métriques persistantes avec rétention configurable
- ✅ Support HTTPS/TLS optionnel

## Prérequis

- Docker et Docker Compose installés sur la machine cible
- Collection Ansible `community.docker` installée
- Rôle `Install_Docker` appliqué (ou Docker déjà installé)
- Le rôle peut être déployé sur le même LXC que GLPI sans conflit

## Structure du rôle

```
Pulse/
├── defaults/main.yml          # Variables par défaut
├── tasks/main.yml             # Tâches principales de déploiement
├── templates/
│   └── docker-compose.yml.j2  # Template Docker Compose
└── README.md                  # Ce fichier
```

## Variables

### Configuration Pulse de base

| Variable | Défaut | Description |
|----------|--------|-------------|
| `pulse_version` | `latest` | Version de l'image Docker Pulse |
| `pulse_container_name` | `pulse` | Nom du conteneur Pulse |
| `pulse_frontend_port` | `7655` | Port d'accès web à Pulse |
| `pulse_backend_port` | `3000` | Port backend interne |

### Authentification

| Variable | Défaut | Description |
|----------|--------|-------------|
| `pulse_auth_user` | `admin` | Nom d'utilisateur admin |
| `pulse_auth_pass` | `PulseAdminPassw0rd!` | Mot de passe admin (bcrypt automatique) |

**⚠️ IMPORTANT:** Changez le mot de passe par défaut et utilisez Ansible Vault pour le sécuriser !

### Paramètres système

| Variable | Défaut | Description |
|----------|--------|-------------|
| `pulse_log_level` | `info` | Niveau de log (debug/info/warn/error) |
| `pulse_log_format` | `auto` | Format de log (auto/json/console) |
| `pulse_pve_polling_interval` | `10` | Intervalle polling Proxmox VE (secondes) |
| `pulse_pbs_polling_interval` | `60` | Intervalle polling PBS (secondes) |
| `pulse_pmg_polling_interval` | `60` | Intervalle polling PMG (secondes) |

### Fonctionnalités

| Variable | Défaut | Description |
|----------|--------|-------------|
| `pulse_enable_backup_polling` | `true` | Activer monitoring des backups |
| `pulse_enable_temperature_monitoring` | `true` | Activer monitoring température |
| `pulse_adaptive_polling_enabled` | `false` | Polling adaptatif pour gros clusters |
| `pulse_discovery_enabled` | `false` | Auto-découverte de nodes |
| `pulse_demo_mode` | `false` | Mode démo lecture seule |

### Rétention des métriques

| Variable | Défaut | Description |
|----------|--------|-------------|
| `pulse_metrics_retention_raw_hours` | `24` | Rétention données brutes (heures) |
| `pulse_metrics_retention_minute_hours` | `168` | Rétention par minute (heures = 7 jours) |
| `pulse_metrics_retention_hourly_days` | `90` | Rétention horaire (jours) |
| `pulse_metrics_retention_daily_days` | `730` | Rétention journalière (jours = 2 ans) |

### HTTPS/TLS (optionnel)

| Variable | Défaut | Description |
|----------|--------|-------------|
| `pulse_https_enabled` | `false` | Activer HTTPS |
| `pulse_tls_cert_file` | `/data/cert.pem` | Chemin certificat TLS |
| `pulse_tls_key_file` | `/data/key.pem` | Chemin clé privée TLS |

## Architecture

### Cohabitation avec GLPI

Le rôle Pulse est conçu pour cohabiter avec GLPI sur le même LXC :

| Service | Port | Réseau Docker | Dossier |
|---------|------|---------------|---------|
| GLPI | 80 | glpi-external | /srv/glpi |
| Pulse | 7655 | pulse-external | /srv/pulse |

**Aucun conflit** : Les services utilisent des ports, réseaux et dossiers différents.

### Volumes Docker persistants

| Volume | Montage | Contenu |
|--------|---------|---------|
| `pulse-data` | `/data` | Configuration, SQLite DB, fichiers chiffrés (.enc) |

### Fichiers de configuration dans le volume

Pulse stocke ses données dans `/data` (volume Docker `pulse-data`) :

- `.env` : Credentials (lecture seule propriétaire)
- `system.json` : Configuration générale
- `nodes.enc` : Credentials des nodes Proxmox (chiffré AES-256-GCM)
- `alerts.json` : Règles d'alerte
- `email.enc` : Configuration SMTP (chiffré)
- `webhooks.enc` : URLs webhooks (chiffré)
- `apprise.enc` : Config notifications (chiffré)
- `oidc.enc` : Config OIDC/SSO (chiffré)
- `api_tokens.json` : Tokens API (hashés)
- `ai.enc` : Config IA (chiffré)
- `metrics.db` : Base SQLite avec historique métriques

## Utilisation

### 1. Déploiement initial

Créer un playbook `deploy_pulse.yml` :

```yaml
---
- name: Déployer Pulse avec Docker
  hosts: GLPI  # Même hôte que GLPI
  become: yes
  roles:
    - Install_Docker  # Si Docker n'est pas déjà installé
    - Pulse
```

Exécuter :
```bash
ansible-playbook -i 00_inventory.yml deploy_pulse.yml
```

### 2. Déploiement combiné GLPI + Pulse

Pour déployer les deux services ensemble :

```yaml
---
- name: Déployer GLPI et Pulse sur le même LXC
  hosts: GLPI
  become: yes
  roles:
    - Install_Docker
    - GLPI
    - Pulse
```

Exécuter :
```bash
ansible-playbook -i 00_inventory.yml deploy_glpi_pulse.yml
```

### 3. Sécuriser les mots de passe avec Ansible Vault

Créer un fichier vault `group_vars/all/vault.yml` :

```bash
ansible-vault create group_vars/all/vault.yml
```

Contenu :
```yaml
---
vault_pulse_auth_pass: "VotreMotDePassePulseTresSecurise789!"
```

Référencer dans `group_vars/all/vars.yml` :
```yaml
---
pulse_auth_pass: "{{ vault_pulse_auth_pass }}"
```

Exécuter avec vault :
```bash
ansible-playbook -i 00_inventory.yml deploy_pulse.yml --ask-vault-pass
```

## Accès à Pulse

Après le déploiement, Pulse est accessible à l'adresse :
```
http://172.16.0.5:7655
```

**Identifiants par défaut :**
- Utilisateur : `admin`
- Mot de passe : celui configuré dans `pulse_auth_pass`

## Configuration post-installation

### 1. Ajouter des nodes Proxmox

Via l'interface web Pulse :
1. Aller dans Settings → Nodes
2. Cliquer sur "Add Node"
3. Entrer les informations :
   - Nom du node
   - URL (ex: `https://192.168.1.10:8006`)
   - Type (PVE/PBS/PMG)
   - Token API ou credentials

### 2. Configurer les alertes

Via l'interface web Pulse :
1. Settings → Alerts
2. Définir les seuils (CPU, RAM, stockage, etc.)
3. Configurer les notifications (email, webhook, Apprise)

### 3. Activer HTTPS

Générer un certificat SSL (Let's Encrypt, auto-signé, etc.) :

```bash
# Sur le LXC
mkdir -p /srv/pulse/certs
cd /srv/pulse/certs

# Certificat auto-signé (exemple)
openssl req -x509 -newkey rsa:4096 -nodes \
  -keyout key.pem \
  -out cert.pem \
  -days 365 \
  -subj "/CN=pulse.example.com"
```

Modifier les variables Ansible :
```yaml
pulse_https_enabled: true
pulse_tls_cert_file: "/srv/pulse/certs/cert.pem"
pulse_tls_key_file: "/srv/pulse/certs/key.pem"
```

Relancer le playbook pour appliquer les changements.

## Maintenance

### Mettre à jour Pulse

Modifier la version dans `defaults/main.yml` ou surcharger la variable :

```yaml
pulse_version: "v1.2.3"  # Nouvelle version
```

Relancer le playbook :
```bash
ansible-playbook -i 00_inventory.yml deploy_pulse.yml
```

Le conteneur sera recréé avec la nouvelle version.

### Accéder aux logs

**Logs Pulse :**
```bash
docker logs pulse
```

**Logs en temps réel :**
```bash
docker logs -f pulse
```

### Commandes utiles

**Redémarrer Pulse :**
```bash
cd /srv/pulse && docker compose restart
```

**Arrêter Pulse :**
```bash
cd /srv/pulse && docker compose down
```

**Supprimer complètement (y compris volumes) :**
```bash
cd /srv/pulse && docker compose down -v
```

**Accéder au shell du conteneur :**
```bash
docker exec -it pulse sh
```

**Vérifier l'état du conteneur :**
```bash
docker ps | grep pulse
```

**Inspecter le volume :**
```bash
docker volume ls | grep pulse
docker volume inspect pulse_pulse-data
```

**Accéder aux fichiers de configuration :**
```bash
# Lister les fichiers dans le volume
docker exec pulse ls -lh /data

# Voir la configuration système
docker exec pulse cat /data/system.json

# Voir les logs internes
docker exec pulse cat /data/logs/pulse.log
```

## Sauvegarde

### Sauvegarder les données Pulse

Le volume `pulse-data` contient toutes les données importantes (config, DB SQLite, fichiers chiffrés).

**Script de backup manuel :**

```bash
#!/bin/bash
BACKUP_DIR="/backups/pulse"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="pulse_backup_${DATE}.tar.gz"

# Créer le dossier de backup
mkdir -p "$BACKUP_DIR"

# Backup du volume Docker
docker run --rm \
  -v pulse_pulse-data:/data \
  -v "$BACKUP_DIR":/backup \
  alpine tar czf "/backup/$BACKUP_FILE" -C /data .

echo "Backup créé: $BACKUP_DIR/$BACKUP_FILE"
```

### Restaurer depuis un backup

```bash
#!/bin/bash
BACKUP_FILE="/backups/pulse/pulse_backup_20250130_120000.tar.gz"

# Arrêter Pulse
cd /srv/pulse && docker compose down

# Supprimer le volume existant
docker volume rm pulse_pulse-data

# Créer un nouveau volume
docker volume create pulse_pulse-data

# Restaurer les données
docker run --rm \
  -v pulse_pulse-data:/data \
  -v "$(dirname $BACKUP_FILE)":/backup \
  alpine tar xzf "/backup/$(basename $BACKUP_FILE)" -C /data

# Redémarrer Pulse
cd /srv/pulse && docker compose up -d
```

## Workflow GLPI + Pulse

Les deux services peuvent être gérés indépendamment :

### Déploiement séparé

```bash
# Déployer uniquement GLPI
ansible-playbook -i 00_inventory.yml deploy_glpi.yml

# Déployer uniquement Pulse
ansible-playbook -i 00_inventory.yml deploy_pulse.yml
```

### Déploiement combiné

```bash
# Déployer les deux en une seule commande
ansible-playbook -i 00_inventory.yml deploy_all.yml
```

### Accès aux services

- **GLPI** : http://172.16.0.5 (port 80)
- **Pulse** : http://172.16.0.5:7655 (port 7655)

## Dépannage

### Pulse ne démarre pas

Vérifier les logs :
```bash
docker logs pulse
docker inspect pulse --format='{{.State.Status}}: {{.State.Error}}'
```

Vérifier le healthcheck :
```bash
docker inspect pulse | grep -A 10 Health
```

### Erreur "port already in use"

Vérifier qu'aucun autre service n'utilise le port 7655 :
```bash
netstat -tlnp | grep 7655
lsof -i :7655
```

Si un conflit existe, modifier `pulse_frontend_port` dans les variables.

### Impossible d'ajouter un node Proxmox

Vérifier :
1. Le LXC peut accéder au node Proxmox (réseau)
2. Les credentials/token API sont corrects
3. L'API Proxmox est activée
4. Le certificat SSL est valide (ou désactiver la vérification)

### Base de données corrompue

En cas de corruption de `metrics.db` :

```bash
# Arrêter Pulse
cd /srv/pulse && docker compose down

# Accéder au volume et supprimer la DB
docker run --rm -v pulse_pulse-data:/data alpine rm /data/metrics.db

# Redémarrer Pulse (DB sera recréée)
cd /srv/pulse && docker compose up -d
```

**Note :** Ceci supprime l'historique des métriques !

### Réinitialiser complètement Pulse

**⚠️ ATTENTION : Ceci supprime toutes les données !**

```bash
cd /srv/pulse
docker compose down -v
docker volume rm pulse_pulse-data

# Relancer le playbook Ansible
ansible-playbook -i 00_inventory.yml deploy_pulse.yml
```

## Support et documentation

- Documentation officielle Pulse : https://github.com/rcourtman/Pulse
- Configuration : https://github.com/rcourtman/Pulse/blob/main/docs/CONFIGURATION.md
- Installation : https://github.com/rcourtman/Pulse/blob/main/docs/INSTALL.md
- Docker Hub : https://hub.docker.com/r/rcourtman/pulse

## Licence

Ce rôle Ansible est fourni tel quel, sous licence MIT-0.
