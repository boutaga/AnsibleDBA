# PostgreSQL Custom Metrics for PMM 3.x

This directory contains custom metrics configuration for monitoring PostgreSQL databases with PMM (Percona Monitoring and Management) version 3.x.

## 📋 Overview

PMM 3.x uses the postgres_exporter to collect PostgreSQL metrics through custom YAML configuration files. These files define SQL queries that are executed periodically to gather specific metrics from PostgreSQL system catalogs and statistics views.

## 📁 Files

- `queries-postgres.yml` - Custom PostgreSQL metrics configuration
- `README.md` - This documentation file

## 🚀 Installation

### Step 1: Copy Custom Metrics File

Copy the custom metrics file to the PMM collectors directory:

```bash
# For high-resolution metrics (collected every 5 seconds)
sudo cp queries-postgres.yml /usr/local/percona/pmm2/collectors/custom-queries/postgresql/high-resolution/

# For medium-resolution metrics (collected every 10 seconds)
sudo cp queries-postgres.yml /usr/local/percona/pmm2/collectors/custom-queries/postgresql/medium-resolution/

# For low-resolution metrics (collected every 60 seconds)
sudo cp queries-postgres.yml /usr/local/percona/pmm2/collectors/custom-queries/postgresql/low-resolution/
```

### Step 2: Set Proper Permissions

```bash
sudo chown pmm:pmm /usr/local/percona/pmm2/collectors/custom-queries/postgresql/*/queries-postgres.yml
sudo chmod 644 /usr/local/percona/pmm2/collectors/custom-queries/postgresql/*/queries-postgres.yml
```

### Step 3: Add PostgreSQL Instance to PMM

Add your PostgreSQL instance to PMM monitoring:

```bash
# Add PostgreSQL instance
sudo pmm-admin add postgresql --username=pmm_user --password=pmm_password --host=localhost --port=5432 --database=postgres postgresql-instance

# For remote PostgreSQL instance
sudo pmm-admin add postgresql --username=pmm_user --password=pmm_password --host=postgres-server.example.com --port=5432 --database=postgres postgresql-remote
```

### Step 4: Restart PMM Agent

```bash
sudo systemctl restart pmm-agent
```

## 📊 Available Custom Metrics

### Database Statistics
- `pg_database_stats_size_bytes` - Database size in bytes
- `pg_database_stats_numbackends` - Number of active connections per database
- `pg_database_stats_xact_commit` - Committed transactions counter
- `pg_database_stats_xact_rollback` - Rolled back transactions counter
- `pg_database_stats_blks_read` - Disk blocks read counter
- `pg_database_stats_blks_hit` - Buffer cache hits counter
- `pg_database_stats_tup_*` - Tuple operation counters (returned, fetched, inserted, updated, deleted)

### Table Statistics
- `pg_table_stats_n_tup_ins` - Tuples inserted per table
- `pg_table_stats_n_tup_upd` - Tuples updated per table
- `pg_table_stats_n_tup_del` - Tuples deleted per table
- `pg_table_stats_n_live_tup` - Live tuples count per table
- `pg_table_stats_n_dead_tup` - Dead tuples count per table
- `pg_table_stats_seq_scan` - Sequential scans per table
- `pg_table_stats_idx_scan` - Index scans per table

### Index Usage
- `pg_index_stats_idx_scan` - Index scan count
- `pg_index_stats_idx_tup_read` - Index entries returned
- `pg_index_stats_idx_tup_fetch` - Live rows fetched via index

### Connection Monitoring
- `pg_activity_connections` - Number of connections by state (active, idle, idle in transaction, etc.)

### Replication Monitoring
- `pg_replication_lag_flush_lag_bytes` - Flush lag in bytes
- `pg_replication_lag_replay_lag_bytes` - Replay lag in bytes

### WAL (Write-Ahead Logging)
- `pg_wal_stats_current_wal_file` - Current WAL file name

### Performance Metrics
- `pg_buffer_cache_cache_hit_ratio` - Buffer cache hit ratio percentage per database
- `pg_long_queries` - Information about long-running queries

