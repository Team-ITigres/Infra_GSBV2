# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## Infra GSBV2

Déploiement automatisé d'une infrastructure complète sur Proxmox via Terraform + Ansible, avec Active Directory, services Docker, réseau VLAN et équipements physiques.

---

## Environnement d'exécution

### Architecture globale
- **Proxmox** : hyperviseur hébergeant tous les LXC et VMs
- **CT 110 "terransible"** (`172.16.0.15`) : conteneur LXC Debian 13 — c'est là qu'on travaille
- **adminbox** : image Docker contenant Ansible, Terraform, expect, et tous les outils
- Le repo Git est cloné dans `/Infra_GSBV2` sur le CT terransible

### La fonction `terransible`
Définie dans `/root/.bashrc` du CT terransible. Lance le conteneur Docker `adminbox:latest` :
```bash
terransible                          # mode interactif (shell dans le conteneur)
terransible ansible-playbook foo.yml # exécute une commande dans le conteneur
terransible terraform apply          # exécute terraform dans le conteneur
```
Le conteneur monte :
- `/root/etc/ansible` → clés SSH Ansible
- `$PWD` → `/work` (répertoire de travail courant)
- `/root/.env_secret` → variables Terraform et Pulse

**Pour lancer Ansible** : toujours se placer dans `/Infra_GSBV2/Ansible` puis appeler `terransible ansible-playbook ...`

### Fichier `/root/.env_secret`
Contient les tokens Terraform et Pulse générés par `Script_Deploy.sh` :
```
TF_VAR_proxmox_api_url=...
TF_VAR_proxmox_api_token_id=...
TF_VAR_proxmox_api_token=...
TF_VAR_target_node=...
TF_VAR_chemin_cttemplate=...
PULSE_PROXMOX_URL=...
PULSE_PROXMOX_TOKEN_ID=...
PULSE_PROXMOX_TOKEN=...
PULSE_PROXMOX_NODE=...
```

### Clés SSH Ansible
Générées par Terraform dans `~/etc/ansible/keys/<hostname>` (ED25519, une clé par LXC).

---

## Déploiement initial (Script_Deploy.sh)

Lancé sur le **nœud Proxmox** avec : `bash Script_Deploy.sh full`

Ce que fait le script dans l'ordre :
1. Télécharge et restaure un template Windows Server 2022 (VM 2000)
2. Supprime les anciens CT/VMs (IDs : 110, 113, 114, 115, 116, 120, 121, 130 + VMs 201, 202)
3. Crée le bridge `vmbr2` (10.10.0.6/28, VLAN-aware) pour le réseau switchs
4. Crée le CT 110 "terransible" (Debian 13, 4 cores, 4Go RAM, 8Go disk)
5. Crée l'utilisateur/token Terraform (`terraform-prov@pve`) et Pulse sur Proxmox
6. Dans le CT : installe Docker, clone le repo Git, télécharge et charge `adminbox:latest`
7. Crée la fonction `terransible` dans `.bashrc`
8. Lance `terraform init` + `terraform apply` → crée tous les LXC et VMs
9. Lance en tmux : `Install_Linuxs.yml` + `Install_Windows.yml` en parallèle

---

## Infrastructure Terraform

### LXC Linux créés (via `variables.tf`)
| ID  | Nom           | IP            | Bridge | VLAN |
|-----|---------------|---------------|--------|------|
| 113 | Adguard       | 172.16.0.3    | vmbr0  | -    |
| 114 | Stack-Web     | 172.16.0.4    | vmbr0  | -    |
| 115 | Stack-App     | 172.16.0.5    | vmbr0  | -    |
| 116 | Dockermail    | 172.16.0.6    | vmbr0  | -    |
| 120 | SFTPGO        | 172.16.69.2   | vmbr0  | 69   |
| 121 | Nextcloud     | 172.16.69.3   | vmbr0  | 69   |
| 130 | ProxmoxBackup | 172.16.31.1   | vmbr0  | 31   |

