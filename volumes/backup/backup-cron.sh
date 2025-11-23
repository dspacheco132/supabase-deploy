#!/bin/sh

# Backup script for cron
# Uses environment variables for database connection

# Get database password from environment
DB_PASSWORD="${POSTGRES_PASSWORD:-}"

if [ -z "$DB_PASSWORD" ]; then
    echo "[ERROR] POSTGRES_PASSWORD environment variable is not set"
    exit 1
fi

# Build database URL
DB_HOST="${POSTGRES_HOST:-supabase-db}"
DB_PORT="${POSTGRES_PORT:-5432}"
DB_NAME="${POSTGRES_DB:-postgres}"
DB_USER="${POSTGRES_USER:-postgres}"

DB_URL="postgresql://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}"

# Execute backup
cd /app && sh backup.sh "$DB_URL"