### Maintenance Operations
- `pg_vacuum_stats_vacuum_count` - Manual vacuum operations per table
- `pg_vacuum_stats_autovacuum_count` - Autovacuum operations per table
- `pg_vacuum_stats_analyze_count` - Manual analyze operations per table
- `pg_vacuum_stats_autoanalyze_count` - Auto-analyze operations per table

### Lock Monitoring
- `pg_locks_lock_count` - Number of locks by lock mode

### Checkpoint Statistics
- `pg_checkpoint_stats_checkpoints_timed` - Scheduled checkpoints
- `pg_checkpoint_stats_checkpoints_req` - Requested checkpoints
- `pg_checkpoint_stats_checkpoint_write_time` - Checkpoint write time
- `pg_checkpoint_stats_buffers_*` - Various buffer statistics

### Storage
- `pg_tablespace_usage_size_bytes` - Tablespace size in bytes

## 🔧 Configuration Requirements

### Database User Privileges

Create a monitoring user with appropriate privileges:

```sql
-- Create monitoring user
CREATE USER pmm_user WITH PASSWORD 'pmm_password';

-- Grant connect privilege
GRANT CONNECT ON DATABASE postgres TO pmm_user;

-- Grant usage on schema
GRANT USAGE ON SCHEMA public TO pmm_user;

-- Grant select on statistics views
GRANT SELECT ON pg_stat_database TO pmm_user;
GRANT SELECT ON pg_stat_user_tables TO pmm_user;
GRANT SELECT ON pg_stat_user_indexes TO pmm_user;
GRANT SELECT ON pg_stat_activity TO pmm_user;
GRANT SELECT ON pg_stat_replication TO pmm_user;
GRANT SELECT ON pg_stat_bgwriter TO pmm_user;
GRANT SELECT ON pg_locks TO pmm_user;
GRANT SELECT ON pg_tablespace TO pmm_user;

-- Grant execute on WAL functions
GRANT EXECUTE ON FUNCTION pg_current_wal_lsn() TO pmm_user;
GRANT EXECUTE ON FUNCTION pg_walfile_name(pg_lsn) TO pmm_user;
GRANT EXECUTE ON FUNCTION pg_wal_lsn_diff(pg_lsn, pg_lsn) TO pmm_user;
GRANT EXECUTE ON FUNCTION pg_database_size(name) TO pmm_user;
GRANT EXECUTE ON FUNCTION pg_tablespace_size(name) TO pmm_user;
GRANT EXECUTE ON FUNCTION pg_backend_pid() TO pmm_user;

-- For PostgreSQL 10+ (pg_monitor role)
-- GRANT pg_monitor TO pmm_user;
```

### PostgreSQL Configuration

Ensure required settings in PostgreSQL configuration (`postgresql.conf`):

```ini
# Enable statistics collection
track_activities = on
track_counts = on
track_io_timing = on
track_functions = all

# For replication monitoring (if using replication)
wal_level = replica  # or higher
max_wal_senders = 3  # or appropriate number
wal_keep_segments = 32  # for PostgreSQL < 13
# wal_keep_size = 512MB  # for PostgreSQL 13+

# For better monitoring
log_checkpoints = on
log_connections = on
log_disconnections = on
log_lock_waits = on

# Shared preload libraries (if using extensions)
# shared_preload_libraries = 'pg_stat_statements'
```

Update `pg_hba.conf` to allow connections:

```
# Allow PMM user connections
host    all             pmm_user        127.0.0.1/32            md5
host    all             pmm_user        ::1/128                 md5
```

Restart PostgreSQL after configuration changes:

```bash
sudo systemctl restart postgresql
```

## 🔍 Verification

### Check if Custom Metrics are Loaded

1. **Verify file placement:**
```bash
ls -la /usr/local/percona/pmm2/collectors/custom-queries/postgresql/*/queries-postgres.yml
```

2. **Check PMM agent logs:**
```bash
sudo journalctl -u pmm-agent -f | grep postgres
```

3. **Test metrics collection:**
```bash
# Check if metrics are being collected
curl -s http://localhost:42001/metrics | grep pg_
```

