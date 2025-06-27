#!/bin/bash
# Backup Validation Module for Database Assessment
# Goes beyond configuration detection to validate backup functionality

# PostgreSQL Backup Validation
pg_backup_validation() {
    echo "=== PostgreSQL Backup Validation ==="
    
    local conn_info=$(get_pg_connection_info)
    if [ -z "$conn_info" ]; then
        echo "Backup validation: Unable to connect to PostgreSQL"
        return 1
    fi
    
    # Check WAL archiving status
    echo "--- WAL Archiving ---"
    safe_postgres_exec "psql $conn_info -t -c \"
        SELECT 'Archive Mode|' || 
        CASE WHEN setting = 'on' THEN 'Enabled' ELSE 'Disabled' END
        FROM pg_settings WHERE name = 'archive_mode';\"" "archive mode check" 15
    
    safe_postgres_exec "psql $conn_info -t -c \"
        SELECT 'Archive Command|' || setting
        FROM pg_settings WHERE name = 'archive_command';\"" "archive command check" 15
    
    # Check WAL archive status
    safe_postgres_exec "psql $conn_info -t -c \"
        SELECT 'Last Archived WAL|' || 
        coalesce(last_archived_wal, 'None') || 
        ' (Time: ' || coalesce(last_archived_time::text, 'Unknown') || ')'
        FROM pg_stat_archiver;\"" "last archived wal" 15
    
    safe_postgres_exec "psql $conn_info -t -c \"
        SELECT 'Failed Archive Attempts|' || failed_count
        FROM pg_stat_archiver;\"" "failed archive count" 15
    
    # Validate backup directories and files
    echo "--- Backup File Validation ---"
    validate_postgres_backup_files "$conn_info"
    
    # Check for common backup tools
    echo "--- Backup Tools Detection ---"
    check_postgres_backup_tools
    
    # Point-in-time recovery readiness
    echo "--- PITR Readiness ---"
    validate_postgres_pitr_setup "$conn_info"
    
    echo ""
}

# MySQL Backup Validation
mysql_backup_validation() {
    echo "=== MySQL Backup Validation ==="
    
    local mysql_cmd=$(get_mysql_connection_cmd)
    if [ -z "$mysql_cmd" ]; then
        echo "Backup validation: Unable to connect to MySQL"
        return 1
    fi
    
    # Check binary logging
    echo "--- Binary Logging ---"
    safe_mysql_exec "$mysql_cmd -e \"
        SELECT CONCAT('Binary Logging|', 
        CASE WHEN @@log_bin = 1 THEN 'Enabled' ELSE 'Disabled' END);\"" "binary logging status" 15
    
    if safe_mysql_exec "$mysql_cmd -e \"SELECT @@log_bin;\"" "binlog check" 10 | grep -q "1"; then
        safe_mysql_exec "$mysql_cmd -e \"
            SHOW VARIABLES LIKE 'log_bin_basename';\" | 
            awk 'NR==2 {print \"Binary Log Path|\" \$2}'" "binary log path" 15
        
        # Check binary log retention
        safe_mysql_exec "$mysql_cmd -e \"
            SELECT CONCAT('Binary Log Retention|', @@binlog_expire_logs_seconds, ' seconds')
            WHERE @@binlog_expire_logs_seconds > 0
            UNION SELECT 'Binary Log Retention|Manual cleanup required'
            WHERE @@binlog_expire_logs_seconds = 0;\"" "binlog retention" 15
    fi
    
    # Validate backup files and directories
    echo "--- Backup File Validation ---"
    validate_mysql_backup_files "$mysql_cmd"
    
    # Check for backup tools
    echo "--- Backup Tools Detection ---"
    check_mysql_backup_tools
    
    # Validate backup consistency
    echo "--- Backup Consistency Checks ---"
    validate_mysql_backup_consistency "$mysql_cmd"
    
    echo ""
}

