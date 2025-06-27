#!/bin/bash
# PostgreSQL specific checks derived from pg_dbaOverview.sh

# Dynamic discovery of PostgreSQL installations
pg_find_clusters() {
  local confs=()
  
  # Method 1: Find running PostgreSQL processes and their data directories
  if command -v ps >/dev/null 2>&1; then
    local running_datadirs=$(ps aux | grep -E 'postgres.*-D' | grep -v grep | sed -n 's/.*-D \([^ ]*\).*/\1/p' | sort -u)
    for datadir in $running_datadirs; do
      [ -f "$datadir/postgresql.conf" ] && confs+=("$datadir/postgresql.conf")
    done
  fi
  
  # Method 2: Check systemd service files for custom paths
  if command -v systemctl >/dev/null 2>&1; then
    local services=$(systemctl list-units --type=service | grep postgres | awk '{print $1}')
    for service in $services; do
      local datadir=$(systemctl show "$service" -p Environment | grep -o 'PGDATA=[^[:space:]]*' | cut -d= -f2)
      [ -n "$datadir" ] && [ -f "$datadir/postgresql.conf" ] && confs+=("$datadir/postgresql.conf")
    done
  fi
  
  # Method 3: Standard locations as fallback
  local standard_dirs=("/var/lib/postgresql" "/usr/local/pgsql" "/opt/postgresql" "/u01/pgdata" "/u02/pgdata")
  for d in "${standard_dirs[@]}"; do
    [ -d "$d" ] && confs+=( $(find "$d" -type f -name postgresql.conf 2>/dev/null) )
  done
  
  # Method 4: Check common PostgreSQL binary locations and ask them
  local pg_binaries=("/usr/bin/postgres" "/usr/local/bin/postgres" "/opt/postgresql/bin/postgres" "/u01/app/postgresql/bin/postgres")
  for binary in "${pg_binaries[@]}"; do
    if [ -x "$binary" ]; then
      # Try to get default data directory from binary
      local default_datadir=$("$binary" --help 2>/dev/null | grep -E 'default.*data.*directory' | sed -n 's/.*default.*data.*directory.*\([^[:space:]]*\).*/\1/p')
      [ -n "$default_datadir" ] && [ -f "$default_datadir/postgresql.conf" ] && confs+=("$default_datadir/postgresql.conf")
    fi
  done
  
  # Remove duplicates and print
  printf '%s\n' "${confs[@]}" | sort -u
}

pg_is_cluster_running() {
  local data_dir="$1"
  [ -f "$data_dir/postmaster.pid" ] && ps -p $(head -1 "$data_dir/postmaster.pid") >/dev/null 2>&1 && echo "online" || echo "down"
}

pg_get_port() {
  local dir="$1"
  local port=""
  
  # First try to get port from running instance
  if [ -f "$dir/postmaster.pid" ]; then
    port=$(sed -n '4p' "$dir/postmaster.pid" 2>/dev/null | xargs)
  fi
  
  # Fallback to config file
  if [ -z "$port" ] || [ "$port" = "" ]; then
    port=$(grep -E '^port' "$dir/postgresql.conf" 2>/dev/null | awk -F= '{print $2}' | awk '{print $1}' | head -n1)
  fi
  
  # Default fallback
  echo "${port:-5432}"
}

pg_get_runtime_paths() {
  local port="$1"
  local paths=""
  
  # Try to connect and get actual runtime paths
  if command -v psql >/dev/null; then
    # Try as current user first, then as postgres user
    local conn_string="host=localhost port=$port dbname=postgres"
    
    paths=$(psql "$conn_string" -t -c "
      SELECT 
        'data_directory: ' || setting FROM pg_settings WHERE name = 'data_directory'
      UNION ALL
      SELECT 
        'config_file: ' || setting FROM pg_settings WHERE name = 'config_file'
      UNION ALL
      SELECT 
        'hba_file: ' || setting FROM pg_settings WHERE name = 'hba_file'
      UNION ALL
      SELECT 
        'ident_file: ' || setting FROM pg_settings WHERE name = 'ident_file'
      UNION ALL
      SELECT 
        'log_directory: ' || setting FROM pg_settings WHERE name = 'log_directory'
      UNION ALL
      SELECT 
        'log_filename: ' || setting FROM pg_settings WHERE name = 'log_filename'
      UNION ALL
      SELECT 
        'archive_command: ' || setting FROM pg_settings WHERE name = 'archive_command'
    " 2>/dev/null || \
    sudo -u postgres psql "$conn_string" -t -c "
      SELECT 
        'data_directory: ' || setting FROM pg_settings WHERE name = 'data_directory'
      UNION ALL
      SELECT 
        'config_file: ' || setting FROM pg_settings WHERE name = 'config_file'
      UNION ALL
      SELECT 
        'hba_file: ' || setting FROM pg_settings WHERE name = 'hba_file'
      UNION ALL
      SELECT 
        'ident_file: ' || setting FROM pg_settings WHERE name = 'ident_file'
      UNION ALL
      SELECT 
        'log_directory: ' || setting FROM pg_settings WHERE name = 'log_directory'
      UNION ALL
      SELECT 
        'log_filename: ' || setting FROM pg_settings WHERE name = 'log_filename'
      UNION ALL
      SELECT 
        'archive_command: ' || setting FROM pg_settings WHERE name = 'archive_command'
    " 2>/dev/null)
  fi
  
  echo "$paths"
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
    
    # Get runtime paths if instance is running
    if [ "$status" = "online" ]; then
      echo "Runtime Paths:"
      pg_get_runtime_paths "$port" | sed 's/^/  /'
    fi
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

