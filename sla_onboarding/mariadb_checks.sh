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