# MariaDB Backup Validation
mariadb_backup_validation() {
    echo "=== MariaDB Backup Validation ==="
    
    local mariadb_cmd=$(get_mariadb_connection_cmd)
    if [ -z "$mariadb_cmd" ]; then
        echo "Backup validation: Unable to connect to MariaDB"
        return 1
    fi
    
    # Check binary logging
    echo "--- Binary Logging ---"  
    safe_mariadb_exec "$mariadb_cmd -e \"
        SELECT CONCAT('Binary Logging|', 
        CASE WHEN @@log_bin = 1 THEN 'Enabled' ELSE 'Disabled' END);\"" "binary logging status" 15
    
    # Galera-specific backup considerations
    if safe_mariadb_exec "$mariadb_cmd -e \"SHOW STATUS LIKE 'wsrep_cluster_size';\"" "galera check" 10 | grep -q "wsrep_cluster_size"; then
        echo "--- Galera Backup Considerations ---"
        safe_mariadb_exec "$mariadb_cmd -e \"
            SELECT CONCAT('Galera State Transfer|', VARIABLE_VALUE) 
            FROM INFORMATION_SCHEMA.GLOBAL_STATUS 
            WHERE VARIABLE_NAME = 'wsrep_local_state_comment';\"" "galera state" 15
        
        # Check for donor/desyncing capabilities
        safe_mariadb_exec "$mariadb_cmd -e \"
            SELECT CONCAT('Desync Capability|', 
            CASE WHEN @@wsrep_desync = 'OFF' THEN 'Available' ELSE 'In Use' END);\"" "desync status" 15
    fi
    
    # MariaDB-specific backup tools
    echo "--- Backup Tools Detection ---"
    check_mariadb_backup_tools
    
    # Validate backup files
    echo "--- Backup File Validation ---"
    validate_mariadb_backup_files "$mariadb_cmd"
    
    echo ""
}

# PostgreSQL backup file validation
validate_postgres_backup_files() {
    local conn_info="$1"
    
    # Get data directory
    local data_dir=$(safe_postgres_exec "psql $conn_info -t -c \"SHOW data_directory;\"" "data directory" 10 2>/dev/null | tr -d ' ')
    
    if [ -n "$data_dir" ] && [ -d "$data_dir" ]; then
        echo "Data Directory|$data_dir"
        
        # Check for base backups
        local backup_dirs=(
            "$data_dir/base_backups"
            "/var/lib/postgresql/backups"
            "/backup/postgresql"
            "/opt/backup/postgresql"
        )
        
        for backup_dir in "${backup_dirs[@]}"; do
            if [ -d "$backup_dir" ]; then
                local backup_count=$(find "$backup_dir" -type f -name "*.tar*" -o -name "backup_label*" 2>/dev/null | wc -l)
                echo "Backup Files in $backup_dir|$backup_count files found"
                
                # Check backup age
                local latest_backup=$(find "$backup_dir" -type f -exec stat -f "%m %N" {} \; 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)
                if [ -n "$latest_backup" ]; then
                    local backup_age=$(( ($(date +%s) - $(stat -f "%m" "$latest_backup" 2>/dev/null || echo "0")) / 3600 ))
                    echo "Latest Backup Age|$backup_age hours ago"
                fi
            fi
        done
        
        # Check WAL archive directory
        local archive_command=$(safe_postgres_exec "psql $conn_info -t -c \"SELECT setting FROM pg_settings WHERE name = 'archive_command';\"" "archive command" 10 2>/dev/null)
        if [[ "$archive_command" =~ /([^[:space:]]+) ]]; then
            local archive_dir=$(dirname "${BASH_REMATCH[1]}")
            if [ -d "$archive_dir" ]; then
                local wal_count=$(find "$archive_dir" -name "*.wal" -o -name "*[0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]" 2>/dev/null | wc -l)
                echo "WAL Archive Files|$wal_count files in $archive_dir"
            fi
        fi
    else
        echo "Data Directory|Unable to determine or access"
    fi
}

