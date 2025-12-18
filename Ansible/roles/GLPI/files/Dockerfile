FROM glpi/glpi:11.0.2

# Installer ldap-utils pour le diagnostic
RUN apt-get update && \
    apt-get install -y ldap-utils && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
