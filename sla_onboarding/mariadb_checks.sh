#!/bin/bash
# MariaDB specific checks

# Try to find MariaDB binary in common locations
MARIADB_CMD=""
for mariadb_path in "/usr/bin/mariadb" "/usr/local/bin/mariadb" "/opt/mariadb/bin/mariadb" "/u01/app/mariadb/bin/mariadb" "/usr/bin/mysql" "/usr/local/bin/mysql" "/opt/mysql/bin/mysql"; do
  if [ -x "$mariadb_path" ]; then
    MARIADB_CMD="$mariadb_path"
    break
  fi
done

# Fallback to PATH
if [ -z "$MARIADB_CMD" ]; then
  MARIADB_CMD="$(command -v mariadb 2>/dev/null || command -v mysql 2>/dev/null || true)"
fi

# Function to get MariaDB connection parameters
mariadb_get_connection() {
  local conn_opts=""
  
  # Try default socket locations
  for socket in "/var/lib/mysql/mysql.sock" "/tmp/mysql.sock" "/var/run/mysqld/mysqld.sock" "/u01/mariadb/mysql.sock"; do
    if [ -S "$socket" ]; then
      conn_opts="--socket=$socket"
      break
    fi
  done
  
  # If no socket found, try TCP connection
  if [ -z "$conn_opts" ]; then
    conn_opts="--host=localhost --port=3306"
  fi
  
  echo "$conn_opts"
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

