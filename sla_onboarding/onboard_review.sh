#!/bin/bash
# SLA onboarding script - collects server and database info in TXT, CSV and JSON formats

set -euo pipefail

FORMAT="txt"
OUTPUT_DIR="$(pwd)"

# allow custom binary locations
PSQL_BIN="$(command -v psql 2>/dev/null || true)"
MYSQL_BIN="$(command -v mysql 2>/dev/null || true)"
MARIADB_BIN="$(command -v mariadb 2>/dev/null || command -v mysql 2>/dev/null || true)"

PG_CONF=""
MYSQL_CONF=""
MARIADB_CONF=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--format)
      FORMAT="$2"; shift 2;;
    -o|--output-dir)
      OUTPUT_DIR="$2"; shift 2;;
    --psql)
      PSQL_BIN="$2"; shift 2;;
    --mysql)
      MYSQL_BIN="$2"; shift 2;;
    --mariadb)
      MARIADB_BIN="$2"; shift 2;;
    --pgconf)
      PG_CONF="$2"; shift 2;;
    --mysqlconf)
      MYSQL_CONF="$2"; shift 2;;
    --mariadbconf)
      MARIADB_CONF="$2"; shift 2;;
    *)
      echo "Usage: $0 [-f txt|csv|json|all] [-o output_dir] [--psql PATH] [--mysql PATH] [--mariadb PATH] [--pgconf PATH] [--mysqlconf PATH] [--mariadbconf PATH]" >&2
      exit 1
      ;;
  esac
done

mkdir -p "$OUTPUT_DIR"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
HOSTNAME=$(hostname -s)

TEXT_FILE="$OUTPUT_DIR/${TIMESTAMP}-${HOSTNAME}.txt"
CSV_FILE="$OUTPUT_DIR/${TIMESTAMP}-${HOSTNAME}.csv"
JSON_FILE="$OUTPUT_DIR/${TIMESTAMP}-${HOSTNAME}.json"

# Helper to run a command and capture output or empty string if fails
run_cmd() {
  CMD_OUTPUT=$(eval "$1" 2>/dev/null || true)
  echo "$CMD_OUTPUT"
}

# Detect database engines and versions
PG_VERSION=""
MYSQL_VERSION=""
MARIADB_VERSION=""
if [ -n "$PSQL_BIN" ]; then
  PG_VERSION=$(run_cmd "$PSQL_BIN --version | awk '{print \$3}'")
fi
if [ -n "$MYSQL_BIN" ]; then
  MYSQL_VERSION=$(run_cmd "$MYSQL_BIN --version | awk '{print \$5}' | tr -d ','")
fi
if [ -n "$MARIADB_BIN" ]; then
  MARIADB_VERSION=$(run_cmd "$MARIADB_BIN --version | awk '{print \$5}' | tr -d ','")
fi

# OS and hardware info
if command -v lsb_release >/dev/null 2>&1; then
  OS_RELEASE=$(lsb_release -ds)
elif [ -r /etc/os-release ]; then
  OS_RELEASE=$(grep -E '^PRETTY_NAME=' /etc/os-release | cut -d= -f2- | tr -d '"')
else
  OS_RELEASE=$(uname -s)
fi
UNAME=$(uname -a)
CPU_INFO=$(run_cmd 'lscpu')
MEM_INFO=$(run_cmd 'free -m')
DISK_INFO=$(df -h)

# Config file checksums
declare -A CONFIG_FILES
CONFIG_FILES[mysql]="${MYSQL_CONF:-/etc/mysql/my.cnf}"
CONFIG_FILES[mariadb]="${MARIADB_CONF:-/etc/mysql/mariadb.conf.d/50-server.cnf}"
CONFIG_FILES[postgresql]="${PG_CONF:-$(find /etc/postgresql -name postgresql.conf 2>/dev/null | head -n 1 || true)}"

CONFIG_SUMS=""
for key in "${!CONFIG_FILES[@]}"; do
  FILE=${CONFIG_FILES[$key]}
  if [ -f "$FILE" ]; then
    SUM=$(sha256sum "$FILE" | awk '{print $1}')
    CONFIG_SUMS+="$key=$FILE ($SUM)\n"
  fi
done

# Security posture (limited)
PG_USERS=$(run_cmd 'psql -At -c "SELECT usename FROM pg_user"')
MYSQL_USERS=$(run_cmd 'mysql -N -e "SELECT user, host FROM mysql.user"')