# MySQL backup file validation
validate_mysql_backup_files() {
    local mysql_cmd="$1"
    
    # Get data directory
    local data_dir=$(safe_mysql_exec "$mysql_cmd -e \"SELECT @@datadir;\"" "data directory" 10 2>/dev/null | tail -1)
    
    if [ -n "$data_dir" ] && [ -d "$data_dir" ]; then
        echo "Data Directory|$data_dir"
        
        # Common backup locations
        local backup_dirs=(
            "/var/backups/mysql"
            "/backup/mysql"
            "/opt/backup/mysql"
            "$(dirname "$data_dir")/backups"
        )
        
        for backup_dir in "${backup_dirs[@]}"; do
            if [ -d "$backup_dir" ]; then
                local backup_count=$(find "$backup_dir" -type f -name "*.sql*" -o -name "*.dump*" 2>/dev/null | wc -l)
                echo "Backup Files in $backup_dir|$backup_count files found"
                
                # Check backup freshness
                local latest_backup=$(find "$backup_dir" -type f -name "*.sql*" -o -name "*.dump*" -exec stat -c "%Y %n" {} \; 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)
                if [ -n "$latest_backup" ]; then
                    local backup_age=$(( ($(date +%s) - $(stat -c "%Y" "$latest_backup" 2>/dev/null || echo "0")) / 3600 ))
                    echo "Latest Backup Age|$backup_age hours ago"
                fi
            fi
        done
        
        # Check binary log directory
        if safe_mysql_exec "$mysql_cmd -e \"SELECT @@log_bin;\"" "binlog check" 10 | grep -q "1"; then
            local binlog_dir=$(safe_mysql_exec "$mysql_cmd -e \"SELECT @@log_bin_basename;\"" "binlog path" 10 2>/dev/null | tail -1)
            if [ -n "$binlog_dir" ]; then
                binlog_dir=$(dirname "$binlog_dir")
                if [ -d "$binlog_dir" ]; then
                    local binlog_count=$(find "$binlog_dir" -name "*.bin" 2>/dev/null | wc -l)
                    echo "Binary Log Files|$binlog_count files in $binlog_dir"
                fi
            fi
        fi
    else
        echo "Data Directory|Unable to determine or access"
    fi
}

# MariaDB backup file validation
validate_mariadb_backup_files() {
    local mariadb_cmd="$1"
    
    # Similar to MySQL but with MariaDB-specific considerations
    validate_mysql_backup_files "$mariadb_cmd"
    
    # Check for Galera state snapshots
    if safe_mariadb_exec "$mariadb_cmd -e \"SHOW STATUS LIKE 'wsrep_cluster_size';\"" "galera check" 10 | grep -q "wsrep_cluster_size"; then
        local data_dir=$(safe_mariadb_exec "$mariadb_cmd -e \"SELECT @@datadir;\"" "data directory" 10 2>/dev/null | tail -1)
        if [ -n "$data_dir" ] && [ -d "$data_dir" ]; then
            # Look for Galera state transfer files
            local sst_files=$(find "$data_dir" -name "*.sst*" -o -name "galera.*" 2>/dev/null | wc -l)
            if [ "$sst_files" -gt 0 ]; then
                echo "Galera SST Files|$sst_files state transfer files found"
            fi
        fi
    fi
}

# Check for backup tools
check_postgres_backup_tools() {
    local tools=("pg_dump" "pg_dumpall" "pg_basebackup" "barman" "pgbackrest" "wal-g")
    
    for tool in "${tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            local version=$(timeout 5 "$tool" --version 2>/dev/null | head -1 || echo "Unknown version")
            echo "Backup Tool Found|$tool ($version)"
        fi
    done
    
    # Check for cron jobs
    if command -v crontab >/dev/null 2>&1; then
        local cron_backups=$(crontab -l 2>/dev/null | grep -i "pg_dump\|pg_basebackup\|barman\|pgbackrest" | wc -l)
        echo "Scheduled Backup Jobs|$cron_backups cron entries found"
    fi
}

