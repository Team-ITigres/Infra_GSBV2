FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV ANSIBLE_VENV=/opt/venvs/ansible
ENV PATH="$ANSIBLE_VENV/bin:/usr/local/bin:$PATH"

# === Paquets de base ===
RUN apt update \
 && apt install -y --no-install-recommends \
    ca-certificates \
    curl \
    wget \
    gnupg \
    git \
    openssh-client \
    jq \
    unzip \
    less \
    vim \
    tmux \
    python3 \
    python3-pip \
    python3-venv \
    proxmoxer \
    requests
 && rm -rf /var/lib/apt/lists/*

# === Ansible dans un venv dédié ===
RUN mkdir -p /opt/venvs \
 && python3 -m venv $ANSIBLE_VENV \
 && $ANSIBLE_VENV/bin/pip install --upgrade pip \
 && $ANSIBLE_VENV/bin/pip install \
    ansible \
    "pywinrm[credssp]" \
    requests-ntlm \
    paramiko \
    proxmoxer \
    requests

# === Terraform (binaire officiel, version pinée) ===
ARG TERRAFORM_VERSION=1.7.5

RUN curl -fsSL https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip \
    -o terraform.zip \
 && unzip terraform.zip \
 && mv terraform /usr/local/bin/terraform \
 && rm terraform.zip

# === Bitwarden CLI (binaire officiel) ===
RUN curl -fsSL "https://vault.bitwarden.com/download/?app=cli&platform=linux" \
    -o bw.zip \
 && unzip bw.zip \
 && chmod +x bw \
 && mv bw /usr/local/bin/bw \
 && rm bw.zip

# === Répertoires de travail ===
RUN mkdir -p /work /root/.ssh

# === Alias pour ansible-playbook ===
RUN echo 'alias apl="ansible-playbook Install_Linuxs.yml"' >> /root/.bashrc
RUN echo 'alias apw="ansible-playbook Install_Windows.yml"' >> /root/.bashrc

WORKDIR /work

CMD ["bash"]