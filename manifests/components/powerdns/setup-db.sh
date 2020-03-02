#!/usr/bin/env sh

set -o errexit
set -o nounset

# wait for mariadb-galera server
mysqladmin status -h${POWERDNS_DB_HOST} -P${POWERDNS_DB_PORT} -u${POWERDNS_DB_ROOT_USER} -p${POWERDNS_DN_ROOT_PASSWORD}

echo "Creating database for PowerDNS..."
mysql -h${POWERDNS_DB_HOST} -P${POWERDNS_DB_PORT} -u${POWERDNS_DB_ROOT_USER} -p${POWERDNS_DN_ROOT_PASSWORD} -e "CREATE DATABASE IF NOT EXISTS \`${POWERDNS_DB_DATABASE}\` DEFAULT CHARACTER SET \`utf8\` COLLATE \`utf8_unicode_ci\`;"

echo "Creating user for PowerDNS database..."
mysql -h${POWERDNS_DB_HOST} -P${POWERDNS_DB_PORT} -u${POWERDNS_DB_ROOT_USER} -p${POWERDNS_DN_ROOT_PASSWORD} -e "CREATE USER IF NOT EXISTS '${POWERDNS_DB_USER}'@'%.%.%.%';"
mysql -h${POWERDNS_DB_HOST} -P${POWERDNS_DB_PORT} -u${POWERDNS_DB_ROOT_USER} -p${POWERDNS_DN_ROOT_PASSWORD} -e "GRANT ALL PRIVILEGES ON \`${POWERDNS_DB_DATABASE}\`.* TO '$POWERDNS_DB_USER'@'%.%.%.%' IDENTIFIED BY '$POWERDNS_DB_PASSWORD';"

if [ $(mysql -h${POWERDNS_DB_HOST} -P${POWERDNS_DB_PORT} -u${POWERDNS_DB_USER} -p${POWERDNS_DB_PASSWORD} -Nsre "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = \"${POWERDNS_DB_DATABASE}\";") -le 1 ]; then
  echo "Loading PowerDNS database schema..."
  cat /schema/schema.sql | mysql -h${POWERDNS_DB_HOST} -P${POWERDNS_DB_PORT} -u${POWERDNS_DB_USER} -p${POWERDNS_DB_PASSWORD} ${POWERDNS_DB_DATABASE}
fi
