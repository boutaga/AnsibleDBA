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

