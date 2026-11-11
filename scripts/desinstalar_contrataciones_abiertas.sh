#!/usr/bin/env bash
# ==============================================================================
# Script de Desinstalación Completa
# Herramienta Tecnológica de Contrataciones Abiertas (EDCA)
# ==============================================================================
# ADVERTENCIA: Este script detiene servicios, elimina bases de datos, borra
# el código fuente y opcionalmente desinstala PostgreSQL, MongoDB, Node.js y NGINX.
# Ejecutar como usuario root.
# ==============================================================================

set -e

# ------------------------------------------------------------------------------
# VARIABLES DE CONFIGURACIÓN (Deben coincidir con las usadas en la instalación)
# ------------------------------------------------------------------------------
DB_NAME="edca"
DB_USER_CAPTURA="prueba_captura"
DB_USER_DASHBOARD="prueba_dashboard"
MONGO_DB_NAME="passport"
APP_DIR="/var/www/html/contratacionesabiertas"
NGINX_SITE_NAME="contratacionesabiertas"

# Cambiar a "true" si también deseas desinstalar los motores y paquetes del sistema
REMOVE_SYSTEM_PACKAGES="true"

# ------------------------------------------------------------------------------
# VERIFICACIÓN DE PRIVILEGIOS Y CONFIRMACIÓN
# ------------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
  echo "[ERROR] Este script debe ejecutarse como usuario root."
  exit 1
fi

echo "=========================================================================="
echo "  DESINSTALACIÓN DE LA HERRAMIENTA DE CONTRATACIONES ABIERTAS"
echo "=========================================================================="
echo "Se realizarán las siguientes acciones:"
echo "  1. Detener y eliminar procesos de PM2 (captura y dashboard)."
echo "  2. Eliminar la base de datos PostgreSQL '$DB_NAME' y sus roles."
echo "  3. Eliminar la base de datos MongoDB '$MONGO_DB_NAME'."
echo "  4. Eliminar el directorio de la aplicación: $APP_DIR"
echo "  5. Eliminar configuración de NGINX ($NGINX_SITE_NAME) si existe."
if [ "$REMOVE_SYSTEM_PACKAGES" = "true" ]; then
  echo "  6. [ACTIVADO] Desinstalar PostgreSQL 17, MongoDB 7, Node.js, PM2 y wkhtmltopdf."
else
  echo "  6. [OMITIDO] Se conservarán PostgreSQL, MongoDB y Node.js instalados."
fi
echo "=========================================================================="
read -p "¿Deseas continuar con la desinstalación? Escribe 'SI' para confirmar: " CONFIRM

if [ "$CONFIRM" != "SI" ]; then
  echo "[CANCELADO] No se realizó ningún cambio en el sistema."
  exit 0
fi

# ------------------------------------------------------------------------------
# PASO 1: DETENER Y ELIMINAR SERVICIOS EN PM2
# ------------------------------------------------------------------------------
echo "[1/6] Deteniendo y eliminando procesos de PM2..."
if command -v pm2 >/dev/null 2>&1; then
  pm2 delete captura >/dev/null 2>&1 || true
  pm2 delete dashboard >/dev/null 2>&1 || true
  pm2 save --force >/dev/null 2>&1 || true
  echo "      -> Procesos PM2 eliminados."
else
  echo "      -> PM2 no está instalado, omitiendo."
fi

# ------------------------------------------------------------------------------
# PASO 2: ELIMINAR BASE DE DATOS Y ROLES EN POSTGRESQL
# ------------------------------------------------------------------------------
echo "[2/6] Eliminando base de datos y usuarios en PostgreSQL..."
if command -v psql >/dev/null 2>&1 && systemctl is-active --quiet postgresql; then
  psql -U postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$DB_NAME';" >/dev/null 2>&1 || true
  psql -U postgres -c "DROP DATABASE IF EXISTS $DB_NAME;" >/dev/null 2>&1 || true
  psql -U postgres -c "DROP ROLE IF EXISTS $DB_USER_CAPTURA;" >/dev/null 2>&1 || true
  psql -U postgres -c "DROP ROLE IF EXISTS $DB_USER_DASHBOARD;" >/dev/null 2>&1 || true
  echo "      -> Base de datos '$DB_NAME' y roles eliminados."
else
  echo "      -> PostgreSQL no está activo o instalado, omitiendo."
fi

# ------------------------------------------------------------------------------
# PASO 3: ELIMINAR BASE DE DATOS EN MONGODB
# ------------------------------------------------------------------------------
echo "[3/6] Eliminando base de datos en MongoDB..."
if command -v mongosh >/dev/null 2>&1 && systemctl is-active --quiet mongod; then
  mongosh "$MONGO_DB_NAME" --quiet --eval "db.dropDatabase()" >/dev/null 2>&1 || true
  echo "      -> Base de datos MongoDB '$MONGO_DB_NAME' eliminada."
