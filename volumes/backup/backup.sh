#!/bin/bash

# Supabase database backup script
# This script creates dumps of roles, schema and data from the database

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to resolve Docker container hostname to IP
# This is needed because Supabase CLI runs pg_dumpall in a temporary container
# that doesn't have access to Docker's internal DNS
resolve_container_ip() {
    local url="$1"
    local hostname=""
    
    # Extract hostname from URL (format: postgresql://user:pass@hostname:port/db)
    # Using sed for sh compatibility - extract everything between @ and :
    hostname=$(echo "$url" | sed -n 's/.*@\([^:]*\):.*/\1/p')
    
    if [ -z "$hostname" ]; then
        echo "$url"
        return
    fi
    
    # Check if hostname is an IP address (basic check)
    if echo "$hostname" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'; then
        echo "$url"
        return
    fi
    
    # Skip resolution for localhost variants
    case "$hostname" in
        localhost|127.0.0.1|host.docker.internal)
            echo "$url"
            return
            ;;
    esac
    
    # Try to resolve container IP
    if command -v docker >/dev/null 2>&1; then
        local container_ip=""
        # Try container name first, then with supabase- prefix
        container_ip=$(docker inspect "$hostname" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null || echo "")
        if [ -z "$container_ip" ]; then
            container_ip=$(docker inspect "supabase-$hostname" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null || echo "")
        fi
        
        if [ -n "$container_ip" ] && [ "$container_ip" != "<no value>" ]; then
            print_info "Resolved container '$hostname' to IP: $container_ip" >&2
            # Replace hostname with IP in URL using sed
            url=$(echo "$url" | sed "s|@$hostname:|@$container_ip:|")
        else
            print_warning "Could not resolve container '$hostname', using as-is" >&2
        fi
    else
        print_warning "Docker command not found, cannot resolve container IP" >&2
    fi
    
    echo "$url"
}

# Directory where dumps will be saved
DUMP_DIR="dump"

# Create dump directory if it doesn't exist
if [ ! -d "$DUMP_DIR" ]; then
    print_info "Creating directory $DUMP_DIR..."
    mkdir -p "$DUMP_DIR"
fi

# Generate timestamp for file naming (YYYY-MM-DD_HHMMSS format)
TIMESTAMP=$(date +"%Y-%m-%d_%H%M%S")

# Create backup file names with timestamp
ROLES_FILE="$DUMP_DIR/backup_${TIMESTAMP}_roles.sql"
SCHEMA_FILE="$DUMP_DIR/backup_${TIMESTAMP}_schema.sql"
DATA_FILE="$DUMP_DIR/backup_${TIMESTAMP}_data.sql"

# Check if database URL was provided as argument
if [ -n "$1" ]; then
    DB_URL="$1"
    print_info "Using database URL provided as argument"
elif [ -n "$DATABASE_URL" ]; then
    DB_URL="$DATABASE_URL"
    print_info "Using DATABASE_URL from environment variables"
elif [ -n "$POSTGRES_HOST" ] && [ -n "$POSTGRES_PORT" ] && [ -n "$POSTGRES_DB" ] && [ -n "$POSTGRES_PASSWORD" ]; then
    # Build URL from environment variables
    DB_URL="postgresql://postgres:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}"
    print_info "Building database URL from environment variables"
else
    print_error "Database URL not provided!"
    echo ""
    echo "Usage:"
    echo "  $0 [DATABASE_URL]"
    echo ""
    echo "Or set the following environment variables:"
    echo "  - DATABASE_URL (full database URL)"
    echo "  - Or POSTGRES_HOST, POSTGRES_PORT, POSTGRES_DB, POSTGRES_PASSWORD"
    echo ""
    echo "Example:"
    echo "  $0 'postgresql://postgres:password@localhost:5432/postgres'"
    echo ""
    exit 1
fi

print_info "Starting database backup..."

# Resolve Docker container hostnames to IPs (needed for Supabase CLI)
DB_URL=$(resolve_container_ip "$DB_URL")

print_info "Database URL: ${DB_URL//:*/:***}@${DB_URL#*@}"

# Check if supabase CLI is available
if ! command -v npx &> /dev/null; then
    print_error "npx not found. Please install Node.js and npm."
    exit 1
fi

# Roles dump
print_info "Creating roles dump..."
if npx --yes supabase db dump --db-url "$DB_URL" --file "$ROLES_FILE" --role-only; then
    print_info "✓ Roles dump created successfully: $ROLES_FILE"
else
    print_error "✗ Failed to create roles dump"
    exit 1
fi

# Schema dump
print_info "Creating schema dump..."
if npx --yes supabase db dump --db-url "$DB_URL" --file "$SCHEMA_FILE" --debug; then
    print_info "✓ Schema dump created successfully: $SCHEMA_FILE"
else
    print_error "✗ Failed to create schema dump"
    exit 1
fi

# Data dump
print_info "Creating data dump..."
if npx --yes supabase db dump --db-url "$DB_URL" --file "$DATA_FILE" --debug --data-only --use-copy; then
    print_info "✓ Data dump created successfully: $DATA_FILE"
else
    print_error "✗ Failed to create data dump"
    exit 1
fi

print_info "Backup completed successfully!"
print_info "Backup timestamp: $TIMESTAMP"
print_info "Files created:"
echo "  - $ROLES_FILE"
echo "  - $SCHEMA_FILE"
echo "  - $DATA_FILE"
if [ -d "$DUMP_DIR" ]; then
    echo ""
    print_info "File sizes:"
    ls -lh "$ROLES_FILE" "$SCHEMA_FILE" "$DATA_FILE" 2>/dev/null || print_warning "Could not list file sizes"
fi

