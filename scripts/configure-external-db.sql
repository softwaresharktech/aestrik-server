-- Run once against the DataHub MariaDB service (NOT the Asterisk server itself — see
-- documentation/09-datahub-production-deployment.md, Step 1).
--
-- Usage:
--   mysql -h <mariadb-private-ip> -u root -p < configure-external-db.sql
--
-- Before running, replace:
--   __ASTERISK_SERVER_PRIVATE_IP__  with the Asterisk app server's private IP (e.g. 10.1.2.10)
--   __FREEPBXUSER_PASSWORD__        with a strong generated password
--
-- Unlike local-dev/init.sql (which grants 'freepbxuser'@'%' for convenience in a
-- localhost-only dev container), this scopes the grant to exactly the Asterisk
-- server's IP — nothing else on the network can authenticate as this user even if
-- the password leaked, per documentation/06-security-hardening.md.

CREATE DATABASE IF NOT EXISTS asterisk;
CREATE DATABASE IF NOT EXISTS asteriskcdrdb;

CREATE USER IF NOT EXISTS 'freepbxuser'@'__ASTERISK_SERVER_PRIVATE_IP__'
  IDENTIFIED BY '__FREEPBXUSER_PASSWORD__';

GRANT ALL PRIVILEGES ON `asterisk`.* TO 'freepbxuser'@'__ASTERISK_SERVER_PRIVATE_IP__';
GRANT ALL PRIVILEGES ON `asteriskcdrdb`.* TO 'freepbxuser'@'__ASTERISK_SERVER_PRIVATE_IP__';

FLUSH PRIVILEGES;
