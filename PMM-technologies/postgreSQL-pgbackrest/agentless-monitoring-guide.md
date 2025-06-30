# Agentless pgBackRest Monitoring in PMM

## Understanding Agentless PostgreSQL Monitoring

In agentless mode, PMM uses server-side postgres_exporter that connects directly to PostgreSQL using database credentials. No agent runs on the database host.

### How It Works

```
┌─────────────────┐         ┌──────────────────┐         ┌─────────────────┐
│   PMM Server    │ ────────>│ Server-side      │ ────────>│   PostgreSQL    │
│                 │  scrape  │ postgres_exporter│  SQL    │   Database      │
│  (Prometheus)   │<────────│  (on PMM server) │<────────│ +monitor schema │
└─────────────────┘ metrics └──────────────────┘ results └─────────────────┘
```

## Data Retention Architecture

### 1. PostgreSQL-Level Retention

When using agentless monitoring with custom functions, data retention happens at multiple levels:

```sql
-- Data stored in PostgreSQL (monitor.pgbackrest_info_raw)
CREATE TABLE monitor.pgbackrest_info_raw (
    collected_at timestamptz DEFAULT now(),
    info_data jsonb
);

-- This data has its own retention policy
DELETE FROM monitor.pgbackrest_info_raw 
WHERE collected_at < now() - interval '7 days';
```

**Key Point**: The pgBackRest info must be collected and stored in PostgreSQL since the server-side exporter cannot execute shell commands on the database host.

### 2. Prometheus Retention (PMM Server)

```yaml
# PMM Prometheus retention settings
global:
  scrape_interval: 60s
  evaluation_interval: 60s
  
# Data retention in Prometheus
storage:
  tsdb:
    retention.time: 30d  # Default PMM retention
    retention.size: 100GB
```

### 3. Query Execution Flow

```mermaid
graph TD
    A[Prometheus Scrape Interval] -->|Every 60s| B[postgres_exporter]
    B -->|Executes SQL| C[monitor.pgbackrest_info\(\)]
    C -->|Reads from| D[monitor.pgbackrest_info_raw table]
    D -->|Returns| E[Current pgBackRest Status]
    E -->|Metrics| F[Prometheus Storage]
    
    G[Cron Job] -->|Every 5 min| H[pgbackrest info]
    H -->|JSON data| D
```

## Setting Up Agentless Monitoring

### Step 1: Database Preparation

Since the exporter runs remotely, we need a different approach for data collection:

```sql
-- Create a function that returns static data if no collector is running
CREATE OR REPLACE FUNCTION monitor.pgbackrest_info()
RETURNS TABLE (
    stanza text,
    backup_type text,
    backup_timestamp timestamptz,
    backup_size bigint,
    -- ... other fields
) AS $$
BEGIN
    -- Check if we have recent data
    IF EXISTS (
        SELECT 1 FROM monitor.pgbackrest_info_raw 
        WHERE collected_at > now() - interval '10 minutes'
    ) THEN
        -- Return parsed data from table
        RETURN QUERY
        WITH latest_info AS (
            SELECT info_data
            FROM monitor.pgbackrest_info_raw
            ORDER BY collected_at DESC
            LIMIT 1
        )
        -- ... parsing logic
        SELECT * FROM parsed_data;
    ELSE
        -- Return empty result or last known good data
        -- This prevents scrape errors when collector hasn't run
        RETURN QUERY
        SELECT 
            'no-data'::text,
            'unknown'::text,
            now() - interval '1 year',
            0::bigint;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

### Step 2: Remote Data Collection Options

#### Option A: Database-Triggered Collection (PostgreSQL Extensions)

```sql
-- Using pg_cron extension (if available)
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Schedule pgBackRest info collection
SELECT cron.schedule(
    'collect-pgbackrest-info',
    '*/5 * * * *',
    $$
    -- This won't work directly - pg_cron cannot execute shell commands
    -- You need a different approach
    $$
);
```

#### Option B: Remote SSH Collection

```bash
#!/bin/bash
# Run on PMM Server or management host

