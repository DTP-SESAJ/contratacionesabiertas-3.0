#!/usr/bin/env bash
# ==============================================================================
# Script Automatizado de Instalación: Contrataciones Abiertas 3.0 (EDCA)
# Entorno: Ubuntu 22.04 / 24.04 / 26.04 LTS / WSL2 (Ejecutar como root)
# ==============================================================================
set -e
export DEBIAN_FRONTEND=noninteractive

# --- VARIABLES DE CONFIGURACIÓN (Edita con nano si deseas personalizar) ---
DB_NAME="edca"
DB_USER_CAPTURA="prueba_captura"
DB_PASS_CAPTURA="p4ssw0rd"
DB_USER_DASHBOARD="prueba_dashboard"
DB_PASS_DASHBOARD="p4ssw0rd"

SERVER_IP="localhost"       # Ejemplo: 34.118.167.103 o dominio
SERVER_PROTOCOL="http"      # http o https
MAPBOX_TOKEN=""             # Pega aquí tu token público de Mapbox (pk.ey...)
APP_DIR="/var/www/html/contratacionesabiertas"
REPO_PATH="github.com/datosabiertosmx/contratacionesabiertas-3.0.git"
# ------------------------------------------------------------------------------

if [ "$EUID" -ne 0 ]; then
  echo "[ERROR] Por favor ejecuta este script como usuario root (ej. sudo bash $0)"
  exit 1
fi

echo "=========================================================================="
echo " CREDENCIALES DE GITHUB PARA DESCARGAR EL REPOSITORIO"
echo "=========================================================================="
read -rp "Ingresa tu usuario de GitHub: " GITHUB_USER
read -rsp "Ingresa tu Personal Access Token (PAT) de GitHub (oculto): " GITHUB_TOKEN
echo ""

if [ -z "$GITHUB_USER" ] || [ -z "$GITHUB_TOKEN" ]; then
  echo "[ERROR] El usuario y el token de GitHub son obligatorios para continuar."
  exit 1
fi

REPO_URL="https://${GITHUB_USER}:${GITHUB_TOKEN}@${REPO_PATH}"

echo "=========================================================================="
echo " 1/9. Actualizando sistema operativo y dependencias base..."
echo "=========================================================================="
rm -f /etc/apt/sources.list.d/pgdg* /etc/apt/sources.list.d/mongodb-org* /etc/apt/sources.list.d/nodesource*
apt-get update && apt-get upgrade -y
apt-get install -y gnupg curl ca-certificates git wget lsb-release