### VMs Windows créées (clone du template 2000)
| ID  | Nom      | IP          |
|-----|----------|-------------|
| 201 | WinSRV01 | 172.16.0.1  |
| 202 | WinSRV02 | 172.16.0.2  |

---

## Inventory Ansible (`00_inventory.yml`)

| Nom           | IP             | Connexion       | User           | Auth            |
|---------------|----------------|-----------------|----------------|-----------------|
| WinSRV01      | 172.16.0.1     | WinRM port 5985 | Administrateur | Formation13@    |
| WinSRV02      | 172.16.0.2     | WinRM port 5985 | Administrateur | Formation13@    |
| Adguard       | 172.16.0.3     | SSH             | root           | clé SSH         |
| Stack-Web     | 172.16.0.4     | SSH             | root           | clé SSH         |
| Stack-App     | 172.16.0.5     | SSH             | root           | clé SSH         |
| Dockermail    | 172.16.0.6     | SSH             | root           | clé SSH         |
| SFTPGO        | 172.16.69.2    | SSH             | root           | clé SSH         |
| Nextcloud     | 172.16.69.3    | SSH             | root           | clé SSH         |
| ProxmoxBackup | 172.16.31.1    | SSH             | root           | clé SSH         |
| EdgeRouter    | 172.16.0.254   | network_cli     | ubnt           | Formation13@    |
| Sw01          | 10.10.0.3      | SSH via expect  | admin          | Formation13@    |
| Sw02          | 10.10.0.4      | SSH via expect  | admin          | Formation13@    |

Mot de passe universel : `Formation13@`

---

## Arborescence Ansible

```
/Infra_GSBV2/Ansible/
├── 00_inventory.yml
├── ansible.cfg
├── epreuve_E6.yml              ← orchestrateur principal
├── collecte_variables.yml      ← toutes les questions interactives
├── vars/
│   └── generated_vars.yml      ← généré par collecte_variables.yml
├── playbooks/
│   ├── Active_directory.yml         → WinSRV01 : OU + groupe + users AD
│   ├── dir_create_ad.yml            → WinSRV01 : dossier partagé + ACL NTFS
│   ├── nextcloud_create_folder.yml  → Nextcloud : dossier + partage groupe AD
│   ├── mappage_lecteur.yml          → WinSRV01 : GPO mappage lecteur réseau
│   ├── blocage_cmd.yml              → WinSRV01 : GPO blocage CMD
│   ├── blocage_panneau_config.yml   → WinSRV01 : GPO blocage Panneau de config
│   ├── bloquer_domaines_adguard.yml → Adguard : blocage domaines DNS
│   ├── parefeu.yml                  → EdgeRouter : règles pare-feu INTERVLAN
│   ├── parefeu_create_rule.yml      → sous-tâches pare-feu (include_tasks)
│   ├── nat_port_forwarding.yml      → EdgeRouter : règles NAT/DNAT
│   ├── Vif_dhcp_routeur.yml         → EdgeRouter : création VIF + DHCP
│   └── switchs.yml                  → Sw01/Sw02 : VLAN + ports via expect SSH
└── roles/
    ├── PromouvoirAD01/    # Promo DC + comptes de service + config LDAP Nextcloud
    ├── ReplicationAD02/   # Réplication AD sur WinSRV02
    ├── Nextcloud/         # Déploiement Nextcloud (Docker)
    ├── Adguard/           # Déploiement AdGuard (Docker)
    ├── GLPI/              # Déploiement GLPI (Docker)
    ├── GLPI_Agent_GPO/    # GPO déploiement agent GLPI
    ├── Dockermail/        # Serveur mail (Docker)
    ├── Roundcube/         # Webmail Roundcube
    ├── SFTPGO/            # Serveur SFTP
    ├── Traefik/           # Reverse proxy
    ├── Crowdsec/          # IDS/IPS
    ├── Pulse/             # Monitoring Proxmox
    ├── ProxmoxAddPBS/     # Ajout Proxmox Backup Server
    ├── ProxmoxBackup/     # Config PBS
    ├── Install_Docker/    # Installation Docker sur LXC
    └── MAJ/               # Mises à jour système
```

---