# Remote collection script
for host in postgresql-host1 postgresql-host2; do
    # Get pgBackRest info via SSH
    info_json=$(ssh postgres@${host} "pgbackrest info --output=json")
    
    # Insert into PostgreSQL
    PGPASSWORD=$PGPASS psql -h ${host} -U pmm -d postgres << SQL
    INSERT INTO monitor.pgbackrest_info_raw (info_data) 
    VALUES ('${info_json}'::jsonb);
SQL
done
```

#### Option C: Push-Based Collection

```bash
# On database host (via cron)
#!/bin/bash
# pgbackrest-push-metrics.sh

# Collect info
info_json=$(pgbackrest info --output=json)

# Push to PostgreSQL
psql << SQL
INSERT INTO monitor.pgbackrest_info_raw (info_data) 
VALUES ('${info_json}'::jsonb);

-- Maintain retention
DELETE FROM monitor.pgbackrest_info_raw 
WHERE collected_at < now() - interval '7 days';
SQL
```

### Step 3: Configure Server-Side Exporter

```yaml
# PMM server-side postgres_exporter configuration
# /etc/pmm-server/postgres_exporter/queries/pgbackrest.yml

pgbackrest_status:
  query: |
    SELECT
      COALESCE(stanza, 'no-data') as stanza,
      COALESCE(backup_type, 'unknown') as backup_type,
      EXTRACT(EPOCH FROM (now() - backup_timestamp))::int as seconds_since_backup,
      COALESCE(backup_size, 0) as backup_size
    FROM monitor.pgbackrest_info()
    WHERE backup_timestamp > now() - interval '30 days'
  metrics:
    - stanza:
        usage: "LABEL"
    - backup_type:
        usage: "LABEL"
    - seconds_since_backup:
        usage: "GAUGE"
    - backup_size:
        usage: "GAUGE"
  # Important: Set appropriate timeout
  timeout: 5s
```

## Retention Considerations

### 1. Multi-Level Retention Strategy

```sql
-- Create partitioned table for better retention management
CREATE TABLE monitor.pgbackrest_info_raw (
    collected_at timestamptz NOT NULL,
    info_data jsonb
) PARTITION BY RANGE (collected_at);

-- Create monthly partitions
CREATE TABLE monitor.pgbackrest_info_raw_2024_01 
PARTITION OF monitor.pgbackrest_info_raw
FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

-- Automated partition management
CREATE OR REPLACE FUNCTION monitor.manage_pgbackrest_partitions()
RETURNS void AS $$
BEGIN
    -- Drop partitions older than retention period
    -- Create new partitions as needed
END;
$$ LANGUAGE plpgsql;
```

### 2. Aggregated Data for Long-Term Retention

```sql
-- Create summary table for long-term metrics
CREATE TABLE monitor.pgbackrest_daily_summary (
    summary_date date,
    stanza text,
    successful_backups int,
    failed_backups int,
    avg_backup_size bigint,
    avg_duration_seconds int,
    PRIMARY KEY (summary_date, stanza)
);

-- Aggregate daily
INSERT INTO monitor.pgbackrest_daily_summary
SELECT 
    date_trunc('day', backup_timestamp)::date,
    stanza,
    COUNT(*) FILTER (WHERE backup_error IS NULL),
    COUNT(*) FILTER (WHERE backup_error IS NOT NULL),
    AVG(backup_size)::bigint,
    AVG(EXTRACT(EPOCH FROM backup_duration))::int
FROM monitor.pgbackrest_info()
WHERE backup_timestamp >= CURRENT_DATE
GROUP BY 1, 2
ON CONFLICT (summary_date, stanza) 
DO UPDATE SET
    successful_backups = EXCLUDED.successful_backups,
    failed_backups = EXCLUDED.failed_backups,
    avg_backup_size = EXCLUDED.avg_backup_size,
    avg_duration_seconds = EXCLUDED.avg_duration_seconds;
```

### 3. Query Optimization for Agentless Mode

```yaml
# Optimized queries for remote execution
pgbackrest_summary:
  query: |
    -- Use materialized view for better performance
    SELECT * FROM monitor.pgbackrest_summary_mv
    WHERE last_refresh > now() - interval '10 minutes'
  metrics:
    - stanza:
        usage: "LABEL"
    - metrics_age_seconds:
        usage: "GAUGE"
    - last_backup_seconds:
        usage: "GAUGE"
