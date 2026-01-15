#!/bin/bash

set -e

# === VERIFICATION ARGUMENT ===
if [ "$1" != "full" ]; then
  apt install figlet -y
  figlet -f banner "debrouille toi"
  figlet -f banner "tie pas un tigre"
  exit 1
fi

# === CONFIG ===
CTID=110
CT_LIST=(110 113 114 115 116 120 130)
VM_LIST=(201 202)
CTNAME="terransible"
HOSTNAME="terransible"
IP="172.16.0.15"
IP_SETUP="$IP/24"
GW="172.16.0.254"
BRIDGE="vmbr0"
SSH_KEY_PATH="/root/.ssh/terransible"
LXC_TEMPLATE_FILENAME="debian-13-standard_13.1-2_amd64.tar.zst"
LXC_TEMPLATE="/var/lib/vz/template/cache/$LXC_TEMPLATE_FILENAME"
LXC_TEMPLATE_URL="http://download.proxmox.com/images/system/$LXC_TEMPLATE_FILENAME"
CHEMIN_TEMPLATE="local:vztmpl/$LXC_TEMPLATE_FILENAME"
CONTAINER_SSH_PORT=22
node=$(hostname)
PM_API="https://172.16.0.253:8006/api2/json"
TOKEN_USER="terraform-prov@pve"
TOKEN_NAME="auto-token"
USER_ROLE="TerraformProv"
TOKEN_PASSWORD="Formation13@TF"
PULSE_USER="pulse-monitor@pam"
PULSE_TOKEN_NAME="pulse-token"
GITHUB_REPO="https://github.com/Team-ITigres/Infra_GSBV2.git"
START_TIME=$(date +%s)
NOM_WINSRV_Backup="vzdump-qemu-101-2025_09_13-14_41_02.vma.zst"

# 1) Télécharger la backup du win srv 2022
echo "[+] Vérification de la backup Windows Server 2022..."
if [ ! -f /var/lib/vz/dump/$NOM_WINSRV_Backup ]; then
  echo "[+] Téléchargement de la backup Windows Server 2022..."
  wget --no-check-certificate -O /var/lib/vz/dump/$NOM_WINSRV_Backup https://m2shelper.boisloret.fr/scripts/deploy-infra-gsb/$NOM_WINSRV_Backup
else
  echo "[!] Backup déjà présente"
fi

# 2) Vérifier si le template existe et s'il utilise le même fichier de backup
NEED_RESTORE=true
if qm status 2000 &>/dev/null; then
  echo "[+] Template Windows existant détecté (VM 2000)"
  # Récupérer la description de la VM pour voir quel backup a été utilisé
  CURRENT_BACKUP=$(qm config 2000 | grep "^description:" | sed 's/description: backup_source=//')

  if [ "$CURRENT_BACKUP" = "$NOM_WINSRV_Backup" ]; then
    echo "[!] Le template utilise déjà le backup $NOM_WINSRV_Backup, pas besoin de restaurer"
    NEED_RESTORE=false
  else
    echo "[!] Le template utilise un backup différent ($CURRENT_BACKUP vs $NOM_WINSRV_Backup)"
    echo "[+] Suppression du template existant..."
    qm destroy 2000 --purge
  fi
fi

# Vérifier s'il y a un conteneur LXC avec l'ID 2000
if pct status 2000 &>/dev/null; then
  echo "[+] Conteneur LXC 2000 détecté, suppression..."
  pct destroy 2000
fi

# 3) Restaurer uniquement si nécessaire
if [ "$NEED_RESTORE" = true ]; then
  echo "[+] Restauration du template Windows depuis $NOM_WINSRV_Backup..."
  qmrestore /var/lib/vz/dump/$NOM_WINSRV_Backup 2000 --storage local-lvm --unique 1
  qm set 2000 --name "WinTemplate"
  qm set 2000 --description "backup_source=$NOM_WINSRV_Backup"

  echo "[+] Marquage en template..."
  qm template 2000
  echo "[+] Template Windows créé avec succès"
else
  echo "[+] Template Windows déjà à jour"
fi

# === 0. Prérequis ===
echo "[+] Vérification/installation de jq..."
if ! command -v jq >/dev/null 2>&1; then
  apt update && apt install -y jq
fi

echo "[+] Vérification et suppression du storage PBS si présent..."
if pvesm status | grep -q "pbs-backup"; then
  echo "⚠️ Storage PBS 'pbs-backup' détecté. Suppression..."
  pvesm remove pbs-backup
  echo "[+] Storage PBS supprimé"
else
  echo "[!] Aucun storage PBS 'pbs-backup' trouvé"
fi

