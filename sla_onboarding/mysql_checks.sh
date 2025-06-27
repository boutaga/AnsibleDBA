#!/bin/bash
# MySQL specific checks

MYSQL_CMD="$(command -v mysql 2>/dev/null || true)"

mysql_summary() {
  echo "---- MySQL Summary ----"
  if [ -z "$MYSQL_CMD" ]; then
    echo "mysql command not found"; return
  fi
  local version=$($MYSQL_CMD -N -e 'SELECT VERSION();' 2>/dev/null)
  local datadir=$($MYSQL_CMD -N -e 'SELECT @@datadir;' 2>/dev/null)
  echo "Version: $version"
  echo "Data Dir: $datadir"
  mysql_db_sizes
  mysql_show_config
  mysql_innodb_status
}


mysql_memory() {
  echo "---- MySQL Memory ----"
  [ -z "$MYSQL_CMD" ] && { echo "mysql command not found"; return; }
  $MYSQL_CMD -N -e "SHOW VARIABLES LIKE 'innodb_buffer_pool_size';" 2>/dev/null
}

mysql_show_config() {
  echo "---- MySQL Configuration ----"
  [ -z "$MYSQL_CMD" ] && { echo "mysql command not found"; return; }
  $MYSQL_CMD -e 'SHOW GLOBAL VARIABLES;' 2>/dev/null | head -n 20
}

mysql_db_sizes() {
  echo "---- MySQL Database Sizes ----"
  [ -z "$MYSQL_CMD" ] && { echo "mysql command not found"; return; }
  $MYSQL_CMD -N -e "SELECT table_schema, ROUND(SUM(data_length+index_length)/1024/1024,2) AS size_mb FROM information_schema.tables GROUP BY table_schema;" 2>/dev/null
}

mysql_innodb_status() {
  echo "---- MySQL InnoDB Status ----"
  [ -z "$MYSQL_CMD" ] && { echo "mysql command not found"; return; }
  $MYSQL_CMD -e 'SHOW ENGINE INNODB STATUS\G' 2>/dev/null | head -n 20
}

mysql_users_security() {
  echo "---- MySQL Users & Security ----"
  [ -z "$MYSQL_CMD" ] && { echo "mysql command not found"; return; }
  echo "User Accounts:"
  $MYSQL_CMD -e "SELECT User, Host, account_locked, password_expired FROM mysql.user ORDER BY User;" 2>/dev/null | head -n 10
  echo "SSL Configuration:"
  $MYSQL_CMD -e "SHOW VARIABLES LIKE 'ssl%';" 2>/dev/null || echo "SSL variables not available"
  echo "Authentication Plugins:"
  $MYSQL_CMD -e "SELECT User, Host, plugin FROM mysql.user WHERE User != '' ORDER BY User;" 2>/dev/null | head -n 10
}

mysql_replication() {
  echo "---- MySQL Replication ----"
  [ -z "$MYSQL_CMD" ] && { echo "mysql command not found"; return; }
  echo "Master Status:"
  $MYSQL_CMD -e "SHOW MASTER STATUS;" 2>/dev/null || echo "Not a master or not configured"
  echo "Slave Status:"
  $MYSQL_CMD -e "SHOW SLAVE STATUS\G" 2>/dev/null | grep -E "(Slave_IO_State|Master_Host|Seconds_Behind_Master|Last_Error)" || echo "Not a slave or not configured"
  echo "Binary Logging:"
  $MYSQL_CMD -e "SHOW VARIABLES LIKE 'log_bin%';" 2>/dev/null
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
  $MYSQL_CMD -e "SHOW ENGINES;" 2>/dev/null | grep -E "(InnoDB|MyISAM|Memory|Archive|CSV)" | awk '{print $1, $2}' | sed 's/^/  /'
  echo "Default Storage Engine:"
  $MYSQL_CMD -e "SHOW VARIABLES LIKE 'default_storage_engine';" 2>/dev/null
}

