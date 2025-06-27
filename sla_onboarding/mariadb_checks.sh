#!/bin/bash
# MariaDB specific checks

# Use configured paths from main script, or defaults if not set
MARIADB_BIN_PATHS=(
  "${MARIADB_BASE_PATHS[@]:-/usr/bin /usr/local/bin /opt/mariadb/bin /u01/app/mariadb/product /u01/app/mariadb/bin}"
)

MARIADB_SEARCH_DATA_PATHS=(
  "${MARIADB_DATA_PATHS[@]:-/var/lib/mysql /usr/local/mariadb/data /opt/mariadb/data /u02/mariadb}"
)

# Try to find MariaDB binary in configured locations
MARIADB_CMD=""
for base_path in "${MARIADB_BIN_PATHS[@]}"; do
  # Direct binary check (prefer mariadb over mysql)
  for mariadb_binary in "$base_path/mariadb" "$base_path/mysql" "$base_path/bin/mariadb" "$base_path/bin/mysql"; do
    if [ -x "$mariadb_binary" ]; then
      MARIADB_CMD="$mariadb_binary"
      break 2
    fi
  done
  
  # OFA-style version paths like /u01/app/mariadb/product/10.11/db_1/bin/mariadb
  for version_path in "$base_path"/{10.*,11.*}/db_*/bin/{mariadb,mysql}; do
    if [ -x "$version_path" ]; then
      MARIADB_CMD="$version_path"
      break 2
    fi
  done
done

# Fallback to PATH
if [ -z "$MARIADB_CMD" ]; then
  MARIADB_CMD="$(command -v mariadb 2>/dev/null || command -v mysql 2>/dev/null || true)"
fi

# Function to discover MariaDB data directories
mariadb_find_datadirs() {
  local datadirs=()
  
  # Method 1: Get from running MariaDB instance
  if [ -n "$MARIADB_CMD" ]; then
    local running_datadir=$(mariadb_exec "SELECT @@datadir;" 2>/dev/null | tail -n +2 | tr -d ' ')
    [ -n "$running_datadir" ] && datadirs+=("$running_datadir")
  fi
  
  # Method 2: Check process list for --datadir
  if command -v ps >/dev/null 2>&1; then
    local proc_datadirs=$(ps aux | grep -E '(mariadbd|mysqld).*--datadir' | grep -v grep | sed -n 's/.*--datadir[= ]\([^ ]*\).*/\1/p' | sort -u)
    for datadir in $proc_datadirs; do
      [ -d "$datadir" ] && datadirs+=("$datadir")
    done
  fi
  
  # Method 3: Search configured data paths
  for data_path in "${MARIADB_SEARCH_DATA_PATHS[@]}"; do
    if [ -d "$data_path" ]; then
      datadirs+=("$data_path")
      
      # Look for version-specific subdirectories
      for version_dir in "$data_path"/{10.*,11.*}; do
        [ -d "$version_dir" ] && datadirs+=("$version_dir")
      done
      
      # Look for alias-based directories
      for alias_dir in "$data_path"/{db_*,main,primary,mariadb*,galera*}; do
        [ -d "$alias_dir" ] && datadirs+=("$alias_dir")
      done
    fi
  done
  
  # Remove duplicates and print
  printf '%s\n' "${datadirs[@]}" | sort -u
}

# Function to get MariaDB connection parameters
mariadb_get_connection() {
  local conn_opts=""
  
  # Method 1: Try to get socket from running instance
  if [ -n "$MARIADB_CMD" ]; then
    local running_socket=$(mariadb_exec "SELECT @@socket;" 2>/dev/null | tail -n +2 | tr -d ' ')
    if [ -n "$running_socket" ] && [ -S "$running_socket" ]; then
      conn_opts="--socket=$running_socket"
      echo "$conn_opts"
      return
    fi
  fi
  
  # Method 2: Try common socket locations
  local socket_paths=(
    "/var/lib/mysql/mysql.sock"
    "/tmp/mysql.sock"
    "/var/run/mysqld/mysqld.sock"
    "/u01/mariadb/mysql.sock"
    "/u02/mariadb/mysql.sock"
  )
  
  for socket in "${socket_paths[@]}"; do
    if [ -S "$socket" ]; then
      conn_opts="--socket=$socket"
      echo "$conn_opts"
      return
    fi
  done
  
  # Method 3: Try TCP connection with custom ports
  for port in 3306 3307 3308; do
    if netstat -ln 2>/dev/null | grep -q ":$port "; then
      conn_opts="--host=localhost --port=$port"
      echo "$conn_opts"
      return
    fi
  done
  
  # Fallback
  echo "--host=localhost --port=3306"
}

