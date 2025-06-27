#!/bin/bash
# MariaDB specific checks

MARIADB_CMD="$(command -v mariadb 2>/dev/null || command -v mysql 2>/dev/null || true)"

mariadb_summary() {
  echo "---- MariaDB Summary ----"
  if [ -z "$MARIADB_CMD" ]; then
    echo "mariadb command not found"; return
  fi
  local version=$($MARIADB_CMD -N -e 'SELECT VERSION();' 2>/dev/null)
  local datadir=$($MARIADB_CMD -N -e 'SELECT @@datadir;' 2>/dev/null)
  echo "Version: $version"
  echo "Data Dir: $datadir"
  mariadb_db_sizes
  mariadb_show_config
  mariadb_innodb_status
}


mariadb_memory() {
  echo "---- MariaDB Memory ----"
  [ -z "$MARIADB_CMD" ] && { echo "mariadb command not found"; return; }
  $MARIADB_CMD -N -e "SHOW VARIABLES LIKE 'innodb_buffer_pool_size';" 2>/dev/null
}

mariadb_show_config() {
  echo "---- MariaDB Configuration ----"
  [ -z "$MARIADB_CMD" ] && { echo "mariadb command not found"; return; }
  $MARIADB_CMD -e 'SHOW GLOBAL VARIABLES;' 2>/dev/null | head -n 20
}

mariadb_db_sizes() {
  echo "---- MariaDB Database Sizes ----"
  [ -z "$MARIADB_CMD" ] && { echo "mariadb command not found"; return; }
  $MARIADB_CMD -N -e "SELECT table_schema, ROUND(SUM(data_length+index_length)/1024/1024,2) AS size_mb FROM information_schema.tables GROUP BY table_schema;" 2>/dev/null
}

mariadb_innodb_status() {
  echo "---- MariaDB InnoDB Status ----"
  [ -z "$MARIADB_CMD" ] && { echo "mariadb command not found"; return; }
  $MARIADB_CMD -e 'SHOW ENGINE INNODB STATUS\G' 2>/dev/null | head -n 20
}

mariadb_cluster_status() {
  echo "---- MariaDB Cluster Status ----"
  [ -z "$MARIADB_CMD" ] && { echo "mariadb command not found"; return; }
  echo "Galera Cluster:"
  $MARIADB_CMD -e "SHOW STATUS LIKE 'wsrep%';" 2>/dev/null | grep -E "(wsrep_cluster_size|wsrep_local_state_comment|wsrep_ready|wsrep_cluster_status)" | sed 's/^/  /' || echo "  Not a Galera cluster"
  echo "Replication (if not Galera):"
  $MARIADB_CMD -e "SHOW SLAVE STATUS\G" 2>/dev/null | grep -E "(Slave_IO_State|Master_Host|Seconds_Behind_Master)" | sed 's/^/  /' || echo "  Not configured as slave"
}

mariadb_plugins() {
  echo "---- MariaDB Plugins ----"
  [ -z "$MARIADB_CMD" ] && { echo "mariadb command not found"; return; }
  $MARIADB_CMD -e "SELECT PLUGIN_NAME, PLUGIN_STATUS, PLUGIN_TYPE FROM information_schema.PLUGINS WHERE PLUGIN_STATUS='ACTIVE' ORDER BY PLUGIN_TYPE, PLUGIN_NAME;" 2>/dev/null | head -n 15 | sed 's/^/  /'
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
  $MARIADB_CMD -e "SELECT User, Host, account_locked, password_expired FROM mysql.user ORDER BY User;" 2>/dev/null | head -n 10 | sed 's/^/  /'
  echo "SSL Configuration:"
  $MARIADB_CMD -e "SHOW VARIABLES LIKE 'ssl%';" 2>/dev/null | sed 's/^/  /' || echo "  SSL variables not available"
  echo "Authentication Plugins:"
  $MARIADB_CMD -e "SELECT User, Host, plugin FROM mysql.user WHERE User != '' ORDER BY User;" 2>/dev/null | head -n 10 | sed 's/^/  /'
}