echo "[+] Vérification et suppression des conteneurs LXC si présents..."
for CT in "${CT_LIST[@]}"; do
  if pct status "$CT" &>/dev/null; then
    echo "⚠️ Conteneur $CT détecté. Suppression..."
    pct stop "$CT" 2>/dev/null || true
    pct destroy "$CT"
  fi
done

echo "[+] Vérification et suppression des VMs si présentes..."
for VM in "${VM_LIST[@]}"; do
  if qm status "$VM" &>/dev/null; then
    echo "⚠️ VM $VM détectée. Suppression..."
    qm stop "$VM" 2>/dev/null || true
    qm destroy "$VM" --purge
  fi
done

# === 1. Télécharger l'ISO LXC ===
# Lxc Debian 13
echo "[+] Vérification de l'image Debian 13 LXC..."
if [ ! -f "$LXC_TEMPLATE" ]; then
  echo "[+] Téléchargement de l'image LXC $LXC_TEMPLATE_FILENAME..."
  wget -O "$LXC_TEMPLATE" "$LXC_TEMPLATE_URL"
fi

# === 2. Génération de la paire de clés SSH ===
echo "[+] Génération de la paire de clés SSH pour le conteneur..."
if [ ! -f "$SSH_KEY_PATH" ]; then
  echo "[+] Création de la paire de clés SSH..."
  ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N ""
else
  echo "[!] Clé SSH déjà existante"
fi

echo "[+] Lecture de la clé publique..."
PUB_KEY=$(cat "${SSH_KEY_PATH}.pub")

# === 3. Création des bridges réseau ===
echo "[+] Vérification et création des bridges réseau..."

# Vérifier si vmbr2 existe déjà
if ! ip link show vmbr2 &>/dev/null; then
  echo "[+] Création du bridge vmbr2..."

  # Vérifier si la configuration existe déjà dans le fichier
  if ! grep -q "^auto vmbr2" /etc/network/interfaces; then
    cat >> /etc/network/interfaces <<'EOF'

auto vmbr2
iface vmbr2 inet static
        address 10.10.0.6/28
        bridge-ports none
        bridge-stp off
        bridge-fd 0
        bridge-vlan-aware yes
        bridge-vids 2-4094
EOF
    echo "[+] Configuration vmbr2 ajoutée à /etc/network/interfaces"
  else
    echo "[!] Configuration vmbr2 déjà présente dans /etc/network/interfaces"
  fi
else
  echo "[!] Le bridge vmbr2 existe déjà"
fi

# Recharger les interfaces réseau
echo "[+] Rechargement des interfaces réseau..."
if command -v ifreload &>/dev/null; then
  ifreload -a
else
  echo "[!] ifreload non disponible, tentative avec ifup..."
  ifup vmbr2 2>/dev/null || true
fi

# === 4. Création du conteneur LXC ===
if pct status 110 &>/dev/null; then
  echo "[!] Le conteneur 110 existe déjà. Destruction en cours..."
  pct stop 110
  pct destroy 110
fi

echo "[+] Création du conteneur LXC '$CTNAME' avec IP $IP_SETUP..."
pct destroy $CTID 2>/dev/null || true

echo "[+] Exécution de la commande pct create..."
pct create $CTID "$CHEMIN_TEMPLATE" \
  --hostname $HOSTNAME \
  --cores 4 \
  --memory 4096 \
  --net0 name=eth0,bridge=$BRIDGE,ip=$IP_SETUP,gw=$GW \
  --net1 name=eth1,bridge=vmbr2,ip=10.10.0.10/28,gw=10.10.0.1 \
  --storage local-lvm \
  --rootfs local-lvm:8 \
  --features nesting=1 \
  --password Formation13@ \
  --unprivileged 0

echo "[+] Démarrage du conteneur..."
pct start $CTID


# === 4. Attente que le conteneur soit up ===
echo "[+] Attente du démarrage du conteneur..."
while ! ping -c 1 -W 1 "$IP" > /dev/null 2>&1; do
    sleep 1
done

# === 5. Injection de la clé SSH ===
echo "[+] Injection de la clé SSH dans le conteneur..."
pct exec $CTID -- mkdir -p /root/.ssh
pct exec $CTID -- bash -c "echo '$PUB_KEY' > /root/.ssh/authorized_keys"
pct exec $CTID -- chmod 600 /root/.ssh/authorized_keys

# === 6. Authentification Proxmox et création du token ===
echo "[+] Configuration du rôle et de l'utilisateur Terraform sur Proxmox..."

# Vérification/création du rôle TerraformProv
if ! pveum role list | grep -qw "$USER_ROLE"; then
  echo "[+] Création du rôle $USER_ROLE avec les privilèges nécessaires..."
  pveum role add "$USER_ROLE" -privs "Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit Pool.Allocate Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Monitor VM.Migrate VM.PowerMgmt SDN.Use"
  echo "[+] Rôle $USER_ROLE créé avec succès."
