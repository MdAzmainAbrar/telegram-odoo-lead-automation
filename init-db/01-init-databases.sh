#!/bin/bash
# Runs automatically the FIRST time the postgres container starts
# (docker-entrypoint-initdb.d scripts only run on an empty data volume).
# Creates a dedicated database for n8n and one for the WhatsApp leads app.
# Odoo creates its own database(s) later via its web-based database manager.

set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "postgres" <<-EOSQL
    CREATE DATABASE n8n;
    CREATE DATABASE whatsapp_leads;
EOSQL
