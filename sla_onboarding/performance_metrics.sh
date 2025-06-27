#!/bin/bash
# Performance Metrics Collection for Database Assessment
# Focuses on key performance indicators relevant to Service Desk intervention timing

# PostgreSQL Performance Metrics
pg_performance_metrics() {
    echo "=== PostgreSQL Performance Metrics ==="
    
    # Get database connection info
    local conn_info=$(get_pg_connection_info)
    if [ -z "$conn_info" ]; then
        echo "Performance metrics: Unable to connect to PostgreSQL"
        return 1
    fi
    
    # Database activity and connections
    echo "--- Database Activity ---"
    safe_postgres_exec "psql $conn_info -t -c \"
        SELECT 'Active Connections|' || count(*) 
        FROM pg_stat_activity 
        WHERE state = 'active';\"" "active connections count" 15
    
    safe_postgres_exec "psql $conn_info -t -c \"
        SELECT 'Total Connections|' || count(*) 
        FROM pg_stat_activity;\"" "total connections count" 15
    
    safe_postgres_exec "psql $conn_info -t -c \"
        SELECT 'Max Connections|' || setting 
        FROM pg_settings 
        WHERE name = 'max_connections';\"" "max connections setting" 15
    
    # Long running queries
    echo "--- Query Performance ---"
    safe_postgres_exec "psql $conn_info -t -c \"
        SELECT 'Long Running Queries (>5min)|' || count(*) 
        FROM pg_stat_activity 
        WHERE state = 'active' 
        AND now() - query_start > interval '5 minutes';\"" "long running queries" 15
        
    # Top wait events
    safe_postgres_exec "psql $conn_info -t -c \"
        SELECT 'Top Wait Event|' || coalesce(wait_event, 'CPU') || ' (' || count(*) || ' sessions)'
        FROM pg_stat_activity 
        WHERE state = 'active'
        GROUP BY wait_event 
        ORDER BY count(*) DESC 
        LIMIT 1;\"" "top wait events" 15
    
    # Database sizes and activity
    echo "--- Database Performance Stats ---"
    safe_postgres_exec "psql $conn_info -t -c \"
        SELECT 'Database with Most Activity|' || datname || ' (' || xact_commit + xact_rollback || ' transactions)'
        FROM pg_stat_database 
        WHERE datname NOT IN ('template0', 'template1') 
        ORDER BY xact_commit + xact_rollback DESC 
        LIMIT 1;\"" "most active database" 15
    
    # Replication lag if applicable
    if safe_postgres_exec "psql $conn_info -t -c \"SELECT count(*) FROM pg_stat_replication;\"" "replication check" 10 | grep -q "1"; then
        echo "--- Replication Performance ---"
        safe_postgres_exec "psql $conn_info -t -c \"
            SELECT 'Replication Lag|' || 
            CASE WHEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn() 
            THEN 'Up to date' 
            ELSE extract(epoch from now() - pg_last_xact_replay_timestamp())::text || ' seconds'
            END;\"" "replication lag" 15
    fi
    
    # Cache hit ratio
    safe_postgres_exec "psql $conn_info -t -c \"
        SELECT 'Cache Hit Ratio|' || round(100.0 * sum(blks_hit) / sum(blks_hit + blks_read), 2) || '%'
        FROM pg_stat_database 
        WHERE blks_read > 0;\"" "cache hit ratio" 15
    
    echo ""
}

