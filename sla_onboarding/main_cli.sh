#!/bin/bash
# Main CLI for SLA onboarding checks
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load custom configuration if it exists
if [ -f "$SCRIPT_DIR/config.sh" ]; then
  echo "Loading custom configuration from $SCRIPT_DIR/config.sh"
  source "$SCRIPT_DIR/config.sh"
fi

# Output format variables
FORMAT="txt"
OUTPUT_FILE=""
REPORT=()

# =============================================================================
# CUSTOMIZABLE PATH VARIABLES - Modify these for your environment
# =============================================================================

# PostgreSQL paths (OFA-style: /u01/app/postgres/product/MAJOR/db_MINOR)
export PG_BASE_PATHS=(
  "/var/lib/postgresql"           # Standard Debian/Ubuntu
  "/usr/local/pgsql"             # Standard source install
  "/opt/postgresql"              # Standard RPM install
  "/u01/app/postgres/product"    # OFA base path
  "/u02/pgdata"                  # OFA data path
)

# MySQL paths
export MYSQL_BASE_PATHS=(
  "/usr/bin"                     # Standard package install
  "/usr/local/bin"               # Standard source install
  "/opt/mysql/bin"               # Standard MySQL install
  "/u01/app/mysql/product"       # OFA base path
  "/u01/app/mysql/bin"           # OFA binary path
)

export MYSQL_DATA_PATHS=(
  "/var/lib/mysql"               # Standard package data
  "/usr/local/mysql/data"        # Standard source data
  "/opt/mysql/data"              # Standard MySQL data
  "/u02/mysql"                   # OFA data path
)

# MariaDB paths
export MARIADB_BASE_PATHS=(
  "/usr/bin"                     # Standard package install
  "/usr/local/bin"               # Standard source install
  "/opt/mariadb/bin"             # Standard MariaDB install
  "/u01/app/mariadb/product"     # OFA base path
  "/u01/app/mariadb/bin"         # OFA binary path
)

export MARIADB_DATA_PATHS=(
  "/var/lib/mysql"               # Standard package data
  "/usr/local/mariadb/data"      # Standard source data
  "/opt/mariadb/data"            # Standard MariaDB data
  "/u02/mariadb"                 # OFA data path
)

# =============================================================================

source "$SCRIPT_DIR/os_checks.sh"
source "$SCRIPT_DIR/postgres_checks.sh"
source "$SCRIPT_DIR/mysql_checks.sh"
source "$SCRIPT_DIR/mariadb_checks.sh"

usage() {
  cat <<USAGE
Usage: $0 [OPTIONS]
  --postgres         Run PostgreSQL checks
  --mysql            Run MySQL checks
  --mariadb          Run MariaDB checks
  --os               Run OS checks
  --all              Run all checks
  --format=FORMAT    Output format: txt, csv, json (default: txt)
  --output=FILE      Write output to file instead of stdout
  -h, --help         Show this help
USAGE
}

# Override echo to collect output
collect() {
  REPORT+=("$1")
}

# Replace echo with collect in all the check scripts
override_echo() {
  # Save original echo function
  eval "original_echo() { $(declare -f echo); }"
  # Override echo to use collect
  echo() {
    collect "$*"
  }
}

# Restore original echo behavior
restore_echo() {
  # Restore original echo function
  eval "echo() { $(declare -f original_echo | sed 's/^original_echo/echo/'); }"
  unset -f original_echo
}

# Parse arguments
run_postgres=false
run_mysql=false
run_mariadb=false
run_os=false

if [ $# -eq 0 ]; then
  usage
  exit 1
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --postgres) run_postgres=true ; shift ;;
    --mysql) run_mysql=true ; shift ;;
    --mariadb) run_mariadb=true ; shift ;;
    --os) run_os=true ; shift ;;
    --all) run_postgres=true; run_mysql=true; run_mariadb=true; run_os=true; shift ;;
    --format=*) FORMAT="${1#*=}"; shift ;;
    --output=*) OUTPUT_FILE="${1#*=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

# Validate format
if [[ ! "$FORMAT" =~ ^(txt|csv|json)$ ]]; then
  echo "Error: Invalid format. Supported formats: txt, csv, json"
  exit 1
fi

# Override echo to collect output
override_echo

# Run selected checks
if $run_os; then
  os_summary
  os_security
  os_storage
  os_services
  os_patches
fi
if $run_postgres; then
  pg_summary
  pg_config_files
  pg_extensions
  pg_users_databases
  pg_backup_config
  pg_memory
  pg_disk
  pg_replication
  pg_logs
  pg_db_sizes
fi
if $run_mysql; then
  mysql_summary
  mysql_get_paths
  mysql_users_security
  mysql_replication
  mysql_config_files
  mysql_storage_engines
  mysql_memory
  mysql_show_config
  mysql_db_sizes
  mysql_innodb_status
fi
if $run_mariadb; then
  mariadb_summary
  mariadb_get_paths
  mariadb_cluster_status
  mariadb_plugins
  mariadb_config_files
  mariadb_users_security
  mariadb_memory
  mariadb_show_config
  mariadb_db_sizes
  mariadb_innodb_status
fi

# Restore original echo function
restore_echo

# Generate output in requested format
output_result() {
  local result=""
  
  case "$FORMAT" in
    json)
      # Create JSON representation
      result="{\n"
      result+="  \"timestamp\": \"$(date -Iseconds)\",\n"
      result+="  \"hostname\": \"$(hostname)\",\n"
      result+="  \"checks\": [\n"
      
      local first=true
      for line in "${REPORT[@]}"; do
        if [ "$first" = true ]; then
          first=false
        else
          result+=",\n"
        fi
        # Escape any quotes in the line
        line="${line//\"/\\\"}"
        result+="    \"$line\""
      done
      
      result+="\n  ]\n"
      result+="}\n"
      ;;
    
    csv)
      # Create CSV representation
      result="Timestamp,Hostname,Check,Value\n"
      local timestamp=$(date -Iseconds)
      local hostname=$(hostname)
      
      for line in "${REPORT[@]}"; do
        # Split at first colon or pipe if exists
        if [[ "$line" == *":"* ]]; then
          local check="${line%%:*}"
          local value="${line#*: }"
          # Escape any commas and quotes
          check="${check//,/\\,}"
          check="${check//\"/\\\"}"
          value="${value//,/\\,}"
          value="${value//\"/\\\"}"
          result+="$timestamp,$hostname,\"$check\",\"$value\"\n"
        elif [[ "$line" == *"|"* ]]; then
          local check="${line%%|*}"
          local value="${line#*| }"
          # Escape any commas and quotes
          check="${check//,/\\,}"
          check="${check//\"/\\\"}"
          value="${value//,/\\,}"
          value="${value//\"/\\\"}"
          result+="$timestamp,$hostname,\"$check\",\"$value\"\n"
        else
          # Just use the whole line as the check
          local check="${line//,/\\,}"
          check="${check//\"/\\\"}"
          result+="$timestamp,$hostname,\"$check\",\"\"\n"
        fi
      done
      ;;
    
    txt|*)
      # Plain text just uses the raw collected lines
      for line in "${REPORT[@]}"; do
        result+="$line\n"
      done
      ;;
  esac
  
  # Output to file or stdout
  if [ -n "$OUTPUT_FILE" ]; then
    echo -e "$result" > "$OUTPUT_FILE"
    echo "Output written to $OUTPUT_FILE"
  else
    echo -e "$result"
  fi
}

output_result

exit 0
