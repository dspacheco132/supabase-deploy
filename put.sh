#!/bin/bash

# Supabase database restore script
# This script restores roles, schema and data to the database

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

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS] [SCHEMA_FILE] [ROLES_FILE] [DATA_FILE]"
    echo ""
    echo "Restore Supabase database from SQL backup files."
    echo ""
    echo "Options:"
    echo "  -s, --schema FILE    Schema SQL file (default: schema.sql)"
    echo "  -r, --roles FILE     Roles SQL file (default: roles.sql)"
    echo "  -d, --data FILE      Data SQL file (default: data.sql)"
    echo "  -c, --container NAME Docker container name (default: supabase-db)"
    echo "  -h, --help           Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0"
    echo "    # Uses default files: schema.sql, roles.sql, data.sql"
    echo ""
    echo "  $0 dump/backup_2025-11-20_145630_schema.sql dump/backup_2025-11-20_145630_roles.sql dump/backup_2025-11-20_145630_data.sql"
    echo "    # Uses positional arguments"
    echo ""
    echo "  $0 --schema dump/backup_schema.sql --data dump/backup_data.sql"
    echo "    # Uses named options (roles will use default)"
    echo ""
    echo "  $0 -s dump/schema.sql -r dump/roles.sql -d dump/data.sql"
    echo "    # Uses short options"
    echo ""
    echo "Environment variables:"
    echo "  SUPABASE_DB_CONTAINER  Docker container name"
    echo "  POSTGRES_DB            Database name (default: postgres)"
    echo "  POSTGRES_USER          Database user (default: postgres)"
}

# Default values
CONTAINER_NAME="${SUPABASE_DB_CONTAINER:-supabase-db}"
SCHEMA_FILE="schema.sql"
ROLES_FILE="roles.sql"
DATA_FILE="data.sql"
DB_NAME="${POSTGRES_DB:-postgres}"
DB_USER="${POSTGRES_USER:-postgres}"

# Track which files were explicitly set
SCHEMA_SET=false
ROLES_SET=false
DATA_SET=false

# Parse command line arguments
POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--schema)
            SCHEMA_FILE="$2"
            SCHEMA_SET=true
            shift 2
            ;;
        -r|--roles)
            ROLES_FILE="$2"
            ROLES_SET=true
            shift 2
            ;;
        -d|--data)
            DATA_FILE="$2"
            DATA_SET=true
            shift 2
            ;;
        -c|--container)
            CONTAINER_NAME="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        -*)
            print_error "Unknown option: $1"
            echo ""
            show_usage
            exit 1
            ;;
        *)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done

# Handle positional arguments (for backward compatibility)
if [ ${#POSITIONAL_ARGS[@]} -gt 0 ]; then
    if [ ${#POSITIONAL_ARGS[@]} -ge 1 ]; then
        SCHEMA_FILE="${POSITIONAL_ARGS[0]}"
        SCHEMA_SET=true
    fi
    if [ ${#POSITIONAL_ARGS[@]} -ge 2 ]; then
        ROLES_FILE="${POSITIONAL_ARGS[1]}"
        ROLES_SET=true
    fi
    if [ ${#POSITIONAL_ARGS[@]} -ge 3 ]; then
        DATA_FILE="${POSITIONAL_ARGS[2]}"
        DATA_SET=true
    fi
fi

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    print_error "Docker not found. Please install Docker."
    exit 1
fi

# Check if container exists and is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    print_error "Container '${CONTAINER_NAME}' is not running!"
    echo ""
    echo "Available containers:"
    docker ps --format '  {{.Names}}' || echo "  (none)"
    exit 1
fi

print_info "Using container: ${CONTAINER_NAME}"
print_info "Database: ${DB_NAME}, User: ${DB_USER}"

# Validate that SQL files exist and collect which ones to process
FILES_TO_PROCESS=()

# Check schema file
if [ -f "$SCHEMA_FILE" ]; then
    FILES_TO_PROCESS+=("schema:$SCHEMA_FILE")
    print_info "Found schema file: $SCHEMA_FILE ($(du -h "$SCHEMA_FILE" | cut -f1))"
elif [ "$SCHEMA_SET" = true ]; then
    print_error "Schema file not found: $SCHEMA_FILE"
    exit 1
fi

# Check roles file
if [ -f "$ROLES_FILE" ]; then
    FILES_TO_PROCESS+=("roles:$ROLES_FILE")
    print_info "Found roles file: $ROLES_FILE ($(du -h "$ROLES_FILE" | cut -f1))"
elif [ "$ROLES_SET" = true ]; then
    print_error "Roles file not found: $ROLES_FILE"
    exit 1
fi

# Check data file
if [ -f "$DATA_FILE" ]; then
    FILES_TO_PROCESS+=("data:$DATA_FILE")
    print_info "Found data file: $DATA_FILE ($(du -h "$DATA_FILE" | cut -f1))"
elif [ "$DATA_SET" = true ]; then
    print_error "Data file not found: $DATA_FILE"
    exit 1
fi

# Check if at least one file was found
if [ ${#FILES_TO_PROCESS[@]} -eq 0 ]; then
    print_error "No backup files found!"
    echo ""
    echo "Please specify at least one backup file:"
    echo "  $0 --schema schema.sql"
    echo "  $0 --roles roles.sql"
    echo "  $0 --data data.sql"
    echo "  $0 schema.sql roles.sql data.sql"
    exit 1
fi

# Function to copy and execute SQL file
execute_sql_file() {
    local file=$1
    local description=$2
    local container_path="/tmp/$(basename "$file")"
    
    print_info "Processing $description..."
    
    # Copy file to container
    if docker cp "$file" "${CONTAINER_NAME}:${container_path}"; then
        print_info "✓ File copied to container"
    else
        print_error "✗ Failed to copy file to container"
        exit 1
    fi
    
    # Execute SQL file
    if docker exec "${CONTAINER_NAME}" psql -U "${DB_USER}" -d "${DB_NAME}" -f "${container_path}" > /dev/null 2>&1; then
        print_info "✓ $description executed successfully"
    else
        print_error "✗ Failed to execute $description"
        print_warning "You may want to check the SQL file for errors"
        exit 1
    fi
    
    # Clean up file from container
    docker exec "${CONTAINER_NAME}" rm -f "${container_path}" 2>/dev/null || true
}

print_info "Starting database restore..."
echo ""

# Restore in order: schema, roles, data (only process files that exist)
# Process in specific order regardless of how they were found
if [[ "${FILES_TO_PROCESS[@]}" =~ schema: ]]; then
    for item in "${FILES_TO_PROCESS[@]}"; do
        if [[ "$item" == schema:* ]]; then
            file="${item#schema:}"
            execute_sql_file "$file" "Schema"
            echo ""
            break
        fi
    done
fi

if [[ "${FILES_TO_PROCESS[@]}" =~ roles: ]]; then
    for item in "${FILES_TO_PROCESS[@]}"; do
        if [[ "$item" == roles:* ]]; then
            file="${item#roles:}"
            execute_sql_file "$file" "Roles"
            echo ""
            break
        fi
    done
fi

if [[ "${FILES_TO_PROCESS[@]}" =~ data: ]]; then
    for item in "${FILES_TO_PROCESS[@]}"; do
        if [[ "$item" == data:* ]]; then
            file="${item#data:}"
            execute_sql_file "$file" "Data"
            echo ""
            break
        fi
    done
fi

print_info "Database restore completed successfully!"