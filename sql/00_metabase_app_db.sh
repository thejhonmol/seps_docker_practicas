#!/bin/bash
set -e
# Este script se ejecuta solo al inicializar un volumen PostgreSQL nuevo.
# Crea una base de aplicación separada para Metabase y evita colisiones
# con los esquemas analíticos y las tablas internas de n8n.
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  -v mb_user="$METABASE_APP_USER" \
  -v mb_pass="$METABASE_APP_PASSWORD" \
  -v mb_db="$METABASE_APP_DB" <<'EOSQL'
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'mb_user', :'mb_pass') \gexec
SELECT format('CREATE DATABASE %I OWNER %I', :'mb_db', :'mb_user') \gexec
EOSQL
