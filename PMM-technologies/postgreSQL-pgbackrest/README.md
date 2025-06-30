# pgBackRest Monitoring Integration for PMM

This directory contains deployment scripts and configuration for integrating pgBackRest backup monitoring with Percona Monitoring and Management (PMM).

## Overview

pgBackRest is an advanced backup and restore solution for PostgreSQL. This integration enables monitoring of:
- Backup status and timing
- Archive status and WAL management
- Backup sizes and durations
- Repository health
- Retention policy compliance

## Components

### 1. deploy.sh
Main deployment script that:
- Creates PostgreSQL monitoring schema and functions
- Installs custom queries for postgres_exporter
- Sets up automated pgBackRest info collection
- Configures cron job for periodic updates

### 2. pgbackrest-queries.yml
Custom queries for postgres_exporter that expose:
- `pgbackrest_last_backup` - Time since last successful backup
- `pgbackrest_backup_status` - Backup success/failure statistics
- `pgbackrest_archive_status` - WAL archive monitoring
- `pgbackrest_retention_status` - Backup retention metrics
- `pgbackrest_stanza_info` - Overall stanza health

## Prerequisites

1. pgBackRest installed and configured
2. PostgreSQL database with superuser access
3. PMM with postgres_exporter configured
4. Linux environment with bash, cron, and standard utilities

## Installation

1. Run the deployment script:
```bash
cd PMM-technologies/postgreSQL-pgbackrest
sudo ./deploy.sh
```

2. The script will:
   - Check pgBackRest installation
   - Create monitoring schema in PostgreSQL
   - Install custom queries for PMM
   - Set up automated info collection
   - Configure postgres_exporter

## Configuration

### Environment Variables
- `PGBACKREST_USER` - PostgreSQL user (default: postgres)
- `PGBACKREST_CONFIG` - pgBackRest config path (default: /etc/pgbackrest/pgbackrest.conf)
- `MONITORING_DB` - Database for monitoring objects (default: postgres)
- `MONITORING_SCHEMA` - Schema name (default: monitor)
- `PMM_POSTGRES_EXPORTER_PORT` - Exporter port (default: 9187)

### Custom Queries Location
The custom queries are installed to: `/etc/postgres_exporter/queries/pgbackrest.yml`

## Metrics Available

### Backup Metrics
- `pgbackrest_last_backup_seconds_since_backup` - Time since last backup
- `pgbackrest_backup_status_successful_backups` - Count of successful backups
- `pgbackrest_backup_status_failed_backups` - Count of failed backups
- `pgbackrest_backup_status_max_backup_duration_seconds` - Maximum backup duration
- `pgbackrest_backup_status_total_backup_size` - Total size of all backups

### Archive Metrics
- `pgbackrest_archive_status_archive_size_bytes` - Estimated archive size
- `pgbackrest_archive_status_repo_ok` - Repository health status

### Retention Metrics
- `pgbackrest_retention_status_full_backup_count` - Number of full backups retained
- `pgbackrest_retention_status_oldest_full_backup_age_seconds` - Age of oldest backup

## Monitoring Setup

### PostgreSQL Functions
The deployment creates these monitoring functions:
- `monitor.pgbackrest_info()` - Main function returning backup information
- `monitor.pgbackrest_status` - View showing backup status with health indicators
- `monitor.pgbackrest_last_backup` - View of most recent backups per stanza

### Data Collection
A cron job runs every 5 minutes to execute `pgbackrest info --output=json` and store results.

## Grafana Dashboard

After deployment, you can create Grafana dashboards using queries like:

```promql
# Time since last backup
pgbackrest_last_backup_seconds_since_backup{stanza="main"}

# Backup success rate
rate(pgbackrest_backup_status_successful_backups[1h])

# Repository health
pgbackrest_archive_status_repo_ok{stanza="main"}
```

## Alerts

Example alert rules for Prometheus:

```yaml
groups:
  - name: pgbackrest
    rules:
      - alert: BackupTooOld
        expr: pgbackrest_last_backup_seconds_since_backup > 86400
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "pgBackRest backup is too old"
          description: "Last backup for {{ $labels.stanza }} was {{ $value }} seconds ago"
      
      - alert: BackupFailed
        expr: increase(pgbackrest_backup_status_failed_backups[1h]) > 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "pgBackRest backup failed"
          description: "Backup failures detected for stanza {{ $labels.stanza }}"
```

## Troubleshooting

### Check Installation
```bash
# Verify PostgreSQL functions
psql -d postgres -c "SELECT * FROM monitor.pgbackrest_info();"

# Check info collector logs
tail -f /var/log/pgbackrest-info-collector.log

# Verify metrics exposure
curl -s localhost:9187/metrics | grep pgbackrest_
```

### Common Issues

1. **No metrics appearing**
   - Ensure pgBackRest has performed at least one backup
   - Check postgres_exporter logs
   - Verify query directory is configured in postgres_exporter

2. **Permission errors**
   - Ensure postgres user can run pgbackrest commands
   - Check file permissions on scripts and configs

3. **Empty monitoring tables**
   - Run info collector manually: `/usr/local/bin/pgbackrest-info-collector.sh`
   - Check pgBackRest configuration and stanza setup

## References

- [pgBackRest User Guide - Monitoring](https://pgbackrest.org/user-guide.html#monitor)
- [PMM Documentation](https://docs.percona.com/percona-monitoring-and-management/)
- [postgres_exporter](https://github.com/prometheus-community/postgres_exporter)