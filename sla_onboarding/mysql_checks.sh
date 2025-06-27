#!/bin/bash
# MySQL specific checks

# Use configured paths from main script, or defaults if not set
MYSQL_BIN_PATHS=(
  "${MYSQL_BASE_PATHS[@]:-/usr/bin /usr/local/bin /opt/mysql/bin /u01/app/mysql/product /u01/app/mysql/bin}"
)

MYSQL_SEARCH_DATA_PATHS=(
  "${MYSQL_DATA_PATHS[@]:-/var/lib/mysql /usr/local/mysql/data /opt/mysql/data /u02/mysql}"
)

# Try to find MySQL binary in configured locations
MYSQL_CMD=""
for base_path in "${MYSQL_BIN_PATHS[@]}"; do
  # Direct binary check
  for mysql_binary in "$base_path/mysql" "$base_path/bin/mysql"; do
    if [ -x "$mysql_binary" ]; then
      MYSQL_CMD="$mysql_binary"
      break 2
    fi
  done
  
  # OFA-style version paths like /u01/app/mysql/product/8.0/db_1/bin/mysql
  for version_path in "$base_path"/{5.*,8.*}/db_*/bin/mysql; do
    if [ -x "$version_path" ]; then
      MYSQL_CMD="$version_path"
      break 2
    fi
  done
done

# Fallback to PATH
if [ -z "$MYSQL_CMD" ]; then
  MYSQL_CMD="$(command -v mysql 2>/dev/null || true)"
fi

# Function to discover MySQL data directories
mysql_find_datadirs() {
  local datadirs=()
  
  # Method 1: Get from running MySQL instance
  if [ -n "$MYSQL_CMD" ]; then
    local running_datadir=$(mysql_exec "SELECT @@datadir;" 2>/dev/null | tail -n +2 | tr -d ' ')
    [ -n "$running_datadir" ] && datadirs+=("$running_datadir")
  fi
  
  # Method 2: Check process list for --datadir
  if command -v ps >/dev/null 2>&1; then
    local proc_datadirs=$(ps aux | grep -E 'mysqld.*--datadir' | grep -v grep | sed -n 's/.*--datadir[= ]\([^ ]*\).*/\1/p' | sort -u)
    for datadir in $proc_datadirs; do
      [ -d "$datadir" ] && datadirs+=("$datadir")
    done
  fi
  
  # Method 3: Search configured data paths
  for data_path in "${MYSQL_SEARCH_DATA_PATHS[@]}"; do
    if [ -d "$data_path" ]; then
      datadirs+=("$data_path")
      
      # Look for version-specific subdirectories
      for version_dir in "$data_path"/{5.*,8.*}; do
        [ -d "$version_dir" ] && datadirs+=("$version_dir")
      done
      
      # Look for alias-based directories
      for alias_dir in "$data_path"/{db_*,main,primary,mysql*}; do
        [ -d "$alias_dir" ] && datadirs+=("$alias_dir")
      done
    fi
  done
  
  # Remove duplicates and print
  printf '%s\n' "${datadirs[@]}" | sort -u
}