## Ordre d'exécution (epreuve_E6.yml)

1. `collecte_variables.yml` — questions interactives + génération `generated_vars.yml`
2. `Active_directory.yml` — OU + groupe + users AD sur WinSRV01
3. `dir_create_ad.yml` — dossier partagé Windows + ACL NTFS
4. `nextcloud_create_folder.yml` — dossier Nextcloud + partage groupe AD (conditionnel)
5. `mappage_lecteur.yml` — GPO mappage lecteur réseau
6. `blocage_cmd.yml` — GPO blocage CMD (conditionnel)
7. `blocage_panneau_config.yml` — GPO blocage Panneau de config (conditionnel)
8. `bloquer_domaines_adguard.yml` — blocage domaines DNS AdGuard
9. `parefeu.yml` — règles pare-feu INTERVLAN EdgeRouter (conditionnel)
10. `Vif_dhcp_routeur.yml` — VIF + DHCP EdgeRouter
11. `switchs.yml` — VLAN + ports Planet Sw01/Sw02

---

## Règles importantes

### Pattern collecte_variables.yml
- **TOUTES** les questions interactives sont dans `collecte_variables.yml`
- `vars_prompt` pour les questions simples en début de play
- `ansible.builtin.pause` dans des blocs conditionnels pour les questions dépendant d'une réponse
- Toutes les variables écrites dans `vars/generated_vars.yml` à la fin
- Les playbooks de `playbooks/` lisent **uniquement** `vars_files: ../vars/generated_vars.yml`
- Les constantes de rôle → second `vars_files: ../roles/<Role>/defaults/main.yml`

### YAML / Ansible
- Toujours `gather_facts: false` (booléen), jamais `gather_facts: no`
- Listes potentiellement `null` depuis le YAML généré : `| default([]) or []`
- Listes vides dans `generated_vars.yml` : écrire `[]` explicitement, pas de valeur vide

### Switchs Planet (Sw01/Sw02)
- Ne supportent **aucun** module Ansible réseau standard
- Passage obligatoire par `expect` + `delegate_to: localhost`
- Séquence de connexion :
  1. `expect "continue..."` → `send "\r"` ← **obligatoire avant Username**
  2. `expect "Username:"` → `send "admin\r"`
  3. `expect "Password:"` → `send "Formation13@\r"`
- **Une seule session CLI simultanée** → si bloqué : reboot physique du switch
- Timeout expect : 90 secondes

### Nextcloud (172.16.69.3, conteneur `nextcloud`)
- Données admin : `/var/www/html/data/nextcloud/files/` (dans le conteneur)
- `occ files:mkdir` et `occ sharing:create` **n'existent pas** dans NC 30
- Créer dossier : `docker exec -u www-data nextcloud mkdir -p ...` + `php occ files:scan --path=`
- Partager avec groupe AD : API OCS REST
  ```
  POST http://localhost/ocs/v2.php/apps/files_sharing/api/v1/shares?format=json
  shareType=1 (groupe), permissions=15 (r+w+create+delete)
  ```
- LDAP : app `user_ldap` doit être activée (`occ app:enable user_ldap`)
- Attributs LDAP obligatoires pour les groupes AD :
  - `ldapGroupMemberAssocAttr = member`
  - `ldapGroupFilterObjectclass = group`
- Config LDAP deployée par rôle `PromouvoirAD01` via template `ldap-config.sh.j2`

### AdGuard (172.16.0.3)
- Config : `/srv/adguard/adguard-conf/AdGuardHome.yaml`
- Docker mode **host** → écoute sur `172.16.0.3`, **pas** `127.0.0.1`
- Redémarrage : `community.docker.docker_container` (pas systemd)
- `wait_for` : utiliser `host: "{{ ansible_host }}"` (pas localhost)

### EdgeRouter (VyOS, 172.16.0.254)
- Module : `vyos.vyos.vyos_command`
- Pare-feu intervlan : ruleset `INTERVLAN_POLICY` sur `eth1`
- NAT : règles DNAT numérotées automatiquement (max existant + 1)
- Interface réseau principale : `eth1` (VLANs en VIF)
- IP WAN du routeur : `192.168.50.81` — les routes Traefik pointant sur cette IP font du **hairpin NAT** (les LANs internes accèdent aux services DMZ via l'IP WAN, comme depuis l'extérieur). C'est voulu, ne pas remplacer par les IPs directes des LXC.

