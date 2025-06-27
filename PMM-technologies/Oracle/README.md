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
2. **Secure connection strings** - avoid plain text passwords (see KMS integration below)
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



## Not released yet :    

**🆕 External KMS Integration** - Store sensitive credentials in external Key Management Services

---

## 🔐 External KMS Integration (Roadmap Feature)

**Status**: 📋 **Planned Feature** - Ready for implementation

### Overview

Integrate with external Key Management Services to securely store and retrieve Oracle database credentials, eliminating plain-text passwords from configuration files.

### Supported KMS Providers

#### 🏢 **Enterprise KMS Solutions**
- **HashiCorp Vault** - Enterprise secret management
- **AWS Secrets Manager** - Cloud-native secret storage
- **Azure Key Vault** - Microsoft Azure secret management
- **Google Secret Manager** - Google Cloud secret storage
- **CyberArk Vault** - Enterprise privileged access management

#### 🔧 **Implementation Approach**

The KMS integration would extend the current multi-instance deployment with secure credential retrieval:

```bash
# Enhanced add command with KMS integration
sudo ./deploy-multi.sh add prod-db1 \
  --host oracle1.company.com \
  --service ORCLCDB \
  --user C##PMM \
  --kms-provider vault \
  --kms-path secret/oracle/prod-db1 \
  --kms-endpoint https://vault.company.com:8200

# Alternative: AWS Secrets Manager
sudo ./deploy-multi.sh add prod-db2 \
  --host oracle2.company.com \
  --service PRODDB \
  --user C##PMM \
  --kms-provider aws-secrets \
  --kms-secret-name oracle/prod-db2/credentials \
  --aws-region us-east-1
```

### Configuration Examples

#### **HashiCorp Vault Integration**

```bash
# connection.conf would reference KMS instead of plain passwords
# /etc/oracledb_exporter/prod-db1/connection.conf
KMS_PROVIDER=vault
KMS_ENDPOINT=https://vault.company.com:8200
KMS_PATH=secret/oracle/prod-db1
KMS_AUTH_METHOD=token  # or: aws-iam, kubernetes, ldap
VAULT_TOKEN_FILE=/etc/oracledb_exporter/vault-token
ORACLE_HOST=oracle1.company.com
ORACLE_PORT=1521
ORACLE_SERVICE=ORCLCDB
ORACLE_USER=C##PMM
EXPORTER_PORT=9161
```

**Vault Secret Structure:**
```json
{
  "password": "secure_oracle_password_123",
  "wallet_password": "wallet_secret_456",
  "ssl_cert": "-----BEGIN CERTIFICATE-----...",
  "ssl_key": "-----BEGIN PRIVATE KEY-----..."
}
```

#### **AWS Secrets Manager Integration**

```bash
# connection.conf for AWS Secrets Manager
# /etc/oracledb_exporter/prod-db2/connection.conf
KMS_PROVIDER=aws-secrets
KMS_SECRET_NAME=oracle/prod-db2/credentials
AWS_REGION=us-east-1
AWS_ROLE_ARN=arn:aws:iam::123456789012:role/OracleMonitoringRole
ORACLE_HOST=oracle2.company.com
ORACLE_PORT=1521
ORACLE_SERVICE=PRODDB
ORACLE_USER=C##PMM
EXPORTER_PORT=9162
```

**AWS Secret Structure:**
```json
{
  "username": "C##PMM",
  "password": "secure_oracle_password_456",
  "host": "oracle2.company.com",
  "port": "1521",
  "service": "PRODDB"
}
```

#### **Azure Key Vault Integration**

```bash
# connection.conf for Azure Key Vault
# /etc/oracledb_exporter/prod-db3/connection.conf
KMS_PROVIDER=azure-keyvault
KMS_VAULT_URL=https://oracle-secrets.vault.azure.net/
KMS_SECRET_NAME=oracle-prod-db3-password
AZURE_CLIENT_ID=12345678-1234-1234-1234-123456789012
AZURE_TENANT_ID=87654321-4321-4321-4321-210987654321
ORACLE_HOST=oracle3.company.com
ORACLE_PORT=1521
ORACLE_SERVICE=PRODDB
ORACLE_USER=C##PMM
EXPORTER_PORT=9163
```

### Enhanced SystemD Service Template

The systemd template would be enhanced to support KMS credential retrieval:

```ini
# /etc/systemd/system/oracledb_exporter@.service
[Unit]
Description=Prometheus Oracle DB Exporter for %i with KMS Integration
After=network-online.target
Wants=network-online.target

[Service]
User=sql_exporter
Group=sql_exporter
Type=simple
Restart=on-failure
RestartSec=5

# Instance-specific configuration directory
EnvironmentFile=/etc/oracledb_exporter/%i/connection.conf

# KMS credential resolution script
ExecStartPre=/usr/local/bin/oracle-kms-resolver %i
ExecStart=/usr/local/bin/oracledb_exporter \
  --web.listen-address=":${EXPORTER_PORT}" \
  --custom.metrics="/etc/oracledb_exporter/%i/custom-metrics.toml" \
  --default.metrics=true \
  --log.level=info

# Enhanced security for KMS access
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/tmp /var/lib/oracledb_exporter

[Install]
WantedBy=multi-user.target
```

### KMS Authentication Methods

#### **HashiCorp Vault**
```bash
# Token-based authentication
VAULT_TOKEN=hvs.abcdef123456...

# AWS IAM authentication
VAULT_AUTH_AWS_ROLE=oracle-monitoring
VAULT_AUTH_AWS_IAM=true

# Kubernetes service account
VAULT_AUTH_K8S_ROLE=oracle-exporter
VAULT_AUTH_K8S_SA_TOKEN_PATH=/var/run/secrets/kubernetes.io/serviceaccount/token
```

