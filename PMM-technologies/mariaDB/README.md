# MariaDB Custom Metrics for PMM 3.x

This directory contains custom metrics configuration for monitoring MariaDB databases with PMM (Percona Monitoring and Management) version 3.x.

## 📋 Overview

PMM 3.x uses the mysql_exporter to collect MariaDB metrics through custom YAML configuration files. These files define SQL queries that are executed periodically to gather specific metrics.

## 📁 Files

- `queries-mysqld.yml` - Custom MariaDB metrics configuration
- `README.md` - This documentation file

## 🚀 Installation

### Step 1: Copy Custom Metrics File

Copy the custom metrics file to the PMM collectors directory:

```bash
# For high-resolution metrics (collected every 5 seconds)
sudo cp queries-mysqld.yml /usr/local/percona/pmm2/collectors/custom-queries/mysql/high-resolution/

# For medium-resolution metrics (collected every 10 seconds)
sudo cp queries-mysqld.yml /usr/local/percona/pmm2/collectors/custom-queries/mysql/medium-resolution/

# For low-resolution metrics (collected every 60 seconds)
sudo cp queries-mysqld.yml /usr/local/percona/pmm2/collectors/custom-queries/mysql/low-resolution/
```

### Step 2: Set Proper Permissions

```bash
sudo chown pmm:pmm /usr/local/percona/pmm2/collectors/custom-queries/mysql/*/queries-mysqld.yml
sudo chmod 644 /usr/local/percona/pmm2/collectors/custom-queries/mysql/*/queries-mysqld.yml
```

### Step 3: Add MariaDB Instance to PMM

Add your MariaDB instance to PMM monitoring:

```bash
# Add MariaDB instance
sudo pmm-admin add mysql --username=pmm_user --password=pmm_password --host=localhost --port=3306 mariadb-instance

# For remote MariaDB instance
sudo pmm-admin add mysql --username=pmm_user --password=pmm_password --host=mariadb-server.example.com --port=3306 mariadb-remote
```

### Step 4: Restart PMM Agent

```bash
sudo systemctl restart pmm-agent
```

## 📊 Available Custom Metrics

### Table Statistics
- `mariadb_table_stats_table_rows` - Number of rows per table
- `mariadb_table_stats_data_length` - Data size in bytes per table
- `mariadb_table_stats_index_length` - Index size in bytes per table

### Connection Monitoring
- `mariadb_connection_stats_variable_value` - Connection statistics including:
  - Total connections
  - Max used connections
  - Current connected threads
  - Running threads
  - Aborted connections

### InnoDB Buffer Pool
- `mariadb_innodb_buffer_pool_variable_value` - Buffer pool utilization metrics

### Replication Monitoring
- `mariadb_slave_lag_seconds_behind_master` - Replication lag in seconds
- `mariadb_slave_lag_slave_io_running` - IO thread status
- `mariadb_slave_lag_slave_sql_running` - SQL thread status

### Query Performance
- `mariadb_query_response_time_count` - Query count by response time bucket
- `mariadb_query_response_time_total` - Total time for queries in bucket

### Binary Log Status
- `mariadb_binlog_status_position` - Current binary log position

### Galera Cluster (if applicable)
- `mariadb_galera_cluster_variable_value` - Galera cluster metrics including:
  - Cluster size
  - Local state
  - Ready status
  - Connection status

### Thread Pool (MariaDB specific)
- `mariadb_thread_pool_variable_value` - Thread pool statistics

### User Statistics
- `mariadb_user_statistics_total_connections` - Total connections per user
- `mariadb_user_statistics_concurrent_connections` - Current connections per user
- `mariadb_user_statistics_connected_time` - Connected time per user
- `mariadb_user_statistics_busy_time` - Busy time per user
- `mariadb_user_statistics_cpu_time` - CPU time per user

## 🔧 Configuration Requirements

### Database User Privileges

Create a monitoring user with appropriate privileges:

```sql
-- Create monitoring user
CREATE USER 'pmm_user'@'%' IDENTIFIED BY 'pmm_password';

-- Grant basic privileges
GRANT SELECT ON *.* TO 'pmm_user'@'%';
GRANT PROCESS ON *.* TO 'pmm_user'@'%';
GRANT REPLICATION CLIENT ON *.* TO 'pmm_user'@'%';

-- For user statistics (MariaDB specific)
GRANT SELECT ON information_schema.user_statistics TO 'pmm_user'@'%';

-- For query response time analysis
GRANT SELECT ON information_schema.query_response_time TO 'pmm_user'@'%';

-- Flush privileges
FLUSH PRIVILEGES;
```