# Backup directory discovery
BACKUP_DIR=""
for d in /var/backups /var/lib/mysql/backups /var/lib/postgresql/backups; do
  if [ -d "$d" ]; then
    BACKUP_DIR="$d"
    break
  fi
done

# Data directories
PG_DATA=""
MYSQL_DATA=""
MARIADB_DATA=""
if [ -n "$PSQL_BIN" ]; then
  PG_DATA=$(run_cmd "$PSQL_BIN -Atc 'SHOW data_directory;'")
fi
if [ -n "$MYSQL_BIN" ]; then
  MYSQL_DATA=$(run_cmd "$MYSQL_BIN -N -e 'SELECT @@datadir'")
fi
if [ -n "$MARIADB_BIN" ]; then
  MARIADB_DATA=$(run_cmd "$MARIADB_BIN -N -e 'SELECT @@datadir'")
fi

# export variables for python
export HOSTNAME TIMESTAMP PG_VERSION MYSQL_VERSION MARIADB_VERSION OS_RELEASE UNAME CPU_INFO MEM_INFO DISK_INFO CONFIG_SUMS PG_USERS MYSQL_USERS BACKUP_DIR PG_DATA MYSQL_DATA MARIADB_DATA JSON_FILE

# Compose text output function
write_txt() {
  {
  echo "Hostname: $HOSTNAME"
  echo "Timestamp: $TIMESTAMP"
  echo "PostgreSQL version: ${PG_VERSION:-N/A}"
  echo "MySQL version: ${MYSQL_VERSION:-N/A}"
  echo "MariaDB version: ${MARIADB_VERSION:-N/A}"
  echo
  echo "OS Release:\n$OS_RELEASE"
  echo "Kernel: $UNAME"
  echo
  echo "CPU Info:\n$CPU_INFO"
  echo
  echo "Memory Info:\n$MEM_INFO"
  echo
  echo "Disk Info:\n$DISK_INFO"
  echo
  echo "Config Checksums:\n$CONFIG_SUMS"
  echo
  echo "PostgreSQL Users:\n$PG_USERS"
  echo "MySQL Users:\n$MYSQL_USERS"
  echo
  echo "Backup Directory: ${BACKUP_DIR:-N/A}"
  echo "PostgreSQL Data Dir: ${PG_DATA:-N/A}"
  echo "MySQL Data Dir: ${MYSQL_DATA:-N/A}"
  echo "MariaDB Data Dir: ${MARIADB_DATA:-N/A}"
  } > "$TEXT_FILE"
}

# CSV output function
write_csv() {
  {
  echo "key,value"
  echo "hostname,$HOSTNAME"
  echo "timestamp,$TIMESTAMP"
  echo "postgresql_version,${PG_VERSION:-}" 
  echo "mysql_version,${MYSQL_VERSION:-}"
  echo "mariadb_version,${MARIADB_VERSION:-}"
  echo "backup_dir,${BACKUP_DIR:-}"
  echo "postgresql_data_dir,${PG_DATA:-}"
  echo "mysql_data_dir,${MYSQL_DATA:-}"
  echo "mariadb_data_dir,${MARIADB_DATA:-}"
  } > "$CSV_FILE"
}

# JSON output function using Python for better escaping
write_json() {
python3 - <<'EOF_PY' > "$JSON_FILE"
import json, os
keys = [
  "HOSTNAME", "TIMESTAMP", "PG_VERSION", "MYSQL_VERSION", "MARIADB_VERSION",
  "OS_RELEASE", "UNAME", "CPU_INFO", "MEM_INFO", "DISK_INFO", "CONFIG_SUMS",
  "PG_USERS", "MYSQL_USERS", "BACKUP_DIR",
  "PG_DATA", "MYSQL_DATA", "MARIADB_DATA"
]
data = {k.lower(): os.environ.get(k) for k in keys}
with open(os.environ["JSON_FILE"], "w") as fh:
    json.dump(data, fh, indent=2)
EOF_PY
}

FILES=""
case "$FORMAT" in
  txt)
    write_txt; FILES="$TEXT_FILE";;
  csv)
    write_csv; FILES="$CSV_FILE";;
  json)
    write_json; FILES="$JSON_FILE";;
  all)
    write_txt; write_csv; write_json; FILES="$TEXT_FILE $CSV_FILE $JSON_FILE";;
  *)
    echo "Invalid format: $FORMAT" >&2; exit 1;;
esac

printf 'Generated files: %s\n' "$FILES"

