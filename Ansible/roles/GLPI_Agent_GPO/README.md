# GLPI_Agent_GPO

Deploie GLPI Agent sur les ordinateurs du domaine via une GPO importee depuis un backup (golden GPO).

## Description

Ce role Ansible deploie GLPI Agent en important une GPO pre-configuree (golden GPO) sur le controleur de domaine Active Directory. La GPO est creee manuellement une fois, exportee, puis deployee de maniere idempotente via Ansible.

## Fonctionnalites

- Cree le dossier `C:\Applications` et le partage SMB `Applications`
- Configure les permissions NTFS et SMB appropriees
- Copie le MSI GLPI Agent sur le serveur
- Importe la GPO depuis le backup (golden GPO)
- Lie la GPO a l'OU des ordinateurs

## Contenu de la golden GPO

La GPO exportee contient:

1. **Software Installation (MSI)**
   - Package MSI en mode "Attribue" (Assigned)
   - Chemin: `\\WinSRV01\Applications\GLPI-Agent-1.15-x64.msi`

2. **Preferences Registre**
   - `HKLM\SOFTWARE\GLPI-Agent\server` = URL du serveur GLPI
   - `HKLM\SOFTWARE\GLPI-Agent\tag` = Tag d'identification

3. **Option "Toujours attendre le reseau"**
   - Active pour garantir l'installation au demarrage

4. **Raccourci bureau (GPP Shortcuts)**
   - Raccourci vers `http://127.0.0.1:62354/now` pour forcer l'inventaire

## Variables

| Variable | Description | Defaut |
|----------|-------------|--------|
| `glpi_agent_version` | Version de GLPI Agent | `1.15` |
| `glpi_agent_msi_file` | Nom du fichier MSI | `GLPI-Agent-1.15-x64.msi` |
| `glpi_agent_gpo_name` | Nom de la GPO | `GLPI_Agent_Install` |
| `glpi_agent_apps_path` | Chemin du dossier Applications | `C:\Applications` |
| `glpi_agent_share_name` | Nom du partage SMB | `Applications` |
| `glpi_agent_target_ou` | OU cible pour le lien GPO | `CN=Computers,DC=gsb,DC=local` |
| `glpi_agent_domain` | Domaine AD | `gsb.local` |
| `glpi_agent_cleanup_backup` | Nettoyer le backup apres import | `true` |

## Prerequis

- Controleur de domaine Active Directory configure
- Ansible collections: `ansible.windows`

## Structure des fichiers

```
roles/GLPI_Agent_GPO/
├── defaults/main.yml
├── files/
│   ├── GLPI-Agent-1.15-x64.msi
│   └── GPO_Backup/
│       ├── manifest.xml
│       └── {GUID}/
│           ├── Backup.xml
│           ├── bkupInfo.xml
│           ├── gpreport.xml
│           └── DomainSysvol/
│               └── GPO/
│                   └── Machine/
│                       ├── Applications/
│                       ├── Preferences/
│                       │   ├── Registry/
│                       │   └── Shortcuts/
│                       └── ...
├── handlers/main.yml
├── meta/main.yml
├── tasks/main.yml
└── vars/main.yml
```

## Exemple d'utilisation

```yaml
- hosts: WinSRV01
  roles:
    - role: GLPI_Agent_GPO
```

## Comment mettre a jour la golden GPO

1. Modifier la GPO manuellement via GPMC sur le DC
2. Exporter avec PowerShell:
   ```powershell
   Backup-GPO -Name "GLPI_Agent_Install" -Path "C:\Temp\GPO_Backup"
   ```
3. Copier le contenu de `C:\Temp\GPO_Backup` vers `roles/GLPI_Agent_GPO/files/GPO_Backup/`
4. Executer le playbook Ansible pour deployer les modifications

## Licence

MIT-0