# Function to execute MariaDB commands with proper authentication
mariadb_exec() {
  local query="$1"
  local conn_opts=$(mariadb_get_connection)
  
  # Try without password first (for systems with auth_socket)
  $MARIADB_CMD $conn_opts -e "$query" 2>/dev/null || \
  # Try with root and empty password
  $MARIADB_CMD $conn_opts -u root -e "$query" 2>/dev/null || \
  # Try with credentials file if exists
  $MARIADB_CMD $conn_opts --defaults-file=/etc/mysql/debian.cnf -e "$query" 2>/dev/null || \
  # Last resort: try sudo to mysql user if exists
  sudo -u mysql $MARIADB_CMD $conn_opts -e "$query" 2>/dev/null || \
  echo "Unable to connect to MariaDB"
}

mariadb_get_paths() {
  echo "---- MariaDB Runtime Paths ----"
  if [ -z "$MARIADB_CMD" ]; then
    echo "mariadb command not found"; return
  fi
  
  echo "Binary Location: $MARIADB_CMD"
  
  # Get paths from running instance
  mariadb_exec "
    SELECT 'datadir: ', @@datadir
    UNION ALL
    SELECT 'basedir: ', @@basedir
    UNION ALL
    SELECT 'plugin_dir: ', @@plugin_dir
    UNION ALL
    SELECT 'log_error: ', @@log_error
    UNION ALL
    SELECT 'general_log_file: ', @@general_log_file
    UNION ALL
    SELECT 'slow_query_log_file: ', @@slow_query_log_file
    UNION ALL
    SELECT 'socket: ', @@socket
    UNION ALL
    SELECT 'pid_file: ', @@pid_file
  " | grep -v "Variable_name" | sed 's/^/  /'
}

mariadb_summary() {
  echo "---- MariaDB Summary ----"
  if [ -z "$MARIADB_CMD" ]; then
    echo "mariadb command not found"; return
  fi
  
  local version=$(mariadb_exec 'SELECT VERSION();' | tail -n +2)
  local datadir=$(mariadb_exec 'SELECT @@datadir;' | tail -n +2)
  echo "Version: $version"
  echo "Data Dir: $datadir"
  
  # Show runtime paths
  mariadb_get_paths
}

mariadb_memory() {
  echo "---- MariaDB Memory ----"
  [ -z "$MARIADB_CMD" ] && { echo "mariadb command not found"; return; }
  mariadb_exec "SHOW VARIABLES LIKE 'innodb_buffer_pool_size';" | tail -n +2
}

mariadb_show_config() {
  echo "---- MariaDB Configuration ----"
  [ -z "$MARIADB_CMD" ] && { echo "mariadb command not found"; return; }
  mariadb_exec 'SHOW GLOBAL VARIABLES;' | head -n 20
}

mariadb_db_sizes() {
  echo "---- MariaDB Database Sizes ----"
  [ -z "$MARIADB_CMD" ] && { echo "mariadb command not found"; return; }
  mariadb_exec "SELECT table_schema, ROUND(SUM(data_length+index_length)/1024/1024,2) AS size_mb FROM information_schema.tables GROUP BY table_schema;" | tail -n +2
}

mariadb_innodb_status() {
  echo "---- MariaDB InnoDB Status ----"
  [ -z "$MARIADB_CMD" ] && { echo "mariadb command not found"; return; }
  mariadb_exec 'SHOW ENGINE INNODB STATUS\G' | head -n 20
}

