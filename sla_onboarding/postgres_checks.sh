#!/bin/bash
# PostgreSQL specific checks derived from pg_dbaOverview.sh

PG_BASE_DIRS=("/u02/pgdata" "/var/lib/postgresql")

pg_find_clusters() {
  local confs=()
  for d in "${PG_BASE_DIRS[@]}"; do
    [ -d "$d" ] && confs+=( $(find "$d" -type f -name postgresql.conf 2>/dev/null) )
  done
  printf '%s\n' "${confs[@]}"
}

pg_is_cluster_running() {
  local data_dir="$1"
  [ -f "$data_dir/postmaster.pid" ] && ps -p $(head -1 "$data_dir/postmaster.pid") >/dev/null 2>&1 && echo "online" || echo "down"
}

pg_get_port() {
  local dir="$1"
  if [ -f "$dir/postmaster.pid" ]; then
    sed -n '4p' "$dir/postmaster.pid" | xargs
  else
    grep -E '^port' "$dir/postgresql.conf" 2>/dev/null | awk -F= '{print $2}' | awk '{print $1}' | head -n1
  fi
}

pg_extract_version() {
  local dir="$1"
  if [[ "$dir" =~ /pgdata/([0-9]+)/ ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo "unknown"
  fi
}

pg_summary() {
  echo "---- PostgreSQL Summary ----"
  local confs
  mapfile -t confs < <(pg_find_clusters)
  for conf in "${confs[@]}"; do
    local dir=$(dirname "$conf")
    local name=$(basename "$dir")
    local status=$(pg_is_cluster_running "$dir")
    local port=$(pg_get_port "$dir")
    local version=$(pg_extract_version "$dir")
    echo "$name | version:$version | port:$port | status:$status"
  done
}

pg_memory() {
  echo "---- PostgreSQL Memory ----"
  local confs
  mapfile -t confs < <(pg_find_clusters)
  for conf in "${confs[@]}"; do
    local dir=$(dirname "$conf")
    local port=$(pg_get_port "$dir")
    local name=$(basename "$dir")
    if [ "$(pg_is_cluster_running "$dir")" = "online" ]; then
      echo "$name:"; psql -h localhost -p "$port" -d postgres -tAc "SHOW shared_buffers; SHOW work_mem;" 2>/dev/null
    else
      echo "$name is down"
    fi
  done
}

pg_disk() {
  echo "---- PostgreSQL Config Files ----"
  local confs
  mapfile -t confs < <(pg_find_clusters)
  for conf in "${confs[@]}"; do
    local dir=$(dirname "$conf")
    echo "$dir/postgresql.conf"
    [ -f "$dir/pg_hba.conf" ] && echo "$dir/pg_hba.conf"
  done
}

pg_replication() {
  echo "---- PostgreSQL Replication ----"
  local confs
  mapfile -t confs < <(pg_find_clusters)
  for conf in "${confs[@]}"; do
    local dir=$(dirname "$conf")
    local port=$(pg_get_port "$dir")
    local name=$(basename "$dir")
    if [ "$(pg_is_cluster_running "$dir")" = "online" ]; then
      echo "$name replication:"; psql -h localhost -p "$port" -d postgres -c "SELECT * FROM pg_stat_replication;" 2>/dev/null
    else
      echo "$name is down"
    fi
  done
}

pg_logs() {
  echo "---- PostgreSQL Logs ----"
  local confs
  mapfile -t confs < <(pg_find_clusters)
  for conf in "${confs[@]}"; do
    local dir=$(dirname "$conf")
    local port=$(pg_get_port "$dir")
    local name=$(basename "$dir")
    if [ -f "$dir/postmaster.pid" ]; then
      local log_dir=$(psql -h localhost -p "$port" -d postgres -Atc "SHOW log_directory" 2>/dev/null)
      local log_file=$(psql -h localhost -p "$port" -d postgres -Atc "SHOW log_filename" 2>/dev/null)
      log_dir=${log_dir:-$dir/pg_log}
      [ "${log_dir:0:1}" != "/" ] && log_dir="$dir/$log_dir"
      local full="$log_dir/$log_file"
      echo "$name log ($full):"; [ -f "$full" ] && tail -n 10 "$full"
    fi
  done
}

pg_db_sizes() {
  echo "---- PostgreSQL Database Sizes ----"
  local confs
  mapfile -t confs < <(pg_find_clusters)
  for conf in "${confs[@]}"; do
    local dir=$(dirname "$conf")
    local port=$(pg_get_port "$dir")
    local name=$(basename "$dir")
    if [ "$(pg_is_cluster_running "$dir")" = "online" ]; then
      echo "$name sizes:"; psql -h localhost -p "$port" -d postgres -Atc "SELECT datname, pg_size_pretty(pg_database_size(datname)) FROM pg_database;" 2>/dev/null
    else
      echo "$name is down"
    fi
  done
}

pg_config_files() {
  echo "---- PostgreSQL Configuration Files ----"
  local confs
  mapfile -t confs < <(pg_find_clusters)
  for conf in "${confs[@]}"; do
    local dir=$(dirname "$conf")
    local name=$(basename "$dir")
    echo "$name Config Files:"
    echo "  postgresql.conf: $conf ($(stat -c%Y "$conf" 2>/dev/null | xargs -I{} date -d @{} '+%Y-%m-%d %H:%M' || echo 'stat failed'))"
    [ -f "$dir/pg_hba.conf" ] && echo "  pg_hba.conf: $dir/pg_hba.conf ($(stat -c%Y "$dir/pg_hba.conf" 2>/dev/null | xargs -I{} date -d @{} '+%Y-%m-%d %H:%M' || echo 'stat failed'))"
    [ -f "$dir/pg_ident.conf" ] && echo "  pg_ident.conf: $dir/pg_ident.conf"
    [ -f "$dir/recovery.conf" ] && echo "  recovery.conf: $dir/recovery.conf"
    [ -f "$dir/postgresql.auto.conf" ] && echo "  postgresql.auto.conf: $dir/postgresql.auto.conf"
  done
}

pg_extensions() {
  echo "---- PostgreSQL Extensions ----"
  local confs
  mapfile -t confs < <(pg_find_clusters)
  for conf in "${confs[@]}"; do
    local dir=$(dirname "$conf")
    local port=$(pg_get_port "$dir")
    local name=$(basename "$dir")
    local status=$(pg_is_cluster_running "$dir")
    if [ "$status" = "online" ] && command -v psql >/dev/null; then
      echo "$name Extensions:"
      psql -h localhost -p "$port" -d postgres -c "SELECT name, default_version, installed_version FROM pg_available_extensions WHERE installed_version IS NOT NULL ORDER BY name;" 2>/dev/null || echo "  Unable to connect"
    else
      echo "$name: offline or psql not available"
    fi
  done
}

pg_users_databases() {
  echo "---- PostgreSQL Users & Databases ----"
  local confs
  mapfile -t confs < <(pg_find_clusters)
  for conf in "${confs[@]}"; do
    local dir=$(dirname "$conf")
    local port=$(pg_get_port "$dir")
    local name=$(basename "$dir")
    local status=$(pg_is_cluster_running "$dir")
    if [ "$status" = "online" ] && command -v psql >/dev/null; then
      echo "$name Databases:"
      psql -h localhost -p "$port" -d postgres -c "SELECT datname, pg_size_pretty(pg_database_size(datname)) as size FROM pg_database WHERE datname NOT IN ('template0','template1') ORDER BY pg_database_size(datname) DESC;" 2>/dev/null || echo "  Unable to connect"
      echo "$name Users:"
      psql -h localhost -p "$port" -d postgres -c "SELECT rolname, rolsuper, rolcreaterole, rolcreatedb, rolcanlogin FROM pg_roles WHERE rolname NOT LIKE 'pg_%' ORDER BY rolname;" 2>/dev/null || echo "  Unable to connect"
    else
      echo "$name: offline or psql not available"
    fi
  done
}

pg_backup_config() {
  echo "---- PostgreSQL Backup Configuration ----"
  local confs
  mapfile -t confs < <(pg_find_clusters)
  for conf in "${confs[@]}"; do
    local dir=$(dirname "$conf")
    local name=$(basename "$dir")
    echo "$name Backup Settings:"
    # Check WAL archiving
    grep -E '^archive_mode|^archive_command|^wal_level' "$conf" 2>/dev/null | sed 's/^/  /' || echo "  No archive settings found"
    # Check for common backup directories
    for backup_dir in "/backup" "/var/backups" "/opt/backup" "$dir/backup" "/backups"; do
      if [ -d "$backup_dir" ]; then
        echo "  Backup directory found: $backup_dir"
        ls -la "$backup_dir" 2>/dev/null | head -3 | sed 's/^/    /'
      fi
    done
    # Check for backup scripts
    for script in "/usr/local/bin/pg_backup.sh" "/opt/backup/pg_backup.sh" "$dir/backup.sh"; do
      [ -f "$script" ] && echo "  Backup script found: $script"
    done
  done
}