### Validate in PMM UI

1. Open PMM web interface (usually http://your-server:80 or :443)
2. Navigate to **Dashboards** → **PostgreSQL** → **PostgreSQL Instance Summary**
3. Look for custom PostgreSQL metrics in the dashboard
4. Check **Query Analytics** for query performance data

## 🎯 Metric Resolution Guidelines

### High-Resolution (5 seconds)
- Connection activity
- Lock monitoring
- Current WAL position
- Active query monitoring

### Medium-Resolution (10 seconds)
- Database statistics
- Buffer cache metrics
- Replication lag
- Basic table statistics

### Low-Resolution (60 seconds)
- Table and index detailed statistics
- Vacuum and analyze statistics
- Checkpoint statistics
- Tablespace usage
- Long-running query detection

## 🔧 Troubleshooting

### Common Issues

1. **Metrics not appearing:**
   - Check file permissions and ownership
   - Verify PMM agent is running: `sudo systemctl status pmm-agent`
   - Check PMM agent logs: `sudo journalctl -u pmm-agent -n 50`

2. **Permission denied errors:**
   - Verify database user privileges
   - Check if user can connect: `psql -U pmm_user -h localhost -d postgres`
   - Ensure pg_hba.conf allows connections

3. **Connection refused:**
   - Check if PostgreSQL is running: `sudo systemctl status postgresql`
   - Verify PostgreSQL is listening: `netstat -ln | grep 5432`
   - Check firewall settings

4. **Function execution errors:**
   - Verify PostgreSQL version compatibility
   - Some functions require specific privileges or PostgreSQL versions

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

### Test Queries Manually

Test custom queries directly in PostgreSQL:

```sql
-- Test database stats query
SELECT datname, pg_database_size(datname) as size_bytes, numbackends 
FROM pg_stat_database 
WHERE datname NOT IN ('template0', 'template1');

-- Test replication lag (only works on master with replicas)
SELECT application_name, client_addr, state, 
       pg_wal_lsn_diff(pg_current_wal_lsn(), flush_lsn) as flush_lag_bytes 
FROM pg_stat_replication;

-- Test connection activity
SELECT state, count(*) as connections 
FROM pg_stat_activity 
WHERE pid <> pg_backend_pid() 
GROUP BY state;
```

## 📈 Grafana Dashboard Integration

These custom metrics can be used in Grafana dashboards with queries like:

```promql
# Database size growth
rate(pg_database_stats_size_bytes[1h])

# Connection utilization
pg_activity_connections{state="active"} / sum(pg_activity_connections) * 100

# Buffer cache hit ratio
pg_buffer_cache_cache_hit_ratio

# Replication lag in MB
pg_replication_lag_flush_lag_bytes / 1024 / 1024

# Table bloat estimation
pg_table_stats_n_dead_tup / (pg_table_stats_n_live_tup + pg_table_stats_n_dead_tup) * 100

# Checkpoint frequency
rate(pg_checkpoint_stats_checkpoints_timed[5m])
```

## 🔗 References

- [PMM 3.x Documentation](https://docs.percona.com/percona-monitoring-and-management/index.html)
- [PostgreSQL Exporter Custom Queries](https://github.com/prometheus-community/postgres_exporter#custom-queries)
- [PostgreSQL System Catalogs](https://www.postgresql.org/docs/current/catalogs.html)
- [PostgreSQL Statistics Views](https://www.postgresql.org/docs/current/monitoring-stats.html)
- [PostgreSQL WAL Functions](https://www.postgresql.org/docs/current/functions-admin.html#FUNCTIONS-ADMIN-BACKUP)

## 📝 Notes

- Custom metrics are collected by the postgres_exporter component in PMM 3.x
- Resolution placement determines collection frequency: high (5s), medium (10s), low (60s)
- Some queries may require specific PostgreSQL versions or configurations
- Always test custom queries in PostgreSQL before deploying to production
- Monitor PMM agent resource usage when adding custom metrics
- Replication-related metrics only work on primary servers with active replicas
- WAL-related functions require appropriate privileges and may vary between PostgreSQL versions