# MySQL Performance Metrics  
mysql_performance_metrics() {
    echo "=== MySQL Performance Metrics ==="
    
    # Get MySQL connection info
    local mysql_cmd=$(get_mysql_connection_cmd)
    if [ -z "$mysql_cmd" ]; then
        echo "Performance metrics: Unable to connect to MySQL"
        return 1
    fi
    
    # Connection and thread information
    echo "--- Connection Performance ---"
    safe_mysql_exec "$mysql_cmd -e \"
        SELECT CONCAT('Active Connections|', COUNT(*)) 
        FROM INFORMATION_SCHEMA.PROCESSLIST 
        WHERE COMMAND != 'Sleep';\"" "active connections" 15
    
    safe_mysql_exec "$mysql_cmd -e \"
        SELECT CONCAT('Total Connections|', COUNT(*)) 
        FROM INFORMATION_SCHEMA.PROCESSLIST;\"" "total connections" 15
    
    safe_mysql_exec "$mysql_cmd -e \"
        SHOW VARIABLES LIKE 'max_connections';\" | 
        awk 'NR==2 {print \"Max Connections|\" \$2}'" "max connections" 15
    
    # Performance schema queries (if available)
    echo "--- Query Performance ---"
    if safe_mysql_exec "$mysql_cmd -e \"SELECT 1 FROM performance_schema.events_statements_summary_by_digest LIMIT 1;\"" "performance schema check" 10; then
        safe_mysql_exec "$mysql_cmd -e \"
            SELECT CONCAT('Slow Queries (>5s)|', COUNT(*)) 
            FROM performance_schema.events_statements_summary_by_digest 
            WHERE AVG_TIMER_WAIT > 5000000000000;\"" "slow queries count" 15
        
        safe_mysql_exec "$mysql_cmd -e \"
            SELECT CONCAT('Top Query Type|', 
                SUBSTRING_INDEX(DIGEST_TEXT, ' ', 1), 
                ' (', COUNT(*), ' queries)')
            FROM performance_schema.events_statements_summary_by_digest 
            GROUP BY SUBSTRING_INDEX(DIGEST_TEXT, ' ', 1)
            ORDER BY COUNT(*) DESC 
            LIMIT 1;\"" "top query type" 15
    else
        # Fallback to show processlist for query analysis
        safe_mysql_exec "$mysql_cmd -e \"
            SELECT CONCAT('Long Running Queries (>300s)|', 
                COUNT(*)) 
            FROM INFORMATION_SCHEMA.PROCESSLIST 
            WHERE COMMAND NOT IN ('Sleep', 'Binlog Dump') 
            AND TIME > 300;\"" "long running queries" 15
    fi
    
    # InnoDB metrics
    echo "--- Storage Engine Performance ---"
    safe_mysql_exec "$mysql_cmd -e \"
        SHOW ENGINE INNODB STATUS\\G\" | 
        awk '/BUFFER POOL AND MEMORY/ {flag=1} 
             flag && /Buffer pool hit rate/ {print \"InnoDB Hit Rate|\" \$5 \" \" \$6 \" \" \$7; flag=0}'" "innodb hit rate" 15
    
    # Replication status
    if safe_mysql_exec "$mysql_cmd -e \"SHOW SLAVE STATUS\\G\"" "replication check" 10 | grep -q "Master_Host"; then
        echo "--- Replication Performance ---"  
        safe_mysql_exec "$mysql_cmd -e \"
            SELECT CONCAT('Replication Lag|', 
                CASE WHEN Seconds_Behind_Master IS NULL 
                THEN 'Not replicating' 
                ELSE CONCAT(Seconds_Behind_Master, ' seconds')
                END) 
            FROM INFORMATION_SCHEMA.REPLICA_HOST_STATUS;\"" "replication lag" 15 2>/dev/null ||
        safe_mysql_exec "$mysql_cmd -e \"SHOW SLAVE STATUS\\G\" | 
            awk '/Seconds_Behind_Master:/ {print \"Replication Lag|\" \$2 \" seconds\"}'" "replication lag fallback" 15
    fi
    
    echo ""
}

# MariaDB Performance Metrics
mariadb_performance_metrics() {
    echo "=== MariaDB Performance Metrics ==="
    
    # Get MariaDB connection info
    local mariadb_cmd=$(get_mariadb_connection_cmd)
    if [ -z "$mariadb_cmd" ]; then
        echo "Performance metrics: Unable to connect to MariaDB"
        return 1
    fi
    
    # Connection performance
    echo "--- Connection Performance ---"
    safe_mariadb_exec "$mariadb_cmd -e \"
        SELECT CONCAT('Active Connections|', COUNT(*)) 
        FROM INFORMATION_SCHEMA.PROCESSLIST 
        WHERE COMMAND != 'Sleep';\"" "active connections" 15
    
    safe_mariadb_exec "$mariadb_cmd -e \"
        SELECT CONCAT('Total Connections|', COUNT(*)) 
        FROM INFORMATION_SCHEMA.PROCESSLIST;\"" "total connections" 15
    
    # Galera cluster performance (if applicable)
    if safe_mariadb_exec "$mariadb_cmd -e \"SHOW STATUS LIKE 'wsrep_cluster_size';\"" "galera check" 10 | grep -q "wsrep_cluster_size"; then
        echo "--- Galera Cluster Performance ---"
        safe_mariadb_exec "$mariadb_cmd -e \"
            SELECT CONCAT('Cluster Size|', VARIABLE_VALUE) 
            FROM INFORMATION_SCHEMA.GLOBAL_STATUS 
            WHERE VARIABLE_NAME = 'wsrep_cluster_size';\"" "cluster size" 15
        
        safe_mariadb_exec "$mariadb_cmd -e \"
            SELECT CONCAT('Cluster Status|', VARIABLE_VALUE) 
            FROM INFORMATION_SCHEMA.GLOBAL_STATUS 
            WHERE VARIABLE_NAME = 'wsrep_cluster_status';\"" "cluster status" 15
        
        safe_mariadb_exec "$mariadb_cmd -e \"
            SELECT CONCAT('Replication Queue|', VARIABLE_VALUE, ' events') 
            FROM INFORMATION_SCHEMA.GLOBAL_STATUS 
            WHERE VARIABLE_NAME = 'wsrep_local_recv_queue_avg';\"" "replication queue" 15
    fi
    
    # Query performance
    echo "--- Query Performance ---"
    safe_mariadb_exec "$mariadb_cmd -e \"
        SELECT CONCAT('Long Running Queries (>300s)|', 
            COUNT(*)) 
        FROM INFORMATION_SCHEMA.PROCESSLIST 
        WHERE COMMAND NOT IN ('Sleep', 'Binlog Dump') 
        AND TIME > 300;\"" "long running queries" 15
    
    # InnoDB performance
    echo "--- Storage Performance ---"
    safe_mariadb_exec "$mariadb_cmd -e \"
        SELECT CONCAT('InnoDB Buffer Pool Usage|', 
            ROUND(100 * (
                (SELECT VARIABLE_VALUE FROM INFORMATION_SCHEMA.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Innodb_buffer_pool_pages_data') /
                (SELECT VARIABLE_VALUE FROM INFORMATION_SCHEMA.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Innodb_buffer_pool_pages_total')
            ), 2), '%');\"" "buffer pool usage" 15
    
    echo ""
}

# Helper functions to get connection info
get_pg_connection_info() {
    # Try different connection methods
    for method in "-U postgres" "-h localhost -U postgres" ""; do
        if safe_postgres_exec "psql $method -c 'SELECT 1;'" "connection test" 5; then
            echo "$method"
            return 0
        fi
    done
    return 1
}

get_mysql_connection_cmd() {
    # Try different connection methods
    for method in "mysql" "mysql -u root" "mysql -h localhost"; do
        if safe_mysql_exec "$method -e 'SELECT 1;'" "connection test" 5; then
            echo "$method"
            return 0
        fi
    done
    return 1
}

get_mariadb_connection_cmd() {
    # Try different connection methods  
    for method in "mariadb" "mariadb -u root" "mysql" "mysql -u root"; do
        if safe_mariadb_exec "$method -e 'SELECT 1;'" "connection test" 5; then
            echo "$method"
            return 0
        fi
    done
    return 1
}

# System performance metrics
system_performance_metrics() {
    echo "=== System Performance Metrics ==="
    
    # CPU usage
    echo "--- CPU Performance ---"
    if command -v top >/dev/null 2>&1; then
        local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')
        echo "CPU Usage|${cpu_usage}% user"
    fi
    
    # Memory usage
    echo "--- Memory Performance ---"
    if command -v free >/dev/null 2>&1; then
        local mem_info=$(free -h | awk 'NR==2{printf "Memory Usage|%s/%s (%.2f%%)", $3,$2,$3/$2*100}')
        echo "$mem_info"
    fi
    
    # Disk I/O
    echo "--- Disk Performance ---"
    if command -v iostat >/dev/null 2>&1; then
        iostat -x 1 2 | awk 'END {if(NF>0) print "Disk Utilization|" $10 "%"}' 2>/dev/null
    elif command -v vmstat >/dev/null 2>&1; then
        local io_wait=$(vmstat 1 2 | tail -1 | awk '{print $16}')
        echo "I/O Wait|${io_wait}%"
    fi
    
    # Load average
    if command -v uptime >/dev/null 2>&1; then
        local load_avg=$(uptime | awk -F'load average:' '{print $2}')
        echo "Load Average|$load_avg"
    fi
    
    echo ""
}