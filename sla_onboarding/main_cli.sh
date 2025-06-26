#!/bin/bash
# Main CLI for SLA onboarding checks
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

source "$SCRIPT_DIR/os_checks.sh"
source "$SCRIPT_DIR/postgres_checks.sh"
source "$SCRIPT_DIR/mysql_checks.sh"
source "$SCRIPT_DIR/mariadb_checks.sh"

usage() {
  cat <<USAGE
Usage: $0 [OPTIONS]
  --postgres       Run PostgreSQL checks
  --mysql          Run MySQL checks
  --mariadb        Run MariaDB checks
  --os             Run OS checks
  --all            Run all checks
  -h, --help       Show this help
USAGE
}

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
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

$run_os && os_summary
if $run_postgres; then
  pg_summary
  pg_db_sizes
fi
if $run_mysql; then
  mysql_summary
fi
if $run_mariadb; then
  mariadb_summary
fi

exit 0