---

## Variables principales (generated_vars.yml)

| Variable | Description |
|----------|-------------|
| `ou_name` | Nom de l'OU AD |
| `group_name` | Nom du groupe AD (ex: `grp_support_client`) |
| `folder_name` | Nom du dossier partagé Windows |
| `drive_letter` | Lettre de lecteur mappé (D-Z) |
| `block_cmd` | `oui/non` |
| `block_control_panel` | `oui/non` |
| `vlan_id` | ID du VLAN |
| `vlan_name` | Nom du VLAN |
| `id_vif` / `ip_vif` | VIF EdgeRouter |
| `dhcp_start/stop/gateway/dns` | Config DHCP |
| `firewall_rule` | `oui/non` |
| `vlan_source` / `vlan_dest` / `service` / `description` | Config pare-feu |
| `nat_rule` | `oui/non` |
| `nat_description/source_network/destination_ip/port/forward_to_ip/port` | Config NAT |
| `create_nextcloud_folder` | `oui/non` |
| `nextcloud_folder_name` | Nom du dossier Nextcloud |
| `users[]` | Liste users AD (firstname/lastname/username/password/email) |
| `domains[]` | Domaines à bloquer AdGuard |
| `switch_ports{}` | Ports access/trunk par switch (`[]` si vide, jamais null) |

---

## Commandes courantes

```bash
# Lancer le playbook E6 complet (depuis /Infra_GSBV2/Ansible)
cd /Infra_GSBV2/Ansible
terransible ansible-playbook epreuve_E6.yml

# Relancer un playbook seul
terransible ansible-playbook playbooks/bloquer_domaines_adguard.yml
terransible ansible-playbook playbooks/Vif_dhcp_routeur.yml
terransible ansible-playbook playbooks/switchs.yml

# Initialisation complète Linux/Windows
terransible ansible-playbook Install_Linuxs.yml
terransible ansible-playbook Install_Windows.yml

# Terraform (depuis /Infra_GSBV2/Terraform)
cd /Infra_GSBV2/Terraform
terransible terraform init
terransible terraform apply

# Déploiement initial (sur le nœud Proxmox, en tant que root)
bash Script_Deploy.sh full
```

**Note** : `--start-at-task` ne fonctionne pas avec `import_playbook` — relancer directement le playbook concerné.

---

## Collections Ansible requises (`requirements.yml`)

```
community.docker, ansible.windows, community.windows, microsoft.ad,
vyos.vyos, community.network, community.proxmox
```

Installation dans adminbox : `ansible-galaxy collection install -r requirements.yml`

---

## Services déployés

| Service | URL |
|---------|-----|
| AdGuard | http://172.16.0.3:3000 |
| Traefik | http://172.16.0.4:8080/dashboard/ |
| GLPI | http://172.16.0.5/glpi |
| Pulse | http://172.16.0.5:7655 |
| Nextcloud | http://172.16.69.3:8080 |
| SFTPGO | http://172.16.69.2:8080/web/admin |
| Roundcube | http://172.16.0.6 |
| ProxmoxBackup | https://172.16.31.1:8007 |

---

## CI/CD GitHub Actions

| Workflow | Déclencheur | Action |
|----------|-------------|--------|
| `build-adminbox.yml` | Push `main` modifiant `Dockerfile` | Build image + push `.tar` via SCP |
| `deploy-script.yml` | Push `main` modifiant `Script_Deploy.sh` | Déploie le script sur serveur web |
| `push-ghcr.yml` | Push `main` sur `Dockerfile` ou manuel | Build + push sur `ghcr.io/team-itigres/adminbox` |

Secrets requis : `M2SHELPER_CLE` (clé SSH), `M2SHELPER_IP` (IP serveur web), `GITHUB_TOKEN` (auto).