else
  echo "[!] Le rôle $USER_ROLE existe déjà."
fi

# Suppression de l'utilisateur s'il existe déjà
if pveum user list | grep -q "$TOKEN_USER"; then
  echo "[!] L'utilisateur $TOKEN_USER existe déjà. Suppression en cours..."
  pveum user delete "$TOKEN_USER"
fi

# Création de l'utilisateur avec mot de passe
echo "[+] Création de l'utilisateur $TOKEN_USER..."
pveum user add "$TOKEN_USER" --password "$TOKEN_PASSWORD"
echo "[+] Utilisateur $TOKEN_USER créé avec succès."

# Attribution du rôle sur la racine /
echo "[+] Attribution du rôle $USER_ROLE à $TOKEN_USER sur /"
pveum aclmod / -user "$TOKEN_USER" -role "$USER_ROLE"

echo "[+] Création du token $TOKEN_NAME..."
TOKEN_OUTPUT=$(pveum user token add "$TOKEN_USER" "$TOKEN_NAME" --privsep 0 --output-format json 2>/dev/null)

if [ -z "$TOKEN_OUTPUT" ]; then
  echo "[!] Le token existe probablement déjà. Supprime-le avec :"
  echo "    pveum user token delete \"$TOKEN_USER\" \"$TOKEN_NAME\""
  exit 1
fi

export TF_TOKEN_ID="$TOKEN_USER!$TOKEN_NAME"
export TF_TOKEN_SECRET=$(echo "$TOKEN_OUTPUT" | jq -r '.value')

echo "[+] Token créé avec succès: $TF_TOKEN_ID"

# === 7. Création de l'utilisateur et du token pour Pulse ===
echo "[+] Configuration de l'utilisateur Pulse pour le monitoring Proxmox..."

# Suppression de l'utilisateur Pulse s'il existe déjà
if pveum user list | grep -q "$PULSE_USER"; then
  echo "[!] L'utilisateur $PULSE_USER existe déjà. Suppression en cours..."
  pveum user delete "$PULSE_USER"
fi

# Création de l'utilisateur Pulse
echo "[+] Création de l'utilisateur $PULSE_USER..."
pveum user add "$PULSE_USER" --comment "Pulse monitoring service"

# Création du token Pulse
echo "[+] Création du token $PULSE_TOKEN_NAME pour Pulse..."
PULSE_TOKEN_OUTPUT=$(pveum user token add "$PULSE_USER" "$PULSE_TOKEN_NAME" --privsep 0 --output-format json 2>/dev/null)

if [ -z "$PULSE_TOKEN_OUTPUT" ]; then
  echo "[!] Échec de la création du token Pulse"
  exit 1
fi

export PULSE_TOKEN_ID="$PULSE_USER!$PULSE_TOKEN_NAME"
export PULSE_TOKEN_SECRET=$(echo "$PULSE_TOKEN_OUTPUT" | jq -r '.value')

# Attribution du rôle PVEAuditor
echo "[+] Attribution du rôle PVEAuditor à $PULSE_USER..."
pveum aclmod / -user "$PULSE_USER" -role PVEAuditor

# Vérification et création du rôle PulseMonitor avec VM.Monitor
echo "[+] Vérification du privilège VM.Monitor..."
if pveum role list 2>/dev/null | grep -q "VM.Monitor" || pveum role add TestMonitor -privs VM.Monitor 2>/dev/null; then
  pveum role delete TestMonitor 2>/dev/null || true
  pveum role delete PulseMonitor 2>/dev/null || true
  pveum role add PulseMonitor -privs VM.Monitor
  pveum aclmod / -user "$PULSE_USER" -role PulseMonitor
  echo "[+] Rôle PulseMonitor créé et attribué"
fi

echo "[+] Token Pulse créé avec succès: $PULSE_TOKEN_ID"

# === 8. Connexion au conteneur pour setup ===
echo "[+] Connexion au conteneur pour déploiement Terraform + Ansible..."
echo "[+] Nettoyage du fichier known_hosts..."
rm -f ~/.ssh/known_hosts

IP_ADDR="${IP%%/*}"

echo "[+] Vérification que le conteneur est bien en ligne..."
until ping -c1 -W1 "$IP_ADDR" >/dev/null 2>&1; do
  echo "⏳ En attente que $IP_ADDR soit en ligne..."
  sleep 2
done

echo "[+] Conteneur en ligne, connexion SSH en cours..."
ssh -T -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" root@"$IP" <<EOF

#!/bin/bash
set -e

DISTRO="trixie"
GITHUB_REPO="$GITHUB_REPO"
node="$node"