### MariaDB Configuration

Enable required features in MariaDB configuration (`/etc/my.cnf` or `/etc/mysql/mariadb.conf.d/50-server.cnf`):

```ini
[mysqld]
# Enable user statistics
userstat = 1

# Enable query response time collection
query_response_time_stats = ON

# Binary logging (if not already enabled)
log-bin = mysql-bin
log-bin-index = mysql-bin.index

# For Galera cluster (if applicable)
# wsrep_on = ON
# wsrep_cluster_address = gcomm://node1,node2,node3
```

Restart MariaDB after configuration changes:

```bash
sudo systemctl restart mariadb
```

## 🔍 Verification

### Check if Custom Metrics are Loaded

1. **Verify file placement:**
```bash
ls -la /usr/local/percona/pmm2/collectors/custom-queries/mysql/*/queries-mysqld.yml
```

2. **Check PMM agent logs:**
```bash
sudo journalctl -u pmm-agent -f | grep mysql
```

3. **Test metrics collection:**
```bash
# Check if metrics are being collected
curl -s http://localhost:42000/metrics | grep mariadb_
```

### Validate in PMM UI

1. Open PMM web interface (usually http://your-server:80 or :443)
2. Navigate to **Dashboards** → **MySQL** → **MySQL Instance Summary**
3. Look for custom MariaDB metrics in the dashboard
4. Check **Query Analytics** for query performance data

## 🎯 Metric Resolution Guidelines

### High-Resolution (5 seconds)
- Connection statistics
- Current active queries
- Buffer pool hit ratios
- Thread pool status

### Medium-Resolution (10 seconds)  
- Replication lag
- Binary log position
- Basic table statistics

### Low-Resolution (60 seconds)
- User statistics
- Storage engine information
- Query response time distributions
- Detailed table statistics

## 🔧 Troubleshooting

### Common Issues

1. **Metrics not appearing:**
   - Check file permissions and ownership
   - Verify PMM agent is running: `sudo systemctl status pmm-agent`
   - Check PMM agent logs: `sudo journalctl -u pmm-agent -n 50`

2. **Permission denied errors:**
   - Verify database user privileges
   - Check if user can connect: `mysql -u pmm_user -p -h localhost`

3. **MariaDB-specific features not working:**
   - Ensure `userstat = 1` is enabled in MariaDB config
   - Verify `query_response_time_stats = ON` for response time metrics
   - Restart MariaDB after config changes

4. **Galera metrics missing:**
   - Only applicable for Galera cluster setups
   - Verify wsrep variables: `SHOW GLOBAL STATUS LIKE 'wsrep_%';`

### Debug Mode

Enable debug logging for PMM agent:

```bash
# Edit PMM agent config
sudo pmm-admin config --server-insecure-tls --debug

# Restart agent with debug logging
sudo systemctl restart pmm-agent

# Check debug logs
sudo journalctl -u pmm-agent -f
```

## 📈 Grafana Dashboard Integration

These custom metrics can be used in Grafana dashboards with queries like:

```promql
# Table growth over time
rate(mariadb_table_stats_table_rows[5m])

# Connection utilization
mariadb_connection_stats_variable_value{variable_name="Threads_connected"} / mariadb_connection_stats_variable_value{variable_name="Max_used_connections"} * 100

# Replication lag
mariadb_slave_lag_seconds_behind_master

# Buffer pool hit ratio
mariadb_innodb_buffer_pool_variable_value{variable_name="Innodb_buffer_pool_read_requests"} / (mariadb_innodb_buffer_pool_variable_value{variable_name="Innodb_buffer_pool_read_requests"} + mariadb_innodb_buffer_pool_variable_value{variable_name="Innodb_buffer_pool_reads"}) * 100
```

## 🔗 References

- [PMM 3.x Documentation](https://docs.percona.com/percona-monitoring-and-management/index.html)
- [MySQL Exporter Custom Queries](https://github.com/prometheus/mysqld_exporter#custom-queries)
- [MariaDB Information Schema](https://mariadb.com/kb/en/information-schema/)
- [MariaDB User Statistics](https://mariadb.com/kb/en/user-statistics/)
- [MariaDB Query Response Time](https://mariadb.com/kb/en/query_response_time-plugin/)

## 📝 Notes

- Custom metrics are collected by the mysql_exporter component in PMM 3.x
- MariaDB uses the same exporter as MySQL but has additional MariaDB-specific features
- Resolution placement determines collection frequency: high (5s), medium (10s), low (60s)
- Always test custom queries in MariaDB before deploying to production
- Monitor PMM agent resource usage when adding custom metrics