#### **AWS Secrets Manager**
```bash
# IAM Role-based (recommended)
AWS_ROLE_ARN=arn:aws:iam::123456789012:role/OracleMonitoringRole

# Instance profile (for EC2)
# Automatically uses EC2 instance IAM role

# Access keys (not recommended for production)
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=...
```

#### **Azure Key Vault**
```bash
# Managed Identity (recommended)
AZURE_USE_MANAGED_IDENTITY=true

# Service Principal
AZURE_CLIENT_ID=12345678-1234-1234-1234-123456789012
AZURE_CLIENT_SECRET=...
AZURE_TENANT_ID=87654321-4321-4321-4321-210987654321

# Certificate-based authentication
AZURE_CLIENT_CERTIFICATE_PATH=/etc/ssl/certs/azure-client.pem
```

### Implementation Benefits

#### **🔒 Security Enhancements**
- **Zero Plain-Text Passwords**: No credentials stored in config files
- **Centralized Secret Management**: Single source of truth for all credentials
- **Audit Trails**: Complete access logging for all secret retrievals
- **Automatic Rotation**: Support for automatic password rotation
- **Fine-Grained Access**: KMS-level access controls and policies

#### **🏢 Enterprise Features**
- **Compliance Ready**: Meets enterprise security and compliance requirements
- **Multi-Environment**: Different KMS backends for dev/test/prod
- **Disaster Recovery**: KMS replication and backup strategies
- **Integration Ready**: Works with existing enterprise KMS infrastructure

#### **⚡ Operational Benefits**
- **Simplified Deployment**: No manual password management
- **Reduced Risk**: Eliminates credential exposure in logs/configs
- **Automated Updates**: Credentials can be rotated without service restarts
- **Monitoring Integration**: KMS access metrics and alerting

### Proposed File Structure with KMS

```
/etc/oracledb_exporter/
├── instances.conf                     # Instance registry
├── custom-metrics-template.toml       # Template for new instances
├── kms/
│   ├── vault-config.json             # Vault configuration
│   ├── aws-config.json               # AWS Secrets Manager config  
│   ├── azure-config.json             # Azure Key Vault config
│   └── tokens/                       # Temporary token storage
│       ├── vault-token
│       └── aws-session-token
├── prod-db1/
│   ├── connection.conf               # KMS-enabled connection config
│   └── custom-metrics.toml           # Instance-specific metrics
├── prod-db2/
│   ├── connection.conf               # AWS Secrets Manager config
│   └── custom-metrics.toml
└── prod-db3/
    ├── connection.conf               # Azure Key Vault config
    └── custom-metrics.toml
```

### Enhanced Management Commands

```bash
# KMS-enabled instance management
sudo ./deploy-multi.sh setup --kms-provider vault --vault-endpoint https://vault.company.com:8200

# Add instance with Vault integration
sudo ./deploy-multi.sh add prod-db1 \
  --host oracle1.company.com \
  --service ORCLCDB \
  --user C##PMM \
  --kms-provider vault \
  --kms-path secret/oracle/prod-db1

# Test KMS connectivity
./deploy-multi.sh test-kms prod-db1

# Rotate credentials (triggers KMS refresh)
sudo ./deploy-multi.sh rotate-secrets prod-db1

# KMS status and health
./deploy-multi.sh kms-status
```

### Implementation Timeline

#### **Phase 1: Core KMS Integration** 
- [ ] HashiCorp Vault integration
- [ ] Enhanced systemd template with KMS support
- [ ] Credential resolution script (`oracle-kms-resolver`)
- [ ] Basic authentication methods (token, AWS IAM)

#### **Phase 2: Multi-Provider Support** 
- [ ] AWS Secrets Manager integration
- [ ] Azure Key Vault integration
- [ ] Google Secret Manager integration
- [ ] Enhanced management commands

#### **Phase 3: Enterprise Features** 
- [ ] Automatic credential rotation
- [ ] Advanced authentication methods
- [ ] KMS health monitoring and alerting
- [ ] Comprehensive documentation and examples

#### **Phase 4: Advanced Integration** 
- [ ] Prometheus metrics for KMS operations
- [ ] Grafana dashboards for KMS monitoring
- [ ] Integration with Oracle Wallet
- [ ] SSL/TLS certificate management via KMS

### Prerequisites for KMS Integration

1. **KMS Infrastructure**: Access to one or more supported KMS providers
2. **Network Connectivity**: Monitoring server must reach KMS endpoints
3. **Authentication Setup**: Appropriate roles, policies, and permissions
4. **Monitoring Integration**: KMS access monitoring and alerting

### Migration Path

For existing deployments, migration to KMS would be seamless:

```bash
# Step 1: Enable KMS for existing instance
sudo ./deploy-multi.sh enable-kms prod-db1 --kms-provider vault --kms-path secret/oracle/prod-db1

# Step 2: Store existing password in KMS
vault kv put secret/oracle/prod-db1 password="current_password_123"

# Step 3: Test KMS integration
./deploy-multi.sh test-kms prod-db1

# Step 4: Restart with KMS enabled
sudo ./deploy-multi.sh restart prod-db1

# Step 5: Verify KMS operation
./deploy-multi.sh status prod-db1
./deploy-multi.sh logs prod-db1
```

This KMS integration would significantly enhance the security posture of the Oracle monitoring solution while maintaining the ease of use and management capabilities of the multi-instance deployment approach.