# Function to get MySQL connection parameters
mysql_get_connection() {
  local conn_opts=""
  
  # Method 1: Try to get socket from running instance
  if [ -n "$MYSQL_CMD" ]; then
    local running_socket=$(mysql_exec "SELECT @@socket;" 2>/dev/null | tail -n +2 | tr -d ' ')
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
    "/u01/mysql/mysql.sock"
    "/u02/mysql/mysql.sock"
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

# Function to execute MySQL commands with proper authentication
mysql_exec() {
  local query="$1"
  local conn_opts=$(mysql_get_connection)
  
  # Try without password first (for systems with auth_socket)
  $MYSQL_CMD $conn_opts -e "$query" 2>/dev/null || \
  # Try with root and empty password
  $MYSQL_CMD $conn_opts -u root -e "$query" 2>/dev/null || \
  # Try with credentials file if exists
  $MYSQL_CMD $conn_opts --defaults-file=/etc/mysql/debian.cnf -e "$query" 2>/dev/null || \
  # Last resort: try sudo to mysql user if exists
  sudo -u mysql $MYSQL_CMD $conn_opts -e "$query" 2>/dev/null || \
  echo "Unable to connect to MySQL"
}

mysql_get_paths() {
  echo "---- MySQL Runtime Paths ----"
  if [ -z "$MYSQL_CMD" ]; then
    echo "mysql command not found"; return
  fi
  
  echo "Binary Location: $MYSQL_CMD"
  
  # Get paths from running instance
  mysql_exec "
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

mysql_summary() {
  echo "---- MySQL Summary ----"
  if [ -z "$MYSQL_CMD" ]; then
    echo "mysql command not found"; return
  fi
  
  local version=$(mysql_exec 'SELECT VERSION();' | tail -n +2)
  local datadir=$(mysql_exec 'SELECT @@datadir;' | tail -n +2)
  echo "Version: $version"
  echo "Data Dir: $datadir"
  
  # Show runtime paths
  mysql_get_paths
}


mysql_memory() {
  echo "---- MySQL Memory ----"
  [ -z "$MYSQL_CMD" ] && { echo "mysql command not found"; return; }
  mysql_exec "SHOW VARIABLES LIKE 'innodb_buffer_pool_size';" | tail -n +2
}

mysql_show_config() {
  echo "---- MySQL Configuration ----"
  [ -z "$MYSQL_CMD" ] && { echo "mysql command not found"; return; }
  mysql_exec 'SHOW GLOBAL VARIABLES;' | head -n 20
}

mysql_db_sizes() {
  echo "---- MySQL Database Sizes ----"
  [ -z "$MYSQL_CMD" ] && { echo "mysql command not found"; return; }
  mysql_exec "SELECT table_schema, ROUND(SUM(data_length+index_length)/1024/1024,2) AS size_mb FROM information_schema.tables GROUP BY table_schema;" | tail -n +2
}

mysql_innodb_status() {
  echo "---- MySQL InnoDB Status ----"
  [ -z "$MYSQL_CMD" ] && { echo "mysql command not found"; return; }
  mysql_exec 'SHOW ENGINE INNODB STATUS\G' | head -n 20
}

mysql_users_security() {
  echo "---- MySQL Users & Security ----"
  [ -z "$MYSQL_CMD" ] && { echo "mysql command not found"; return; }
  echo "User Accounts:"
  mysql_exec "SELECT User, Host, account_locked, password_expired FROM mysql.user ORDER BY User;" | head -n 10
  echo "SSL Configuration:"
  mysql_exec "SHOW VARIABLES LIKE 'ssl%';" || echo "SSL variables not available"
  echo "Authentication Plugins:"
  mysql_exec "SELECT User, Host, plugin FROM mysql.user WHERE User != '' ORDER BY User;" | head -n 10
}

mysql_replication() {
  echo "---- MySQL Replication ----"
  [ -z "$MYSQL_CMD" ] && { echo "mysql command not found"; return; }
  echo "Master Status:"
  mysql_exec "SHOW MASTER STATUS;" || echo "Not a master or not configured"
  echo "Slave Status:"
  mysql_exec "SHOW SLAVE STATUS\G" | grep -E "(Slave_IO_State|Master_Host|Seconds_Behind_Master|Last_Error)" || echo "Not a slave or not configured"
  echo "Binary Logging:"
  mysql_exec "SHOW VARIABLES LIKE 'log_bin%';"
}

mysql_config_files() {
  echo "---- MySQL Configuration Files ----"
  for config in "/etc/mysql/my.cnf" "/etc/my.cnf" "/usr/local/mysql/my.cnf" "/opt/mysql/my.cnf"; do
    if [ -f "$config" ]; then
      echo "Config: $config ($(stat -c%Y "$config" 2>/dev/null | xargs -I{} date -d @{} '+%Y-%m-%d %H:%M' || echo 'stat failed'))"
    fi
  done
  # Check for included directories
  for dir in "/etc/mysql/conf.d" "/etc/mysql/mysql.conf.d" "/etc/my.cnf.d"; do
    if [ -d "$dir" ]; then
      local count=$(ls "$dir"/*.cnf 2>/dev/null | wc -l)
      echo "Config dir: $dir ($count files)"
      ls "$dir"/*.cnf 2>/dev/null | head -5 | sed 's/^/  /'
    fi
  done
}

mysql_storage_engines() {
  echo "---- MySQL Storage Engines ----"
  [ -z "$MYSQL_CMD" ] && { echo "mysql command not found"; return; }
  mysql_exec "SHOW ENGINES;" | grep -E "(InnoDB|MyISAM|Memory|Archive|CSV)" | awk '{print $1, $2}' | sed 's/^/  /'
  echo "Default Storage Engine:"
  mysql_exec "SHOW VARIABLES LIKE 'default_storage_engine';"
}

