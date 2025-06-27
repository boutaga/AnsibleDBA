# Oracle Database PMM/Prometheus Monitoring

This directory contains a complete setup for monitoring Oracle Database with Prometheus and PMM (Percona Monitoring and Management), including custom metrics specifically designed for Oracle enterprise features.

**🆕 Multi-Instance Support**: This solution now supports deploying multiple Oracle exporters on a single monitoring server, each targeting different remote Oracle instances.

## 🎯 Overview

This monitoring solution provides comprehensive Oracle Database metrics including:

- **DataGuard Status Monitoring** - Transport and apply lag tracking
- **Multi-tenant (CDB/PDB) Tablespace Usage** - Detailed space management for container databases
- **RMAN Backup Status** - Backup job monitoring and alerting
- **Flash Recovery Area (FRA) Usage** - Real space usage excluding reclaimable space
- **ASM Diskgroup Monitoring** - Automated Storage Management space tracking
- **Enhanced Standard Metrics** - Instance status, sessions, performance, and more

## 📁 Files

| File | Description |
|------|-------------|
| `deploy.sh` | Single-instance deployment script (legacy) |
| `deploy-multi.sh` | **Multi-instance deployment and management script** |
| `oracledb_exporter.service` | Single-instance systemd service (legacy) |
| `oracledb_exporter@.service` | **Systemd template service for multi-instance** |
| `custom-metrics.toml` | Custom Oracle metrics configuration template |
| `config-template.env` | Configuration template with examples |
| `oracle.collector.yml` | Single-instance Prometheus configuration |
| `prometheus-multi-instance.yml` | **Multi-instance Prometheus configuration** |
| `validate-setup.sh` | Setup validation script |
| `README.md` | This documentation |
| `PMM - Oracle Exporter DEV.md` | Detailed development documentation |
| `PMM - Oracle exporter metrics details.md` | Standard metrics reference |

## 🚀 Quick Start

Choose your deployment approach:

- **[Single Instance](#single-instance-deployment)** - One exporter for one Oracle database
- **[Multi-Instance](#multi-instance-deployment)** - Multiple exporters on one monitoring server ⭐ **Recommended**

### Prerequisites

1. **Oracle Database(s)** running and accessible remotely
2. **Oracle monitoring user** with appropriate privileges on each database
3. **Dedicated monitoring server** (for multi-instance deployment)
4. **Oracle Instant Client** (optional - exporters can use pure Go drivers)
5. **Prometheus** server to scrape metrics

---

## 🔥 Multi-Instance Deployment (Recommended)

Deploy multiple Oracle exporters on a single dedicated monitoring server, each targeting different remote Oracle instances.

### ✅ Advantages

- **Centralized Monitoring**: All Oracle exporters on one server
- **Resource Efficiency**: Shared binary, single server maintenance  
- **Easy Management**: Unified management interface for all instances
- **Port Management**: Automatic port assignment and conflict prevention
- **Independent Scaling**: Add/remove instances without affecting others
- **Security**: No need to install exporters on database servers
- **Network Efficiency**: Single monitoring server for Prometheus to scrape

### Step 1: Initial Setup

```bash
# Make script executable
chmod +x deploy-multi.sh

# Install base system (binary, user, systemd template)
sudo ./deploy-multi.sh setup
```

### Step 2: Add Oracle Instances

```bash
# Add production databases
sudo ./deploy-multi.sh add prod-db1 \
  --host oracle1.company.com \
  --service ORCLCDB \
  --user C##PMM \
  --password secure_password_123

sudo ./deploy-multi.sh add prod-db2 \
  --host oracle2.company.com \
  --port 1522 \
  --service PRODDB \
  --user C##PMM \
  --password secure_password_456

# Add test database
sudo ./deploy-multi.sh add test-db1 \
  --host oracle-test.company.com \
  --service TESTDB \
  --user monitoring_user \
  --password test_password
```

### Step 3: Manage Instances

```bash
# List all configured instances
./deploy-multi.sh list

# Start specific instance
sudo ./deploy-multi.sh start prod-db1

# Check status
./deploy-multi.sh status prod-db1

# View logs
./deploy-multi.sh logs prod-db1

# Start all instances
sudo ./deploy-multi.sh start prod-db1
sudo ./deploy-multi.sh start prod-db2
sudo ./deploy-multi.sh start test-db1
```

### Step 4: Configure Prometheus

Use the multi-instance Prometheus configuration:

```yaml
# Copy from prometheus-multi-instance.yml
scrape_configs:
  - job_name: 'oracle_production'
    static_configs:
      - targets: 
          - 'monitoring-server:9161'  # prod-db1
          - 'monitoring-server:9162'  # prod-db2
    scrape_interval: 30s
    
  - job_name: 'oracle_development'
    static_configs:
      - targets:
          - 'monitoring-server:9163'  # test-db1
    scrape_interval: 60s
```

### Multi-Instance Management Commands

```bash
# Instance Management
./deploy-multi.sh list                    # List all instances
./deploy-multi.sh status [instance]       # Show status (all or specific)
./deploy-multi.sh start <instance>        # Start instance
./deploy-multi.sh stop <instance>         # Stop instance  
./deploy-multi.sh restart <instance>      # Restart instance
./deploy-multi.sh logs <instance>         # View logs
./deploy-multi.sh remove <instance>       # Remove instance

# Examples
./deploy-multi.sh status                  # All instances
./deploy-multi.sh status prod-db1         # Specific instance
./deploy-multi.sh restart prod-db2        # Restart specific
```

### Directory Structure

```
/etc/oracledb_exporter/
├── instances.conf                 # Instance registry
├── custom-metrics-template.toml   # Template for new instances
├── prod-db1/
│   ├── connection.conf            # Connection details
│   └── custom-metrics.toml        # Instance-specific metrics
├── prod-db2/
│   ├── connection.conf
│   └── custom-metrics.toml
└── test-db1/
    ├── connection.conf
    └── custom-metrics.toml
```

### Port Assignment

- **Base port**: 9161 (configurable with BASE_PORT environment variable)
- **Auto-increment**: prod-db1=9161, prod-db2=9162, test-db1=9163, etc.
- **Custom ports**: Use `--exporter-port` option during add

---

## 📊 Single Instance Deployment

### 1. Database User Setup

Create a monitoring user with necessary privileges:

```sql
-- Create monitoring user (for CDB)
CREATE USER C##PMM IDENTIFIED BY your_secure_password CONTAINER=ALL;

-- Grant basic privileges
GRANT CREATE SESSION TO C##PMM CONTAINER=ALL;
GRANT SELECT ON V_$SESSION TO C##PMM CONTAINER=ALL;
GRANT SELECT ON V_$SYSSTAT TO C##PMM CONTAINER=ALL;
GRANT SELECT ON V_$INSTANCE TO C##PMM CONTAINER=ALL;
GRANT SELECT ON V_$DATABASE TO C##PMM CONTAINER=ALL;
GRANT SELECT ON DBA_TABLESPACES TO C##PMM CONTAINER=ALL;
GRANT SELECT ON DBA_DATA_FILES TO C##PMM CONTAINER=ALL;
GRANT SELECT ON DBA_FREE_SPACE TO C##PMM CONTAINER=ALL;

-- Grant privileges for custom metrics
GRANT SELECT ON V_$DATAGUARD_STATS TO C##PMM CONTAINER=ALL;
GRANT SELECT ON V_$RMAN_BACKUP_JOB_DETAILS TO C##PMM CONTAINER=ALL;
GRANT SELECT ON V_$FLASH_RECOVERY_AREA_USAGE TO C##PMM CONTAINER=ALL;
GRANT SELECT ON V_$ASM_DISKGROUP TO C##PMM CONTAINER=ALL;
GRANT SELECT ON CDB_TABLESPACES TO C##PMM CONTAINER=ALL;
GRANT SELECT ON CDB_DATA_FILES TO C##PMM CONTAINER=ALL;
GRANT SELECT ON CDB_TEMP_FILES TO C##PMM CONTAINER=ALL;
GRANT SELECT ON CDB_FREE_SPACE TO C##PMM CONTAINER=ALL;
GRANT SELECT ON V_$TEMP_SPACE_HEADER TO C##PMM CONTAINER=ALL;
GRANT SELECT ON V_$DIAG_ALERT_EXT TO C##PMM CONTAINER=ALL;
GRANT SELECT ON V_$SESSION_LONGOPS TO C##PMM CONTAINER=ALL;
GRANT SELECT ON V_$SGA TO C##PMM CONTAINER=ALL;
GRANT SELECT ON V_$PGASTAT TO C##PMM CONTAINER=ALL;
```

### 2. Deploy Oracle Exporter

Run the automated deployment script:

```bash
# Make the script executable
chmod +x deploy.sh

# Run deployment (as root or with sudo)
sudo ./deploy.sh
```

The script will:
- Download and install the Oracle exporter binary
- Create system user and configuration directories
- Copy custom metrics configuration
- Install and enable systemd service

### 3. Configure Connection

Edit the systemd service file to set your database connection:

```bash
sudo systemctl edit oracledb_exporter
```

Add your connection details:

```ini
[Service]
Environment="DATA_SOURCE_NAME=oracle://C##PMM:your_password@hostname:1521/ORCLCDB"
```

### 4. Start and Verify

```bash
# Start the service
sudo systemctl start oracledb_exporter

# Check status
sudo systemctl status oracledb_exporter

# Check logs
sudo journalctl -u oracledb_exporter -f

# Test metrics endpoint
curl http://localhost:9161/metrics
```

### 5. Configure Prometheus

Add the Oracle job to your Prometheus configuration:

```yaml
scrape_configs:
  - job_name: 'oracle_database'
    static_configs:
      - targets: ['your-oracle-server:9161']
    scrape_interval: 60s
    scrape_timeout: 30s
```

Or use the provided `oracle.collector.yml` for more advanced configuration.

## 📊 Custom Metrics

### DataGuard Monitoring

Monitors DataGuard transport and apply lag:

```
oracle_dataguard_status_lag_seconds{name="transport lag"} 0
oracle_dataguard_status_lag_seconds{name="apply lag"} 1
```

### CDB Tablespace Usage

Provides detailed tablespace metrics for multi-tenant databases:

```
oracle_cdb_tablespace_usage_size_mb{tablespace_name="SYSTEM",con_id="1"} 2180
oracle_cdb_tablespace_usage_used_percent{tablespace_name="SYSTEM",con_id="1"} 96.6
```

### RMAN Backup Status

Tracks backup job status and performance:

```
oracle_rman_backup_status_source_mb{input_type="DB INCR",status="COMPLETED"} 573239
oracle_rman_backup_status_duration_minutes{input_type="DB INCR",status="COMPLETED"} 49.9
```

### FRA Usage

Monitors Flash Recovery Area real usage:

```
oracle_fra_usage_real_usage_percent 4.48
```

### ASM Diskgroup Space

Tracks ASM storage space:

```
oracle_asm_diskgroup_space_usable_gb{diskgroup_name="DATA"} 5504
oracle_asm_diskgroup_space_usable_gb{diskgroup_name="RECO"} 975
```

## 🔧 Configuration

### Environment Variables

Key configuration options (set in systemd service):

| Variable | Description | Example |
|----------|-------------|---------|
| `DATA_SOURCE_NAME` | Oracle connection string | `oracle://user:pass@host:1521/service` |
| `LD_LIBRARY_PATH` | Oracle client library path | `/usr/lib/oracle/21/client64/lib` |
| `ORACLE_HOME` | Oracle home directory | `/opt/oracle/product/19c/dbhome_1` |

### Custom Metrics Configuration

Edit `/etc/oracledb_exporter/custom-metrics.toml` to add or modify metrics:

```toml
[[metric]]
context = "my_custom_metric"
labels = ["label_column"]
metrics = [
    { name = "value_metric", help = "Description", kind = "gauge" }
]
request = "SELECT label_column, value_metric FROM my_view"
```

### Service Configuration

The systemd service supports various options:

```ini
ExecStart=/usr/local/bin/oracledb_exporter \
  --web.listen-address=":9161" \
  --custom.metrics="/etc/oracledb_exporter/custom-metrics.toml" \
  --default.metrics=true \
  --log.level="info"
```

## 🔍 Troubleshooting

### Common Issues

1. **Connection Failed (ORA-12541)**
   ```bash
   # Check listener status
   lsnrctl status
   
   # Test connection
   sqlplus C##PMM/password@hostname:1521/ORCLCDB
   ```

2. **Permission Denied (ORA-00942)**
   ```sql
   -- Grant missing privileges
   GRANT SELECT ON V_$DATAGUARD_STATS TO C##PMM CONTAINER=ALL;
   ```

3. **Library Loading Errors**
   ```bash
   # Set library path in systemd service
   Environment="LD_LIBRARY_PATH=/usr/lib/oracle/21/client64/lib"
   ```

4. **Service Won't Start**
   ```bash
   # Check detailed logs
   journalctl -u oracledb_exporter -n 50 --no-pager
   
   # Test exporter manually
   sudo -u sql_exporter /usr/local/bin/oracledb_exporter --help
   ```

### Debug Mode

Enable debug logging:

```bash
# Edit service to add debug flag
sudo systemctl edit oracledb_exporter

[Service]
ExecStart=
ExecStart=/usr/local/bin/oracledb_exporter \
  --web.listen-address=":9161" \
  --custom.metrics="/etc/oracledb_exporter/custom-metrics.toml" \
  --default.metrics=true \
  --log.level="debug"
```

### Testing Queries

Test custom queries directly in SQL*Plus:

```sql
-- Test DataGuard query
select name, value from v$dataguard_stats where name like '%lag%';

-- Test CDB tablespace query
select tablespace_name, con_id from cdb_tablespaces where rownum <= 5;

-- Test RMAN backup query
select input_type, status, start_time from v$rman_backup_job_details 
where start_time >= sysdate-1;
```

## 📈 Monitoring and Alerting

### Key Metrics to Monitor

1. **Instance Availability**: `oracle_instance_detailed_up`
2. **Tablespace Usage**: `oracle_cdb_tablespace_usage_used_percent > 85`
3. **DataGuard Lag**: `oracle_dataguard_status_lag_seconds > 300`
4. **Backup Failures**: `oracle_rman_backup_status{status!="COMPLETED"}`
5. **FRA Usage**: `oracle_fra_usage_real_usage_percent > 80`
6. **ASM Space**: `oracle_asm_diskgroup_space_usable_gb < 100`

### Grafana Dashboards

Create dashboards for:
- Oracle Instance Overview
- Tablespace Usage and Growth
- DataGuard Status and Performance
- Backup Status and History
- ASM Storage Overview
- Session and Performance Metrics

### Example Alerts

```yaml
groups:
  - name: oracle_alerts
    rules:
      - alert: OracleInstanceDown
        expr: oracle_instance_detailed_up == 0
        for: 1m
        labels:
          severity: critical
      
      - alert: OracleTablespaceUsageHigh
        expr: oracle_cdb_tablespace_usage_used_percent > 90
        for: 5m
        labels:
          severity: warning
      
      - alert: OracleDataGuardLagHigh
        expr: oracle_dataguard_status_lag_seconds > 3600
        for: 10m
        labels:
          severity: warning
```

## 🔒 Security Considerations

1. **Use dedicated monitoring user** with minimal required privileges
2. **Secure connection strings** - avoid plain text passwords
3. **Network security** - restrict access to exporter port (9161)
4. **Regular password rotation** for monitoring accounts
5. **Consider Oracle Wallet** for password-less authentication
6. **Monitor exporter logs** for security events

## 🎯 Integration with PMM

If using Percona Monitoring and Management:

1. **Add Oracle as Custom Service**:
   ```bash
   pmm-admin add external --listen-port=9161 oracle-database
   ```

2. **Import Grafana Dashboards** for Oracle monitoring

3. **Configure Alertmanager** integration for notifications

## 📚 References

- [Oracle Database Monitoring Best Practices](https://docs.oracle.com/database/121/ADMIN/monitor.htm)
- [Oracle DataGuard Documentation](https://docs.oracle.com/database/121/SBYDB/toc.htm)
- [Oracle ASM Administration](https://docs.oracle.com/database/121/OSTMG/toc.htm)
- [RMAN Backup and Recovery](https://docs.oracle.com/database/121/BRADV/toc.htm)
- [Prometheus Oracle Exporter](https://github.com/iamseth/oracledb_exporter)
- [Oracle Observability Project](https://github.com/oracle/oracle-db-appdev-monitoring)

## 🤝 Contributing

To add new custom metrics:

1. Add SQL query to `custom-metrics.toml`
2. Test query in Oracle SQL*Plus
3. Restart exporter service
4. Verify metrics in Prometheus
5. Update documentation

## 📝 License

This configuration is provided as-is for Oracle Database monitoring with Prometheus/PMM. Refer to individual component licenses for specific terms.