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