mariadb_cluster_status() {
  echo "---- MariaDB Cluster Status ----"
  [ -z "$MARIADB_CMD" ] && { echo "mariadb command not found"; return; }
  echo "Galera Cluster:"
  mariadb_exec "SHOW STATUS LIKE 'wsrep%';" | grep -E "(wsrep_cluster_size|wsrep_local_state_comment|wsrep_ready|wsrep_cluster_status)" | sed 's/^/  /' || echo "  Not a Galera cluster"
  echo "Replication (if not Galera):"
  mariadb_exec "SHOW SLAVE STATUS\G" | grep -E "(Slave_IO_State|Master_Host|Seconds_Behind_Master)" | sed 's/^/  /' || echo "  Not configured as slave"
}

mariadb_plugins() {
  echo "---- MariaDB Plugins ----"
  [ -z "$MARIADB_CMD" ] && { echo "mariadb command not found"; return; }
  mariadb_exec "SELECT PLUGIN_NAME, PLUGIN_STATUS, PLUGIN_TYPE FROM information_schema.PLUGINS WHERE PLUGIN_STATUS='ACTIVE' ORDER BY PLUGIN_TYPE, PLUGIN_NAME;" | head -n 15 | sed 's/^/  /'
}

mariadb_config_files() {
  echo "---- MariaDB Configuration Files ----"
  for config in "/etc/mysql/my.cnf" "/etc/my.cnf" "/usr/local/mysql/my.cnf" "/opt/mariadb/my.cnf"; do
    if [ -f "$config" ]; then
      echo "Config: $config ($(stat -c%Y "$config" 2>/dev/null | xargs -I{} date -d @{} '+%Y-%m-%d %H:%M' || echo 'stat failed'))"
    fi
  done
  # Check for included directories
  for dir in "/etc/mysql/conf.d" "/etc/mysql/mariadb.conf.d" "/etc/my.cnf.d"; do
    if [ -d "$dir" ]; then
      local count=$(ls "$dir"/*.cnf 2>/dev/null | wc -l)
      echo "Config dir: $dir ($count files)"
      ls "$dir"/*.cnf 2>/dev/null | head -5 | sed 's/^/  /'
    fi
  done
}

mariadb_users_security() {
  echo "---- MariaDB Users & Security ----"
  [ -z "$MARIADB_CMD" ] && { echo "mariadb command not found"; return; }
  echo "User Accounts:"
  mariadb_exec "SELECT User, Host, account_locked, password_expired FROM mysql.user ORDER BY User;" | head -n 10 | sed 's/^/  /'
  echo "SSL Configuration:"
  mariadb_exec "SHOW VARIABLES LIKE 'ssl%';" | sed 's/^/  /' || echo "  SSL variables not available"
  echo "Authentication Plugins:"
  mariadb_exec "SELECT User, Host, plugin FROM mysql.user WHERE User != '' ORDER BY User;" | head -n 10 | sed 's/^/  /'
}

# MariaDB CIS Compliance Check Wrapper - calls the actual function from cis_integration.sh
mariadb_cis_compliance_check() {
  # Skip CIS checks if explicitly disabled in interactive mode
  if [ "${INTERACTIVE_MARIADB_CIS_ENABLED:-}" = "false" ]; then
    echo "CIS Compliance|Skipped per user request in interactive mode"
    return 0
  fi
  
  # Check if the CIS integration module function exists (already sourced in main_cli.sh)
  if declare -f mariadb_cis_compliance_check > /dev/null 2>&1; then
    # This is a name conflict - we need to call the integration function directly
    # but avoid infinite recursion. Use a bypass approach.
    echo "CIS Compliance|Calling MariaDB CIS integration..."
    local script_dir="$(dirname "$0")"
    cd "$script_dir" && python3 mariadb1011_CIS_checks.py 2>/dev/null && {
      echo "CIS Compliance|MariaDB CIS assessment completed"
      local cis_output_file=$(ls -t mariadb1011_cis_check_*.txt 2>/dev/null | head -1)
      if [ -n "$cis_output_file" ]; then
        echo "CIS Output File|$cis_output_file"
      fi
    } || echo "CIS Compliance|MariaDB CIS assessment failed - check prerequisites"
  else
    echo "CIS Compliance|MariaDB CIS integration not available"
    echo "CIS Compliance|Install prerequisites and ensure mariadb1011_CIS_checks.py is present"
  fi
}

