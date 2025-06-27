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

source "$SCRIPT_DIR/error_handling.sh"
source "$SCRIPT_DIR/performance_metrics.sh"
source "$SCRIPT_DIR/backup_validation.sh"
source "$SCRIPT_DIR/security_assessment.sh"
source "$SCRIPT_DIR/os_checks.sh"
source "$SCRIPT_DIR/postgres_checks.sh"
source "$SCRIPT_DIR/mysql_checks.sh"
source "$SCRIPT_DIR/mariadb_checks.sh"
source "$SCRIPT_DIR/sla_templates.sh"

# Initialize error handling
init_error_handling

usage() {
  cat <<USAGE
Usage: $0 [OPTIONS]
  --postgres         Run PostgreSQL checks
  --mysql            Run MySQL checks
  --mariadb          Run MariaDB checks
  --os               Run OS checks
  --all              Run all checks
  --interactive      Interactive mode with guided execution
  --format=FORMAT    Output format: txt, csv, json (default: txt)
  --output=FILE      Write output to file instead of stdout
  -h, --help         Show this help

Interactive Mode:
  Use --interactive for guided execution suitable for Service Desk operators.
  This mode will detect databases, validate connectivity, and generate 
  SLA-focused reports with clear explanations.
USAGE
}

# Interactive mode functions
interactive_mode() {
  echo "==========================================="
  echo "   SLA Onboarding Assessment - Interactive Mode"
  echo "==========================================="
  echo ""
  echo "This tool will help you assess the database environment for Service Desk onboarding."
  echo "It will automatically detect databases and guide you through the process."
  echo ""
  
  # Pre-flight system checks
  echo "Pre-flight: Checking system readiness..."
  check_prerequisites
  
  # Step 1: System detection
  echo "Step 1: Detecting system information..."
  local hostname=$(hostname)
  local os_info=$(lsb_release -d 2>/dev/null | cut -f2 || echo "Unknown OS")
  echo "  Hostname: $hostname"
  echo "  OS: $os_info"
  echo ""
  
  # Step 2: Database detection
  echo "Step 2: Scanning for database installations..."
  local found_postgres=false
  local found_mysql=false
  local found_mariadb=false
  
  # Check for PostgreSQL
  if command -v psql >/dev/null 2>&1 || pgrep -f postgres >/dev/null 2>&1; then
    echo "  ✓ PostgreSQL detected"
    found_postgres=true
  fi
  
  # Check for MySQL
  if command -v mysql >/dev/null 2>&1 || pgrep -f mysqld >/dev/null 2>&1; then
    echo "  ✓ MySQL detected"
    found_mysql=true
  fi
  
  # Check for MariaDB
  if command -v mariadb >/dev/null 2>&1 || pgrep -f mariadbd >/dev/null 2>&1; then
    echo "  ✓ MariaDB detected"
    found_mariadb=true
  fi
  
  if [ "$found_postgres" = false ] && [ "$found_mysql" = false ] && [ "$found_mariadb" = false ]; then
    echo "  ! No database installations detected"
    echo "    This may be a application server or the databases are installed in non-standard locations."
  fi
  echo ""
  
  # Step 3: Connectivity pre-checks
  echo "Step 3: Testing database connectivity..."
  if [ "$found_postgres" = true ]; then
    test_postgres_connectivity
  fi
  if [ "$found_mysql" = true ]; then
    test_mysql_connectivity  
  fi
  if [ "$found_mariadb" = true ]; then
    test_mariadb_connectivity
  fi
  echo ""
  
  # Step 4: User confirmation
  echo "Step 4: Confirm assessment scope"
  echo "The following checks will be performed:"
  echo "  - Operating System configuration and security"
  if [ "$found_postgres" = true ]; then
    echo "  - PostgreSQL database assessment"
  fi
  if [ "$found_mysql" = true ]; then
    echo "  - MySQL database assessment"
  fi
  if [ "$found_mariadb" = true ]; then
    echo "  - MariaDB database assessment"
  fi
  echo ""
  
  read -p "Continue with assessment? (y/N): " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Assessment cancelled."
    exit 0
  fi
  echo ""
  
  # Step 5: Run assessments
  echo "Step 5: Running assessments..."
  echo "This may take a few minutes depending on database sizes..."
  echo ""
  
  # Set variables for main execution
  run_os=true
  run_postgres=$found_postgres
  run_mysql=$found_mysql
  run_mariadb=$found_mariadb
  
  # Set default format and output for interactive mode
  if [ -z "$OUTPUT_FILE" ]; then
    OUTPUT_FILE="sla_assessment_$(hostname)_$(date +%Y%m%d_%H%M%S).json"
  fi
  if [ "$FORMAT" = "txt" ]; then
    FORMAT="json"
  fi
  
  echo "Assessment will be saved to: $OUTPUT_FILE"
  echo "Format: $FORMAT"
  echo ""
}