check_mysql_backup_tools() {
    local tools=("mysqldump" "mysqlhotcopy" "xtrabackup" "mariabackup" "mydumper")
    
    for tool in "${tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            local version=$(timeout 5 "$tool" --version 2>/dev/null | head -1 || echo "Unknown version")
            echo "Backup Tool Found|$tool ($version)"
        fi
    done
    
    # Check for backup scripts
    if command -v crontab >/dev/null 2>&1; then
        local cron_backups=$(crontab -l 2>/dev/null | grep -i "mysqldump\|xtrabackup\|mydumper" | wc -l)
        echo "Scheduled Backup Jobs|$cron_backups cron entries found"
    fi
}

check_mariadb_backup_tools() {
    local tools=("mariabackup" "mysqldump" "mydumper" "xtrabackup")
    
    for tool in "${tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            local version=$(timeout 5 "$tool" --version 2>/dev/null | head -1 || echo "Unknown version")
            echo "Backup Tool Found|$tool ($version)"
        fi
    done
    
    # Check for Galera-specific backup considerations
    if systemctl is-active mariadb >/dev/null 2>&1; then
        if systemctl show mariadb.service -p Environment | grep -q "wsrep"; then
            echo "Galera Backup Config|Cluster-aware backup configuration detected"
        fi
    fi
}

# PostgreSQL PITR validation
validate_postgres_pitr_setup() {
    local conn_info="$1"
    
    # Check if WAL archiving is properly configured for PITR
    local archive_mode=$(safe_postgres_exec "psql $conn_info -t -c \"SELECT setting FROM pg_settings WHERE name = 'archive_mode';\"" "archive mode" 10 2>/dev/null)
    local wal_level=$(safe_postgres_exec "psql $conn_info -t -c \"SELECT setting FROM pg_settings WHERE name = 'wal_level';\"" "wal level" 10 2>/dev/null)
    
    if [[ "$archive_mode" =~ on ]] && [[ "$wal_level" =~ (replica|logical) ]]; then
        echo "PITR Capability|Properly configured for Point-in-Time Recovery"
        
        # Check recovery configuration
        local data_dir=$(safe_postgres_exec "psql $conn_info -t -c \"SHOW data_directory;\"" "data directory" 10 2>/dev/null | tr -d ' ')
        if [ -n "$data_dir" ] && [ -f "$data_dir/recovery.conf" -o -f "$data_dir/postgresql.auto.conf" ]; then
            echo "Recovery Configuration|Recovery configuration files present"
        else
            echo "Recovery Configuration|Recovery templates available but not configured"
        fi
    else
        echo "PITR Capability|Not properly configured (archive_mode: $archive_mode, wal_level: $wal_level)"
    fi
}

# MySQL backup consistency validation
validate_mysql_backup_consistency() {
    local mysql_cmd="$1"
    
    # Check for consistent backup indicators
    echo "--- Backup Consistency ---"
    
    # Check for GTID consistency (MySQL 5.6+)
    if safe_mysql_exec "$mysql_cmd -e \"SELECT @@gtid_mode;\"" "gtid check" 10 2>/dev/null | grep -qi "on"; then
        echo "GTID Mode|Enabled (supports consistent backups)"
        
        # Get current GTID position
        safe_mysql_exec "$mysql_cmd -e \"
            SELECT CONCAT('Current GTID Position|', @@gtid_executed);\"" "gtid position" 15
    else
        echo "GTID Mode|Disabled (using binary log positions)"
        
        # Get current binary log position
        safe_mysql_exec "$mysql_cmd -e \"
            SHOW MASTER STATUS;\" | 
            awk 'NR==2 {print \"Binary Log Position|\" \$1 \":\" \$2}'" "binlog position" 15
    fi
    
    # Check for InnoDB consistency
    safe_mysql_exec "$mysql_cmd -e \"
        SELECT CONCAT('InnoDB Recovery Mode|', 
        CASE WHEN @@innodb_force_recovery = 0 
        THEN 'Normal (consistent)' 
        ELSE CONCAT('Recovery mode ', @@innodb_force_recovery)
        END);\"" "innodb recovery mode" 15
}