elif command -v mongo >/dev/null 2>&1 && systemctl is-active --quiet mongod; then
  mongo "$MONGO_DB_NAME" --quiet --eval "db.dropDatabase()" >/dev/null 2>&1 || true
  echo "      -> Base de datos MongoDB '$MONGO_DB_NAME' eliminada."
else
  echo "      -> MongoDB no está activo o instalado, omitiendo."
fi

# ------------------------------------------------------------------------------
# PASO 4: ELIMINAR CÓDIGO FUENTE Y DIRECTORIOS DE LA APLICACIÓN
# ------------------------------------------------------------------------------
echo "[4/6] Eliminando archivos de la aplicación..."
if [ -d "$APP_DIR" ]; then
  rm -rf "$APP_DIR"
  echo "      -> Directorio $APP_DIR eliminado."
else
  echo "      -> El directorio $APP_DIR no existe, omitiendo."
fi

# ------------------------------------------------------------------------------
# PASO 5: ELIMINAR CONFIGURACIÓN DE NGINX (SI EXISTE)
# ------------------------------------------------------------------------------
echo "[5/6] Limpiando configuración de NGINX..."
if [ -f "/etc/nginx/sites-enabled/$NGINX_SITE_NAME" ] || [ -f "/etc/nginx/sites-available/$NGINX_SITE_NAME" ]; then
  rm -f "/etc/nginx/sites-enabled/$NGINX_SITE_NAME"
  rm -f "/etc/nginx/sites-available/$NGINX_SITE_NAME"
  if command -v nginx >/dev/null 2>&1; then
    nginx -t >/dev/null 2>&1 && systemctl reload nginx || true
  fi
  echo "      -> VirtualHost de NGINX eliminado."
else
  echo "      -> No se encontró configuración de NGINX para la herramienta."
fi

# ------------------------------------------------------------------------------
# PASO 6: DESINSTALACIÓN OPCIONAL DE PAQUETES DEL SISTEMA
# ------------------------------------------------------------------------------
if [ "$REMOVE_SYSTEM_PACKAGES" = "true" ]; then
  echo "[6/6] Iniciando desinstalación de paquetes base del sistema..."
  export DEBIAN_FRONTEND=noninteractive

  echo "      [6.1] Desinstalando herramientas globales de npm (pm2, sequelize-cli, ncu)..."
  npm uninstall -g pm2 sequelize-cli npm-check-updates >/dev/null 2>&1 || true
  rm -rf /root/.pm2 /root/.npm /usr/local/bin/pm2* /usr/local/bin/sequelize* /usr/local/bin/ncu /usr/local/lib/node_modules

  echo "      [6.2] Deteniendo y eliminando PostgreSQL y sus datos..."
  systemctl stop postgresql >/dev/null 2>&1 || service postgresql stop >/dev/null 2>&1 || true
  apt-get purge -y "postgresql*" >/dev/null 2>&1 || true
  rm -rf /etc/postgresql /var/lib/postgresql /var/log/postgresql /etc/apt/sources.list.d/pgdg.list /etc/apt/trusted.gpg.d/pgdg.asc

  echo "      [6.3] Deteniendo y eliminando MongoDB y sus datos..."
  systemctl stop mongod >/dev/null 2>&1 || service mongod stop >/dev/null 2>&1 || true
  apt-get purge -y "mongodb-org*" >/dev/null 2>&1 || true
  rm -rf /var/log/mongodb /var/lib/mongodb /etc/mongod.conf /etc/apt/sources.list.d/mongodb-org-7.0.list /usr/share/keyrings/mongodb-server-7.0.gpg

  echo "      [6.4] Eliminando Node.js y wkhtmltopdf..."
  apt-get purge -y nodejs wkhtmltopdf wkhtmltox >/dev/null 2>&1 || true
  rm -rf /etc/apt/sources.list.d/nodesource.list /etc/apt/keyrings/nodesource.gpg

  echo "      [6.5] Limpiando dependencias huérfanas y caché de paquetes..."
  apt-get autoremove -y >/dev/null 2>&1 || true
  apt-get autoclean -y >/dev/null 2>&1 || true
  hash -r 2>/dev/null || true

  echo "      -> Paquetes base, datos y repositorios eliminados por completo."
else
  echo "[6/6] Paquetes base conservados (REMOVE_SYSTEM_PACKAGES=false)."
fi

echo "=========================================================================="
echo "  DESINSTALACIÓN COMPLETADA EXITOSAMENTE"
echo "=========================================================================="