# Connectivity test functions
test_postgres_connectivity() {
  echo "  Testing PostgreSQL connectivity..."
  local pg_status="Unknown"
  
  if systemctl is-active postgresql >/dev/null 2>&1; then
    pg_status="Running (systemctl)"
  elif pgrep -f "postgres.*-D" >/dev/null 2>&1; then
    pg_status="Running (process detected)"
  else
    pg_status="Not running or not accessible"
  fi
  
  echo "    Status: $pg_status"
  
  # Try to connect with common methods
  if [ "$pg_status" != "Not running or not accessible" ]; then
    if safe_postgres_exec "sudo -u postgres psql -c 'SELECT version();'" "version check" 10; then
      echo "    Connectivity: ✓ Accessible via sudo postgres user"
    elif safe_postgres_exec "psql -h localhost -U postgres -c 'SELECT version();'" "network connection" 10; then
      echo "    Connectivity: ✓ Accessible via network connection"
    else
      echo "    Connectivity: ⚠ Running but connection method needs configuration"
      echo "      Note: PostgreSQL is running but requires authentication setup"
    fi
  fi
}

test_mysql_connectivity() {
  echo "  Testing MySQL connectivity..."
  local mysql_status="Unknown"
  
  if systemctl is-active mysql >/dev/null 2>&1 || systemctl is-active mysqld >/dev/null 2>&1; then
    mysql_status="Running (systemctl)"
  elif pgrep -f mysqld >/dev/null 2>&1; then
    mysql_status="Running (process detected)"
  else
    mysql_status="Not running or not accessible"
  fi
  
  echo "    Status: $mysql_status"
  
  if [ "$mysql_status" != "Not running or not accessible" ]; then
    if safe_mysql_exec "mysql -e 'SELECT VERSION();'" "version check" 10; then
      echo "    Connectivity: ✓ Accessible without authentication"
    elif safe_mysql_exec "mysql -u root -e 'SELECT VERSION();'" "root connection" 10; then
      echo "    Connectivity: ✓ Accessible as root user"
    else
      echo "    Connectivity: ⚠ Running but requires authentication"
      echo "      Note: MySQL is running but requires credentials for full assessment"
    fi
  fi
}

test_mariadb_connectivity() {
  echo "  Testing MariaDB connectivity..."
  local mariadb_status="Unknown"
  
  if systemctl is-active mariadb >/dev/null 2>&1; then
    mariadb_status="Running (systemctl)"
  elif pgrep -f mariadbd >/dev/null 2>&1; then
    mariadb_status="Running (process detected)"
  else
    mariadb_status="Not running or not accessible"
  fi
  
  echo "    Status: $mariadb_status"
  
  if [ "$mariadb_status" != "Not running or not accessible" ]; then
    if safe_mariadb_exec "mariadb -e 'SELECT VERSION();'" "version check" 10; then
      echo "    Connectivity: ✓ Accessible without authentication"
    elif safe_mariadb_exec "mariadb -u root -e 'SELECT VERSION();'" "root connection" 10; then
      echo "    Connectivity: ✓ Accessible as root user"
    else
      echo "    Connectivity: ⚠ Running but requires authentication"
      echo "      Note: MariaDB is running but requires credentials for full assessment"
    fi
  fi
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
interactive=false

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
    --interactive) interactive=true; shift ;;
    --format=*) FORMAT="${1#*=}"; shift ;;
    --output=*) OUTPUT_FILE="${1#*=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

# Handle interactive mode
if [ "$interactive" = true ]; then
  interactive_mode
fi

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
  system_performance_metrics
  system_security_assessment
  os_monitoring_discovery
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
  pg_performance_metrics
  pg_backup_validation
  pg_security_assessment
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
  mysql_performance_metrics
  mysql_backup_validation
  mysql_security_assessment
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
  mariadb_performance_metrics
  mariadb_backup_validation
  mariadb_security_assessment
fi

# Restore original echo function
restore_echo

# Generate output in requested format
output_result() {
  local result=""
  local raw_report_data=""
  
  # Combine all report data for SLA analysis
  for line in "${REPORT[@]}"; do
    raw_report_data+="$line\n"
  done
  
  case "$FORMAT" in
    json)
      # Create JSON representation with SLA assessment
      local sla_json=$(generate_sla_report "$raw_report_data" "json")
      
      result="{\n"
      result+="  \"timestamp\": \"$(date -Iseconds)\",\n"
      result+="  \"hostname\": \"$(hostname)\",\n"
      
      # Add SLA assessment section
      result+="  \"sla_assessment\": $(echo "$sla_json" | jq '.sla_assessment' 2>/dev/null || echo '{}'),\n"
      
      result+="  \"technical_checks\": [\n"
      
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
      # Create CSV representation with SLA info
      result="Timestamp,Hostname,Check,Value\n"
      local timestamp=$(date -Iseconds)
      local hostname=$(hostname)
      
      # Add SLA assessment as CSV rows
      local sla_csv=$(generate_sla_report "$raw_report_data" "csv")
      result+="$sla_csv\n"
      result+="\n# Technical Checks\n"
      
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
      # Plain text with SLA assessment
      local sla_text=$(generate_sla_report "$raw_report_data" "text")
      result+="$sla_text\n\n"
      
      result+="=================================================================\n"
      result+="                    TECHNICAL ASSESSMENT\n"
      result+="=================================================================\n\n"
      
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
