USE glpi;
[ERROR]: Task failed: Failed to connect to the host via ssh: Host key verification failed.
Origin: <adhoc 'shell' task>

{'action': 'shell', 'args': {'_raw_params': "docker exec mariadb mysqldump -u glpi_user -p'GlpiUserPassw0rd!' [...]

    "changed": false,
    "msg": "Task failed: Failed to connect to the host via ssh: Host key verification failed.",
    "unreachable": true
}
