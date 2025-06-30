# Installing pgBackRest Custom Queries in PMM v3

This guide explains how to add pgBackRest monitoring queries to PostgreSQL instances already monitored by PMM v3.

## Prerequisites

- PostgreSQL instance already added to PMM v3
- pgBackRest configured and performing backups
- Access to PMM Server (API or UI)
- PostgreSQL superuser access for creating monitoring functions

## Installation Methods

### Method 1: Using PMM API (Recommended)

PMM v3 provides APIs to manage custom queries for postgres_exporter.

#### 1. Get PostgreSQL Service Details

First, identify your PostgreSQL service in PMM:

```bash
# List all PostgreSQL services
curl -s -u admin:admin https://pmm-server/v1/inventory/Services/List | \
  jq '.postgresql[] | {service_id, service_name, node_id}'
```

#### 2. Add Custom Queries via API

```bash
# Set variables
PMM_SERVER="https://pmm-server"
PMM_USER="admin"
PMM_PASS="admin"
SERVICE_NAME="postgresql-prod"

# Create custom queries configuration
cat > pgbackrest-queries.json << 'EOF'
{
  "service_name": "postgresql-prod",
  "queries": {
    "pgbackrest_last_backup": {
      "query": "SELECT stanza, backup_type, EXTRACT(EPOCH FROM (now() - backup_timestamp))::int as seconds_since_backup, backup_size, CASE backup_type WHEN 'full' THEN 1 WHEN 'diff' THEN 2 WHEN 'incr' THEN 3 ELSE 0 END as backup_type_num FROM monitor.pgbackrest_last_backup",
      "metrics": [
        {"stanza": {"usage": "LABEL", "description": "pgBackRest stanza name"}},
        {"backup_type": {"usage": "LABEL", "description": "Type of backup"}},
        {"seconds_since_backup": {"usage": "GAUGE", "description": "Seconds since last backup"}},
        {"backup_size": {"usage": "GAUGE", "description": "Size of last backup in bytes"}},
        {"backup_type_num": {"usage": "GAUGE", "description": "Numeric backup type"}}
      ]
    }
  }
}
EOF

# Apply custom queries (PMM v3 API endpoint)
curl -X POST \
  -u ${PMM_USER}:${PMM_PASS} \
  -H "Content-Type: application/json" \
  -d @pgbackrest-queries.json \
  ${PMM_SERVER}/v1/management/postgresql/queries
```

### Method 2: Using pmm-admin (Agent-side)

If you have access to the PMM agent host:

#### 1. Create Custom Queries File

```bash
# On the PMM agent host
sudo mkdir -p /usr/local/percona/pmm2/collectors/custom-queries/postgresql
cd /usr/local/percona/pmm2/collectors/custom-queries/postgresql

# Copy the pgbackrest-queries.yml file
sudo cp /path/to/pgbackrest-queries.yml .
```

#### 2. Update PostgreSQL Exporter Configuration

```bash
# Find the postgres_exporter process
ps aux | grep postgres_exporter

# Edit the configuration to include custom queries directory
sudo vi /usr/local/percona/pmm2/config/postgres_exporter.yml

# Add or update:
query_directory: /usr/local/percona/pmm2/collectors/custom-queries/postgresql
```

#### 3. Restart PostgreSQL Exporter

```bash
# Restart the exporter
sudo systemctl restart pmm-agent
```

### Method 3: Using PMM UI (Limited)

PMM v3 UI has limited support for custom queries, but you can:

1. Navigate to **Configuration → Settings → Advanced Settings**
2. Look for PostgreSQL collector settings
3. Some versions allow uploading custom query files

## Database Setup

Regardless of the method used, you must first create the monitoring functions in PostgreSQL:

```bash
# Connect to your PostgreSQL instance
psql -h your-postgres-host -U postgres

# Run the monitoring setup SQL
\i pgbackrest-monitoring-setup.sql
```

Create `pgbackrest-monitoring-setup.sql`:

