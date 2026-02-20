# Infra GSBV2

Déploiement automatisé d'une infrastructure complète sur Proxmox via Terraform + Ansible, avec Active Directory, services Docker, réseau VLAN et équipements physiques.

---

## Table des matières

1. [Architecture globale](#architecture-globale)
2. [Prérequis](#prérequis)
3. [Déploiement initial](#déploiement-initial-script_deploysh)
4. [Infrastructure Terraform](#infrastructure-terraform)
5. [Ansible — Initialisation Linux/Windows](#ansible--initialisation-linuxwindows)
6. [Ansible — Épreuve E6 (interactive)](#ansible--épreuve-e6-interactive)
7. [Services déployés](#services-déployés)
8. [Réseau](#réseau)
9. [CI/CD GitHub Actions](#cicd-github-actions)
10. [Dépannage](#dépannage)

---

## Architecture globale

```
Proxmox (hyperviseur)
└── CT 110 "terransible" (172.16.0.15) — Debian 13, Docker
    └── adminbox (conteneur Docker)
        ├── Ansible
        ├── Terraform 1.7.5
        ├── expect
        └── Bitwarden CLI
```

Tout Ansible et Terraform s'exécute **dans le conteneur `adminbox`** via la fonction `terransible` définie dans le `.bashrc` du CT 110 :

```bash
# Mode interactif
terransible

# Exécuter un playbook
terransible ansible-playbook epreuve_E6.yml

# Exécuter Terraform
terransible terraform apply
```

Le conteneur monte :
- `/root/etc/ansible` → clés SSH ED25519 par hôte
- `$PWD` → `/work` (répertoire de travail)
- `/root/.env_secret` → tokens Proxmox + Pulse

**Pour lancer Ansible** : toujours se placer dans `/Infra_GSBV2/Ansible` avant d'appeler `terransible`.

---

## Prérequis

- Nœud Proxmox avec accès root SSH
- Connectivité internet (Docker, Terraform, GitHub, templates Debian)
- ~200 Go de stockage disponible (template Windows + VMs)
- CPU : 16+ cœurs recommandés — RAM : 32+ Go recommandés

---

## Déploiement initial (Script_Deploy.sh)

**À exécuter sur le nœud Proxmox**, en tant que root :

```bash
bash Script_Deploy.sh full
```

Ce que fait le script dans l'ordre :

| Étape | Action |
|-------|--------|
| 1 | Télécharge et restaure le template Windows Server 2022 (VM 2000) |
| 2 | Supprime les anciens CT/VMs (IDs 110, 113-116, 120-121, 130, 201, 202) |
| 3 | Crée le bridge `vmbr2` (10.10.0.6/28, VLAN-aware) pour les switchs |
| 4 | Crée le CT 110 "terransible" (Debian 13, 4 cores, 4 Go RAM, 8 Go disk) |
| 5 | Crée l'utilisateur/token Terraform (`terraform-prov@pve`) et Pulse sur Proxmox |
| 6 | Dans le CT : installe Docker, clone le repo Git, charge `adminbox:latest` |
| 7 | Lance `terraform init` + `terraform apply` → crée tous les LXC et VMs |
| 8 | Lance en tmux en parallèle : `Install_Linuxs.yml` + `Install_Windows.yml` |

**Durée estimée** : 30-45 minutes selon la connexion.

---

## Infrastructure Terraform

Définie dans `Terraform/` — crée les ressources Proxmox depuis un template.

### LXC Linux créés

| ID  | Nom           | IP            | VLAN |
|-----|---------------|---------------|------|
| 113 | Adguard       | 172.16.0.3    | —    |
| 114 | Stack-Web     | 172.16.0.4    | —    |
| 115 | Stack-App     | 172.16.0.5    | —    |
| 116 | Dockermail    | 172.16.0.6    | —    |
| 120 | SFTPGO        | 172.16.69.2   | 69   |
| 121 | Nextcloud     | 172.16.69.3   | 69   |
| 130 | ProxmoxBackup | 172.16.31.1   | 31   |

### VMs Windows créées (clone du template 2000)

| ID  | Nom      | IP          |
|-----|----------|-------------|
| 201 | WinSRV01 | 172.16.0.1  |
| 202 | WinSRV02 | 172.16.0.2  |

Une clé SSH ED25519 est générée par Terraform pour chaque LXC et stockée dans `~/etc/ansible/keys/<hostname>`.

---

## Ansible — Initialisation Linux/Windows

### Install_Linuxs.yml

Joué sur tous les LXC Linux. Installe Docker puis déploie les services :

| Rôle | Hôte(s) cible | Description |
|------|---------------|-------------|
| `MAJ` | Tous | Mises à jour système |
| `Install_Docker` | Tous sauf ProxmoxBackup | Installation Docker Engine |
| `Adguard` | Adguard | Serveur DNS filtrant (mode réseau host) |
| `Traefik` | Stack-Web | Reverse proxy + certificats SSL auto-signés |
| `GLPI` | Stack-App | Gestion de parc IT (MySQL backend) |
| `Pulse` | Stack-App | Dashboard monitoring Proxmox |
| `Dockermail` | Dockermail | Serveur mail (Postfix/Dovecot, auth LDAP) |
| `Roundcube` | Dockermail | Webmail |
| `SFTPGO` | SFTPGO | Serveur SFTP (auth LDAP) |
| `Nextcloud` | Nextcloud | Partage de fichiers (PostgreSQL, LDAP AD) |
| `ProxmoxBackup` | ProxmoxBackup | Proxmox Backup Server |
| `ProxmoxAddPBS` | localhost | Enregistre PBS dans Proxmox |
| `Pulse_Agent` | Tous | Agent monitoring |

### Install_Windows.yml

Joué sur WinSRV01 et WinSRV02 :

| Rôle | Hôte | Description |
|------|------|-------------|
| `PromouvoirAD01` | WinSRV01 | Promotion DC primaire, comptes de service AD, config LDAP Nextcloud |
| `GLPI_Agent_GPO` | WinSRV01 | Déploiement agent GLPI via GPO |
| `ReplicationAD02` | WinSRV02 | Promotion DC secondaire, réplication AD |

---

## Ansible — Épreuve E6 (interactive)

**Orchestrateur** : `epreuve_E6.yml`

```bash
cd /Infra_GSBV2/Ansible
terransible ansible-playbook epreuve_E6.yml
```

### Étape 1 : collecte_variables.yml

Collecte interactive de toutes les variables puis les écrit dans `vars/generated_vars.yml`.

Variables collectées :

| Variable | Description |
|----------|-------------|
| `ou_name` | Nom de l'OU AD |
| `group_name` | Nom du groupe AD |
| `folder_name` | Nom du dossier partagé Windows |
| `drive_letter` | Lettre de lecteur mappé (D-Z) |
| `block_cmd` | Bloquer CMD : `oui/non` |
| `block_control_panel` | Bloquer Panneau de config : `oui/non` |
| `users[]` | Liste des utilisateurs AD (prénom/nom/login/mdp/email) |
| `domains[]` | Domaines à bloquer dans AdGuard |
| `vlan_id` / `vlan_name` | VLAN à créer |
| `id_vif` / `ip_vif` | Interface VIF sur EdgeRouter |
| `dhcp_start/stop/gateway/dns` | Plage DHCP |
| `firewall_rule` | Créer une règle pare-feu : `oui/non` |
| `nat_rule` | Créer une règle NAT : `oui/non` |
| `create_nextcloud_folder` | Créer dossier Nextcloud : `oui/non` |
| `nextcloud_folder_name` | Nom du dossier Nextcloud |
| `switch_ports{}` | Ports access/trunk par switch |

### Étape 2 : exécution des playbooks (dans l'ordre)

| # | Playbook | Cible | Action |
|---|----------|-------|--------|
| 1 | `Active_directory.yml` | WinSRV01 | OU + groupe + utilisateurs AD |
| 2 | `dir_create_ad.yml` | WinSRV01 | Dossier partagé + ACL NTFS |
| 3 | `nextcloud_create_folder.yml` | Nextcloud | Dossier + partage groupe AD (conditionnel) |
| 4 | `mappage_lecteur.yml` | WinSRV01 | GPO mappage lecteur réseau |
| 5 | `blocage_cmd.yml` | WinSRV01 | GPO blocage CMD (conditionnel) |
| 6 | `blocage_panneau_config.yml` | WinSRV01 | GPO blocage Panneau de config (conditionnel) |
| 7 | `bloquer_domaines_adguard.yml` | Adguard | Ajout domaines à la liste de blocage |
| 8 | `parefeu.yml` | EdgeRouter | Règles pare-feu INTERVLAN (conditionnel) |
| 9 | `Vif_dhcp_routeur.yml` | EdgeRouter | Création VIF + DHCP |
| 10 | `switchs.yml` | Sw01/Sw02 | Configuration VLAN + ports via expect SSH |

### Relancer un playbook seul

```bash
# Relancer uniquement la config réseau
terransible ansible-playbook playbooks/Vif_dhcp_routeur.yml

# Relancer uniquement AdGuard
terransible ansible-playbook playbooks/bloquer_domaines_adguard.yml

# Relancer uniquement les switchs
terransible ansible-playbook playbooks/switchs.yml
```

---

## Services déployés

| Service | URL | Description |
|---------|-----|-------------|
| **AdGuard** | http://172.16.0.3:3000 | DNS filtrant, blocage pub/malware |
| **Traefik** | http://172.16.0.4:8080/dashboard/ | Reverse proxy |
| **GLPI** | http://172.16.0.5/glpi | Gestion de parc IT |
| **Pulse** | http://172.16.0.5:7655 | Monitoring Proxmox |
| **Nextcloud** | http://172.16.69.3:8080 | Partage de fichiers |
| **SFTPGO** | http://172.16.69.2:8080/web/admin | Serveur SFTP + web admin |
| **Roundcube** | http://172.16.0.6 | Webmail |
| **ProxmoxBackup** | https://172.16.31.1:8007 | Sauvegarde Proxmox |

### Authentification par défaut

| Service | Connexion | Mot de passe |
|---------|-----------|--------------|
| WinRM (Windows) | `Administrateur` | `Formation13@` |
| SSH Linux | `root` | Clé ED25519 dans `~/etc/ansible/keys/` |
| Switchs | `admin` | `Formation13@` |
| EdgeRouter | `ubnt` | `Formation13@` |

> **Important** : changer les mots de passe par défaut après déploiement.

---

## Réseau

### Plan d'adressage

| Réseau | Bridge | Usage |
|--------|--------|-------|
| 172.16.0.0/24 | vmbr0 | Réseau principal (LXC, VMs, routeur) |
| 172.16.69.0/24 | vmbr0 VLAN 69 | Services données (Nextcloud, SFTPGO) |
| 172.16.31.0/24 | vmbr0 VLAN 31 | Sauvegarde (PBS) |
| 10.10.0.0/28 | vmbr2 | Réseau de gestion switchs |

### Inventory Ansible

| Hôte | IP | Connexion | Auth |
|------|----|-----------|------|
| WinSRV01 | 172.16.0.1 | WinRM:5985 | Administrateur/Formation13@ |
| WinSRV02 | 172.16.0.2 | WinRM:5985 | Administrateur/Formation13@ |
| Adguard | 172.16.0.3 | SSH | root + clé ED25519 |
| Stack-Web | 172.16.0.4 | SSH | root + clé ED25519 |
| Stack-App | 172.16.0.5 | SSH | root + clé ED25519 |
| Dockermail | 172.16.0.6 | SSH | root + clé ED25519 |
| SFTPGO | 172.16.69.2 | SSH | root + clé ED25519 |
| Nextcloud | 172.16.69.3 | SSH | root + clé ED25519 |
| ProxmoxBackup | 172.16.31.1 | SSH | root + clé ED25519 |
| EdgeRouter | 172.16.0.254 | network_cli | ubnt/Formation13@ |
| Sw01 | 10.10.0.3 | SSH via expect | admin/Formation13@ |
| Sw02 | 10.10.0.4 | SSH via expect | admin/Formation13@ |

### Notes switchs Planet

Les switchs Sw01/Sw02 ne supportent pas les modules Ansible réseau standard. La connexion passe par `expect` via `delegate_to: localhost`. Séquence obligatoire :

1. `expect "continue..."` → `send "\r"` ← **avant le login Username**
2. `expect "Username:"` → `send "admin\r"`
3. `expect "Password:"` → `send "Formation13@\r"`

Une seule session CLI simultanée — si bloquée, redémarrage physique du switch nécessaire.

### Notes Nextcloud (LDAP + partage)

- `occ files:mkdir` et `occ sharing:create` **n'existent pas** dans Nextcloud 30
- Créer un dossier : `docker exec -u www-data nextcloud mkdir -p ...` + `php occ files:scan --path=`
- Partager avec un groupe AD : API OCS REST (`POST /ocs/v2.php/apps/files_sharing/api/v1/shares`)
- Attributs LDAP obligatoires pour les groupes AD :
  - `ldapGroupMemberAssocAttr = member`
  - `ldapGroupFilterObjectclass = group`

---

## CI/CD GitHub Actions

Trois workflows dans `.github/workflows/` :

| Fichier | Déclencheur | Action |
|---------|-------------|--------|
| `build-adminbox.yml` | Push sur `main` modifiant `Dockerfile` | Build l'image + push `.tar` via SCP sur le serveur web |
| `deploy-script.yml` | Push sur `main` modifiant `Script_Deploy.sh` | Déploie le script sur le serveur web |
| `push-ghcr.yml` | Push sur `main` modifiant `Dockerfile` + déclenchement manuel | Build + push sur `ghcr.io/team-itigres/adminbox` |

### Secrets requis

| Secret | Usage |
|--------|-------|
| `M2SHELPER_CLE` | Clé SSH privée pour déploiement SCP |
| `M2SHELPER_IP` | IP du serveur web cible |
| `GITHUB_TOKEN` | Auto-injecté par GitHub (push GHCR) |

### Déclencher push-ghcr manuellement

GitHub → dépôt → **Actions** → **Push Adminbox to GHCR** → **Run workflow**

---

## Dépannage

### Problème YAML dans generated_vars.yml

Les listes vides doivent être `[]` explicitement. Une valeur vide génère `null` et plante Jinja2.

```yaml
# Correct
switch_ports:
  Sw01:
    access_ports: []
    trunk_ports:
      - "lag1"

# Incorrect — plante avec "did not find expected key"
switch_ports:
  Sw01:
    access_ports:
    trunk_ports: ['lag1']
      - "lag1"
```

### Groupe AD invisible dans Nextcloud

```bash
# Vérifier la config LDAP
docker exec -u www-data nextcloud php occ ldap:show-config s01 | grep -i group

# Forcer les attributs
docker exec -u www-data nextcloud php occ ldap:set-config s01 ldapGroupMemberAssocAttr "member"
docker exec -u www-data nextcloud php occ ldap:set-config s01 ldapGroupFilterObjectclass "group"

# Vider le cache
docker exec -u www-data nextcloud php occ ldap:clear-mapping group

# Vérifier que le groupe est visible
docker exec -u www-data nextcloud php occ ldap:search --group 'nom_groupe'
```

### Switch Planet bloqué

Si une session SSH est déjà ouverte sur le switch, toute nouvelle connexion échoue silencieusement. Seul un redémarrage physique du switch débloque la situation.

### Timeout AdGuard au redémarrage

Le conteneur AdGuard peut mettre jusqu'à 60 secondes à être disponible sur le port 53 après redémarrage. Le playbook est configuré avec `timeout: 60`.

### Relancer partiellement l'épreuve E6

`--start-at-task` ne fonctionne pas bien avec `import_playbook`. Relancer directement le playbook concerné :

```bash
terransible ansible-playbook playbooks/bloquer_domaines_adguard.yml
terransible ansible-playbook playbooks/Vif_dhcp_routeur.yml
terransible ansible-playbook playbooks/switchs.yml
```

### Gather_facts YAML

Toujours utiliser des booléens stricts en YAML :

```yaml
gather_facts: false   # Correct
gather_facts: no      # Incorrect — warning Ansible
```
