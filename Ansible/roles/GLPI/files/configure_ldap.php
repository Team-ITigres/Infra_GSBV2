<?php
/**
 * Script de configuration LDAP pour GLPI
 * Ce script utilise l'API interne de GLPI pour configurer correctement le LDAP
 */

// Charger GLPI (compatible avec GLPI 10 et 11)
define('GLPI_ROOT', '/var/www/html');

// Essayer les différents chemins d'inclusion selon la version de GLPI
if (file_exists(GLPI_ROOT . '/vendor/autoload.php')) {
    // GLPI 10+
    require_once GLPI_ROOT . '/vendor/autoload.php';
    require_once GLPI_ROOT . '/inc/based_config.php';
    require_once GLPI_ROOT . '/inc/db.function.php';

    // Initialiser la session
    Session::setPath();
    Session::start();

    // Charger la DB
    include_once GLPI_CONFIG_DIR . '/config_db.php';

    $DB = new DB();
    if (!$DB->connected) {
        die("Erreur: Impossible de se connecter à la base de données\n");
    }
} elseif (file_exists(GLPI_ROOT . '/inc/includes.php')) {
    // GLPI 9.x
    include (GLPI_ROOT . "/inc/includes.php");
} else {
    die("Erreur: Impossible de trouver les fichiers d'inclusion de GLPI\n");
}

// Paramètres LDAP passés en arguments
$ldap_config = [
    'name'                => $argv[1] ?? 'Active Directory GSB',
    'host'                => $argv[2] ?? '172.16.0.1',
    'port'                => $argv[3] ?? 389,
    'basedn'              => $argv[4] ?? 'DC=gsb,DC=local',
    'rootdn'              => $argv[5] ?? 'CN=glpi_bind,OU=Comptes_Services,DC=gsb,DC=local',
    'rootdn_passwd'       => $argv[6] ?? 'Formation13@',
    'login_field'         => $argv[7] ?? 'samaccountname',
    'sync_field'          => $argv[8] ?? 'objectguid',
    'condition'           => $argv[9] ?? '(&(objectClass=user)(objectCategory=person)(!(userAccountControl:1.2.840.113556.1.4.803:=2)))',
    'use_tls'             => 0,
    'use_bind'            => 1,
    'use_dn'              => 1,
    'email1_field'        => $argv[10] ?? 'mail',
    'realname_field'      => $argv[11] ?? 'sn',
    'firstname_field'     => $argv[12] ?? 'givenname',
    'phone_field'         => $argv[13] ?? 'telephonenumber',
    'title_field'         => $argv[14] ?? 'title',
    'group_field'         => $argv[15] ?? 'memberof',
    'group_condition'     => $argv[16] ?? '(objectClass=group)',
    'group_search_type'   => 0,
    'can_support_pagesize'=> 1,
    'pagesize'            => 100,
    'ldap_maxlimit'       => 1000,
    'is_active'           => 1,
    'is_default'          => 1,
];

// Créer ou mettre à jour la configuration LDAP
$authldap = new AuthLDAP();

// Chercher si une configuration existe déjà
$existing = $authldap->find(['name' => $ldap_config['name']]);

if (count($existing) > 0) {
    // Mettre à jour
    $id = array_key_first($existing);
    $ldap_config['id'] = $id;
    if ($authldap->update($ldap_config)) {
        echo "Configuration LDAP mise à jour avec succès (ID: $id)\n";
        exit(0);
    } else {
        echo "Erreur lors de la mise à jour de la configuration LDAP\n";
        exit(1);
    }
} else {
    // Créer
    $id = $authldap->add($ldap_config);
    if ($id) {
        echo "Configuration LDAP créée avec succès (ID: $id)\n";
        exit(0);
    } else {
        echo "Erreur lors de la création de la configuration LDAP\n";
        exit(1);
    }
}