```sql
-- Create monitoring schema
CREATE SCHEMA IF NOT EXISTS monitor;

-- Create pgBackRest info table (populated by cron)
CREATE TABLE IF NOT EXISTS monitor.pgbackrest_info_raw (
    collected_at timestamptz DEFAULT now(),
    info_data jsonb
);

-- Create function to parse pgBackRest JSON data
CREATE OR REPLACE FUNCTION monitor.pgbackrest_info()
RETURNS TABLE (
    stanza text,
    backup_type text,
    backup_timestamp timestamptz,
    backup_lsn text,
    backup_wal_start text,
    backup_wal_stop text,
    backup_duration interval,
    backup_size bigint,
    backup_db_size bigint,
    backup_repo_size bigint,
    backup_reference text,
    backup_error text,
    archive_min text,
    archive_max text,
    repo_status text
) AS $$
BEGIN
    RETURN QUERY
    WITH latest_info AS (
        SELECT info_data
        FROM monitor.pgbackrest_info_raw
        ORDER BY collected_at DESC
        LIMIT 1
    ),
    parsed_data AS (
        SELECT 
            stanza_elem->>'name' as stanza_name,
            repo_elem->>'status' as repo_status,
            backup_elem->>'type' as backup_type,
            to_timestamp((backup_elem->'timestamp'->>'stop')::bigint) as backup_timestamp,
            backup_elem->'info'->>'lsn' as backup_lsn,
            backup_elem->'archive'->>'start' as backup_wal_start,
            backup_elem->'archive'->>'stop' as backup_wal_stop,
            to_timestamp((backup_elem->'timestamp'->>'stop')::bigint) - 
                to_timestamp((backup_elem->'timestamp'->>'start')::bigint) as backup_duration,
            (backup_elem->'info'->'size')::bigint as backup_size,
            (backup_elem->'info'->'database'->'size')::bigint as backup_db_size,
            (backup_elem->'info'->'repository'->'size')::bigint as backup_repo_size,
            backup_elem->>'reference' as backup_reference,
            backup_elem->>'error' as backup_error,
            stanza_elem->'archive'->0->>'min' as archive_min,
            stanza_elem->'archive'->0->>'max' as archive_max
        FROM latest_info,
            jsonb_array_elements(info_data->'stanza') as stanza_elem,
            jsonb_array_elements(stanza_elem->'repo') as repo_elem,
            jsonb_array_elements(stanza_elem->'backup') as backup_elem
    )
    SELECT * FROM parsed_data;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create convenient views
CREATE OR REPLACE VIEW monitor.pgbackrest_last_backup AS
WITH latest_backups AS (
    SELECT 
        stanza,
        MAX(backup_timestamp) as last_backup_time
    FROM monitor.pgbackrest_info()
    WHERE backup_error IS NULL
    GROUP BY stanza
)
SELECT 
    pb.stanza,
    pb.backup_type,
    pb.backup_timestamp,
    pb.backup_size,
    age(now(), pb.backup_timestamp) as time_since_backup,
    EXTRACT(EPOCH FROM age(now(), pb.backup_timestamp)) as seconds_since_backup
FROM monitor.pgbackrest_info() pb
JOIN latest_backups lb ON pb.stanza = lb.stanza 
    AND pb.backup_timestamp = lb.last_backup_time;

-- Grant permissions
GRANT USAGE ON SCHEMA monitor TO PUBLIC;
GRANT EXECUTE ON FUNCTION monitor.pgbackrest_info() TO PUBLIC;
GRANT SELECT ON ALL TABLES IN SCHEMA monitor TO PUBLIC;
```

## Setting Up Data Collection

Create a cron job to populate the monitoring data:

```bash
# Create collection script
sudo tee /usr/local/bin/pgbackrest-pmm-collector.sh << 'EOF'
#!/bin/bash
# Collect pgBackRest info for PMM

PGHOST="${PGHOST:-localhost}"
PGDATABASE="${PGDATABASE:-postgres}"
PGUSER="${PGUSER:-postgres}"

# Get pgBackRest info
info_json=$(pgbackrest info --output=json 2>/dev/null)

# Store in PostgreSQL
psql -h "$PGHOST" -d "$PGDATABASE" -U "$PGUSER" << SQL
INSERT INTO monitor.pgbackrest_info_raw (info_data) 
VALUES ('${info_json}'::jsonb);

-- Keep only last 7 days
DELETE FROM monitor.pgbackrest_info_raw 
WHERE collected_at < now() - interval '7 days';
SQL
EOF

sudo chmod +x /usr/local/bin/pgbackrest-pmm-collector.sh

# Add to crontab (run every 5 minutes)
(crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/pgbackrest-pmm-collector.sh") | crontab -
```

## Verifying the Installation

### 1. Check Query Registration

```bash
# Via API
curl -s -u admin:admin ${PMM_SERVER}/v1/management/postgresql/queries/${SERVICE_NAME} | jq .

# Via direct metrics endpoint
curl -s http://pmm-agent-host:42001/metrics | grep pgbackrest_
```

### 2. Test Queries Directly

```sql
-- In PostgreSQL
SELECT * FROM monitor.pgbackrest_last_backup;
SELECT * FROM monitor.pgbackrest_info() LIMIT 5;
```

### 3. Check in PMM UI

1. Go to **Explore → Metrics**
2. Search for `pgbackrest_`
3. Verify metrics are appearing

## Creating Grafana Dashboards

Once metrics are flowing, create dashboards in PMM:

### 1. Via UI
- Navigate to **Dashboards → Create → Dashboard**
- Add panels with PromQL queries

### 2. Via API
```bash
# Import dashboard JSON
curl -X POST \
  -u admin:admin \
  -H "Content-Type: application/json" \
  -d @pgbackrest-dashboard.json \
  ${PMM_SERVER}/api/dashboards/db
```

### Example Panel Queries

```promql
# Time since last backup
pgbackrest_last_backup_seconds_since_backup{service_name="$service"}

# Backup success rate (last 24h)
increase(pgbackrest_backup_status_successful_backups[24h])

# Average backup duration
avg_over_time(pgbackrest_backup_status_avg_backup_duration_seconds[7d])
```

## Troubleshooting

### Metrics Not Appearing

1. **Check postgres_exporter logs:**
```bash
journalctl -u pmm-agent -f | grep postgres_exporter
```

2. **Verify custom queries loaded:**
```bash
# Check exporter endpoint
curl -s http://localhost:42001/metrics | grep "custom_query"
```

3. **Test query manually:**
```bash
# Run exporter query test
postgres_exporter --query.test "pgbackrest_last_backup"
```

### Permission Issues

Ensure the PMM PostgreSQL user has access:
```sql
-- Grant necessary permissions to PMM user
GRANT USAGE ON SCHEMA monitor TO pmm;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA monitor TO pmm;
GRANT SELECT ON ALL TABLES IN SCHEMA monitor TO pmm;
```

### API Authentication Issues

For PMM v3 with enhanced security:
```bash
# Get API token
TOKEN=$(curl -X POST \
  -d '{"username":"admin","password":"admin"}' \
  ${PMM_SERVER}/auth/login | jq -r .token)

# Use token in requests
curl -H "Authorization: Bearer $TOKEN" \
  ${PMM_SERVER}/v1/inventory/Services/List
```

## Best Practices

1. **Test in Staging First**
   - Deploy to non-production environment
   - Verify metrics collection
   - Test dashboard functionality

2. **Monitor Query Performance**
   - Ensure custom queries don't impact database
   - Use appropriate intervals
   - Consider query complexity

3. **Security Considerations**
   - Use least-privilege database user
   - Secure pgBackRest configuration files
   - Encrypt API communications

4. **Regular Maintenance**
   - Update queries as pgBackRest evolves
   - Monitor data retention
   - Review and optimize queries

## References

- [PMM v3 API Documentation](https://docs.percona.com/percona-monitoring-and-management/api.html)
- [postgres_exporter Custom Queries](https://github.com/prometheus-community/postgres_exporter#adding-new-metrics)
- [PMM Custom Queries Guide](https://docs.percona.com/percona-monitoring-and-management/extend-metrics.html)