```

## Best Practices for Agentless Monitoring

### 1. Use Materialized Views

```sql
-- Create materialized view for expensive queries
CREATE MATERIALIZED VIEW monitor.pgbackrest_summary_mv AS
SELECT 
    stanza,
    MAX(backup_timestamp) as last_backup,
    COUNT(*) as total_backups,
    now() as last_refresh
FROM monitor.pgbackrest_info()
GROUP BY stanza;

-- Refresh periodically
CREATE OR REPLACE FUNCTION monitor.refresh_pgbackrest_mv()
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY monitor.pgbackrest_summary_mv;
END;
$$ LANGUAGE plpgsql;
```

### 2. Implement Fallback Mechanisms

```sql
-- Function with fallback data
CREATE OR REPLACE FUNCTION monitor.pgbackrest_metrics()
RETURNS TABLE (
    metric_name text,
    metric_value numeric,
    metric_timestamp timestamptz
) AS $$
BEGIN
    -- Try to get fresh data
    IF EXISTS (SELECT 1 FROM monitor.pgbackrest_info_raw 
               WHERE collected_at > now() - interval '15 minutes') THEN
        RETURN QUERY
        SELECT 'live_data'::text, 1::numeric, now();
        -- ... actual metrics
    ELSE
        -- Return cached/summary data
        RETURN QUERY
        SELECT 
            'cached_data'::text, 
            0::numeric, 
            MAX(collected_at)
        FROM monitor.pgbackrest_info_raw;
    END IF;
END;
$$ LANGUAGE plpgsql;
```

### 3. Monitor the Monitoring

```yaml
# Add meta-metrics about data freshness
pgbackrest_monitoring_health:
  query: |
    SELECT
      'pgbackrest_monitoring' as monitor_name,
      EXTRACT(EPOCH FROM (now() - MAX(collected_at)))::int as data_age_seconds,
      COUNT(*) as data_points_last_hour
    FROM monitor.pgbackrest_info_raw
    WHERE collected_at > now() - interval '1 hour'
  metrics:
    - monitor_name:
        usage: "LABEL"
    - data_age_seconds:
        usage: "GAUGE"
        description: "Age of most recent pgBackRest data"
    - data_points_last_hour:
        usage: "GAUGE"
        description: "Number of collections in last hour"
```

## Limitations and Workarounds

### Limitation 1: No Direct Command Execution
**Problem**: Server-side exporter cannot run `pgbackrest info` directly.

**Solution**: Use one of these approaches:
- Push-based collection from database host
- Pull-based collection via SSH from management server
- API-based collection if pgBackRest REST API is available

### Limitation 2: Increased Query Load
**Problem**: Every scrape executes SQL queries on the database.

**Solution**: 
- Use materialized views
- Implement query result caching
- Adjust scrape intervals appropriately

### Limitation 3: Network Latency
**Problem**: Remote queries may timeout or impact scrape duration.

**Solution**:
```yaml
# Adjust timeouts in exporter configuration
pgbackrest_queries:
  timeout: 10s  # Increase from default 5s
  max_connections: 2  # Limit concurrent connections
```

## Example Implementation Timeline

1. **Initial Setup (Day 1)**
   - Create database schema and functions
   - Deploy collection mechanism
   - Configure server-side exporter

2. **Data Accumulation (Days 2-7)**
   - Monitor data collection
   - Verify metrics accuracy
   - Adjust collection frequency

3. **Retention Implementation (Week 2)**
   - Implement partitioning if needed
   - Create aggregation jobs
   - Set up data cleanup

4. **Optimization (Week 3+)**
   - Create materialized views
   - Optimize queries
   - Implement caching

## Monitoring Architecture Decision Tree

```
Is PMM agent on database host?
├─ Yes: Use local agent with file access
└─ No: Agentless monitoring
    ├─ Can install cron on DB host?
    │  ├─ Yes: Push-based collection
    │  └─ No: Remote collection needed
    │      ├─ SSH access available?
    │      │  ├─ Yes: SSH-based collection
    │      │  └─ No: Manual process required
    └─ pgBackRest API available?
        ├─ Yes: API-based collection
        └─ No: Consider alternative monitoring
```

This agentless approach requires more setup but provides flexibility for environments where installing agents is not possible or desired.