if ! command -v wkhtmltopdf >/dev/null 2>&1; then
  echo "      -> Instalando librerías gráficas y wkhtmltopdf (0.12.6.1-2 jammy)..."
  apt-get install -y fontconfig libfreetype6 libjpeg-turbo8 libxrender1 libxext6 xfonts-75dpi xfonts-base
  rm -rf /tmp/wkhtmltox*
  curl -fSL "https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_amd64.deb" -o /tmp/wkhtmltox.deb
  dpkg-deb -x /tmp/wkhtmltox.deb /tmp/wkhtmltox_extracted
  cp -r /tmp/wkhtmltox_extracted/usr/local/* /usr/local/
  ldconfig
  rm -rf /tmp/wkhtmltox*
else
  echo "      -> wkhtmltopdf ya se encuentra instalado ($(wkhtmltopdf --version))."
fi

echo "=========================================================================="
echo " 2/9. Instalando PostgreSQL..."
echo "=========================================================================="
CODENAME=$(lsb_release -cs)
if [ "$CODENAME" != "resolute" ]; then
  wget -qO- "https://www.postgresql.org/media/keys/ACCC4CF8.asc" | tee /etc/apt/trusted.gpg.d/pgdg.asc &>/dev/null
  echo "deb [signed-by=/etc/apt/trusted.gpg.d/pgdg.asc] https://apt.postgresql.org/pub/repos/apt ${CODENAME}-pgdg main" > /etc/apt/sources.list.d/pgdg.list
  apt-get update
fi
apt-get install -y postgresql postgresql-contrib
systemctl enable --now postgresql 2>/dev/null || service postgresql start

echo "=========================================================================="
echo " 3/9. Instalando MongoDB 7.0..."
echo "=========================================================================="
curl -fsSL "https://pgp.mongodb.com/server-7.0.asc" | gpg --yes -o /usr/share/keyrings/mongodb-server-7.0.gpg --dearmor
echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" > /etc/apt/sources.list.d/mongodb-org-7.0.list
apt-get update
apt-get install -y mongodb-org
systemctl enable --now mongod 2>/dev/null || service mongod start

echo "=========================================================================="
echo " 4/9. Instalando Node.js 21, PM2 y Sequelize-CLI..."
echo "=========================================================================="
mkdir -p /etc/apt/keyrings
curl -fsSL "https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key" | gpg --yes --dearmor -o /etc/apt/keyrings/nodesource.gpg
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_21.x nodistro main" > /etc/apt/sources.list.d/nodesource.list
apt-get update
apt-get install -y nodejs
command -v npm >/dev/null 2>&1 || apt-get install -y npm
npm install -g pm2@latest sequelize-cli npm-check-updates

echo "=========================================================================="
echo " 5/9. Configurando Base de Datos y Roles en PostgreSQL..."
echo "=========================================================================="
su - postgres -c "psql -tc \"SELECT 1 FROM pg_database WHERE datname = '$DB_NAME'\" | grep -q 1 || psql -c \"CREATE DATABASE $DB_NAME;\""
su - postgres -c "psql -tc \"SELECT 1 FROM pg_roles WHERE rolname = '$DB_USER_CAPTURA'\" | grep -q 1 || psql -c \"CREATE USER $DB_USER_CAPTURA WITH PASSWORD '$DB_PASS_CAPTURA';\""
su - postgres -c "psql -tc \"SELECT 1 FROM pg_roles WHERE rolname = '$DB_USER_DASHBOARD'\" | grep -q 1 || psql -c \"CREATE USER $DB_USER_DASHBOARD WITH PASSWORD '$DB_PASS_DASHBOARD';\""
su - postgres -c "psql -c \"GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER_CAPTURA;\""
su - postgres -c "psql -c \"GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER_DASHBOARD;\""

echo "=========================================================================="
echo " 6/9. Descargando código fuente de Contrataciones Abiertas 3.0..."
echo "=========================================================================="
mkdir -p "$APP_DIR"
cd "$APP_DIR"
rm -rf contratacionesabiertas-3.0 captura dashboard

git clone "$REPO_URL" contratacionesabiertas-3.0
unset GITHUB_TOKEN REPO_URL

mv -v contratacionesabiertas-3.0/contratacionesabiertas/captura "$APP_DIR/"
mv -v contratacionesabiertas-3.0/contratacionesabiertas/dashboard "$APP_DIR/"
rm -rf contratacionesabiertas-3.0

echo "=========================================================================="
echo " 7/9. Aplicando configuraciones de conexión, IP y Mapbox..."
echo "=========================================================================="
cat << JSON_CONF > "$APP_DIR/captura/config/config.json"
{
  "development": {
    "username": "$DB_USER_CAPTURA",
    "password": "$DB_PASS_CAPTURA",
    "database": "$DB_NAME",
    "port": "5432",
    "host": "localhost",
    "dialect": "postgres",
    "operatorsAliases": 0
  },
  "test": {
    "username": "$DB_USER_CAPTURA",
    "password": "$DB_PASS_CAPTURA",
    "database": "$DB_NAME",
    "port": "5432",
    "host": "localhost",
    "dialect": "postgres",
    "operatorsAliases": 0
  },
  "production": {
    "username": "$DB_USER_CAPTURA",
    "password": "$DB_PASS_CAPTURA",
    "database": "$DB_NAME",
    "port": "5432",
    "host": "localhost",
    "dialect": "postgres",
    "operatorsAliases": 0
  }
}
JSON_CONF

sed -i "s/prueba_captura/$DB_USER_CAPTURA/g" "$APP_DIR/captura/db_conf.js"
sed -i "s/prueba_dashboard/$DB_USER_DASHBOARD/g" "$APP_DIR/captura/db_conf.js"
sed -i "s/p4ssw0rd/$DB_PASS_CAPTURA/g" "$APP_DIR/captura/db_conf.js"

sed -i "s/prueba_dashboard/$DB_USER_DASHBOARD/g" "$APP_DIR/dashboard/dash_config.js"
sed -i "s/p4ssw0rd/$DB_PASS_DASHBOARD/g" "$APP_DIR/dashboard/dash_config.js"

sed -i "s|http://localhost|$SERVER_PROTOCOL://$SERVER_IP|g" "$APP_DIR/dashboard/public/javascripts/common.js"

if [ -n "$MAPBOX_TOKEN" ]; then
  sed -i "s|process.env.MAPTOKEN || ''|process.env.MAPTOKEN || '$MAPBOX_TOKEN'|g" "$APP_DIR/captura/views/main.ejs"
  sed -i "s|process.env.MAPTOKEN || ''|process.env.MAPTOKEN || '$MAPBOX_TOKEN'|g" "$APP_DIR/dashboard/views/contract.ejs"
fi

echo "=========================================================================="
echo " 8/9. Cargando esquemas SQL, migraciones e Infraestructura Abierta..."
echo "=========================================================================="
cd "$APP_DIR/captura/sql"

sed -i "s/prueba_dashboard/$DB_USER_DASHBOARD/g" edca.sql
sed -i "s/prueba_captura/$DB_USER_CAPTURA/g" edca.sql
sed -i "s/prueba_captura/$DB_USER_CAPTURA/g" owner_public.sql
sed -i "s/prueba_dashboard/$DB_USER_DASHBOARD/g" dashboard.sql
sed -i "s/prueba_dashboard/$DB_USER_DASHBOARD/g" owner_dashboard.sql

su - postgres -c "psql -d $DB_NAME -f $APP_DIR/captura/sql/edca.sql"
su - postgres -c "psql -d $DB_NAME -f $APP_DIR/captura/sql/owner_public.sql"
su - postgres -c "psql -d $DB_NAME -f $APP_DIR/captura/sql/dashboard.sql"
su - postgres -c "psql -d $DB_NAME -f $APP_DIR/captura/sql/owner_dashboard.sql"

cd "$APP_DIR/captura"
rm -rf node_modules
npm install
npm install --save pg@latest
sequelize db:migrate
sequelize db:seed:all

su - postgres -c "psql -d $DB_NAME -f $APP_DIR/captura/sql/update_InfraestructuraAbiertav1.sql"

echo "--- Tablas en esquema public ---"
su - postgres -c "psql -P pager=off -d $DB_NAME -c '\dt public.*'"
echo "--- Tablas en esquema dashboard ---"
su - postgres -c "psql -P pager=off -d $DB_NAME -c '\dt dashboard.*'"

PG_VER=$(psql -V | awk '{print $3}' | cut -d. -f1)
PG_HBA="/etc/postgresql/$PG_VER/main/pg_hba.conf"
if [ -f "$PG_HBA" ]; then
  sed -i 's/^local\s\+all\s\+all\s\+peer/local   all             all                                     scram-sha-256/g' "$PG_HBA"
  sed -i 's/md5/scram-sha-256/g' "$PG_HBA"
  systemctl restart postgresql 2>/dev/null || service postgresql restart
fi

echo "=========================================================================="
echo " 9/9. Instalando dependencias de Dashboard e iniciando servicios PM2..."
echo "=========================================================================="
cd "$APP_DIR/dashboard"
npm install wkhtmltopdf
ncu -u
npm install
npm install express@^4.21.2

cd "$APP_DIR/captura"
chmod u+x useradm
pm2 delete captura 2>/dev/null || true
pm2 start npm --name "captura" -- start

cd "$APP_DIR/dashboard"
pm2 delete dashboard 2>/dev/null || true
pm2 start npm --name "dashboard" -- start
pm2 save

echo "=========================================================================="
echo " ¡INSTALACIÓN COMPLETADA CON ÉXITO!"
echo "=========================================================================="
echo " -> Módulo Captura:   $SERVER_PROTOCOL://$SERVER_IP:3000"
echo " -> Módulo Dashboard: $SERVER_PROTOCOL://$SERVER_IP:4000/contratacionesabiertas/contratos"
echo ""
echo " [PASO FINAL MANUAL] Crea tu usuario administrador ejecutando:"
echo " cd $APP_DIR/captura && ./useradm add administrador"
echo "=========================================================================="