echo "[+] Mise à jour des paquets..."
apt update

echo "[+] Installation des dépendances pour Docker et tmux..."
apt install -y ca-certificates curl gnupg tmux

echo "[+] Ajout de la clé GPG Docker..."
curl -fsSL https://download.docker.com/linux/debian/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

chmod a+r /etc/apt/keyrings/docker.gpg

echo "[+] Ajout du dépôt Docker..."
echo \
"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/debian \
\$(. /etc/os-release && echo \"\$VERSION_CODENAME\") stable" \
| tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "[+] Mise à jour avec le nouveau dépôt Docker..."
apt update

echo "[+] Installation de Docker et ses composants..."
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "[+] Clonage du dépôt Git..."
git clone "\$GITHUB_REPO" /Infra_GSBV2 || { echo "❌ Clone Git échoué"; exit 1; }

echo "[+] Écriture du fichier .env_secret pour Terraform et Pulse..."
cat <<EOT > /root/.env_secret
TF_VAR_proxmox_api_url=$PM_API
TF_VAR_proxmox_api_token_id=$TOKEN_USER!$TOKEN_NAME
TF_VAR_proxmox_api_token=$TF_TOKEN_SECRET
TF_VAR_target_node=$node
TF_VAR_chemin_cttemplate=$CHEMIN_TEMPLATE
PULSE_PROXMOX_URL=$PM_API
PULSE_PROXMOX_TOKEN_ID=$PULSE_USER!$PULSE_TOKEN_NAME
PULSE_PROXMOX_TOKEN=$PULSE_TOKEN_SECRET
PULSE_PROXMOX_NODE=$node
EOT

echo "[+] Vérification du contenu du fichier .env_secret..."
cat /root/.env_secret

echo "[+] Téléchargement de l'image adminbox:latest depuis m2shelper..."
wget --no-check-certificate --progress=bar:force:noscroll https://m2shelper.boisloret.fr/scripts/deploy-infra-gsb/adminbox-latest.tar -O /tmp/adminbox.tar

echo "[+] Chargement de l'image Docker..."
docker load -i /tmp/adminbox.tar

echo "[+] Nettoyage du fichier temporaire..."
rm -f /tmp/adminbox.tar

echo "[+] Création de la fonction terransible..."
cat >> /root/.bashrc <<FUNCEOF
terransible() {
  if [ \\\$# -eq 0 ]; then
    docker run --rm -it --network="host" \\
      -v /root/etc/ansible:/root/etc/ansible \\
      -v "\\\$PWD":/work \\
      --env-file /root/.env_secret \\
      adminbox:latest
  else
    docker run --rm --network="host" \\
      -v /root/etc/ansible:/root/etc/ansible \\
      -v "\\\$PWD":/work \\
      --env-file /root/.env_secret \\
      adminbox:latest "\\\$@"
  fi
}
FUNCEOF

echo "[+] Chargement de la fonction terransible..."
source /root/.bashrc

echo "[+] Initialisation de Terraform..."
cd /Infra_GSBV2/Terraform
terransible terraform init

echo "[+] Application de la configuration Terraform..."
terransible terraform apply -auto-approve

echo "[+] Attente que les machines 172.16.0.2 et 172.16.0.1 soient en ligne..."
while ! ping -c 1 -W 1 172.16.0.2 > /dev/null 2>&1; do
  echo "⏳ En attente de 172.16.0.2..."
  sleep 1
done
echo "[+] Machine 172.16.0.2 en ligne"

while ! ping -c 1 -W 1 172.16.0.1 > /dev/null 2>&1; do
  echo "⏳ En attente de 172.16.0.1..."
  sleep 1
done
echo "[+] Machine 172.16.0.1 en ligne"

echo "[+] Installation des rôles Ansible..."
cd /Infra_GSBV2/Ansible
terransible ansible-galaxy install -r requirements.yml --force

EOF

echo "[+] Lancement des playbooks Ansible en mode tmux..."

# Connexion SSH avec terminal et lancement automatique de tmux
# Note: tmux doit être lancé AVANT terransible, car terransible est un conteneur Docker
ssh -t -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" root@"$IP" \
  "cd /Infra_GSBV2/Ansible && tmux new-session 'terransible ansible-playbook Install_Linuxs.yml' \\; split-window -h 'terransible ansible-playbook Install_Windows.yml'"

echo ""
echo "✅ Déploiement complet terminé avec succès."

DURATION=$(($(date +%s) - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))

if [ $MINUTES -gt 0 ]; then
  echo "Temps de préparation: ${MINUTES} minute(s) ${SECONDS} seconde(s) (${DURATION} secondes au total)"
else
  echo "Temps de préparation: ${SECONDS} seconde(s)"
fi