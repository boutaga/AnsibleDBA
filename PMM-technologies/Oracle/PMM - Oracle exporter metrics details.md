---
tags:
  - PMM
  - exporter
date: 27-05-2025
---
[oracle-db-appdev-monitoring/default-metrics.toml at main · oracle/oracle-db-appdev-monitoring](https://github.com/oracle/oracle-db-appdev-monitoring/blob/main/default-metrics.toml)

## SQL definitions by metric context

### 1 — `sessions`

```sql
-- oracledb_sessions_value
SELECT status,
       type,
       COUNT(*) AS value
FROM   v$session
GROUP  BY status, type;
```


### 2 — `resource` (resource limits)

```sql
-- oracledb_resource_current_utilization
-- oracledb_resource_limit_value
SELECT resource_name,
       current_utilization,
       CASE
           WHEN TRIM(limit_value) LIKE 'UNLIMITED' THEN -1
           ELSE TRIM(limit_value)
       END AS limit_value
FROM   v$resource_limit;
```



### 3 — `asm_diskgroup`

```sql
-- oracledb_asm_diskgroup_total
-- oracledb_asm_diskgroup_free
SELECT name,
       total_mb * 1024 * 1024 AS total,
       free_mb  * 1024 * 1024 AS free
FROM   v$asm_diskgroup_stat
WHERE  EXISTS (SELECT 1
               FROM   v$datafile
               WHERE  name LIKE '+%');
```



### 4 — `activity` (core system statistics)

```sql
-- oracledb_activity_value{name='<statistic name>'}
SELECT name,
       value
FROM   v$sysstat
WHERE  name IN ('parse count (total)',
                'execute count',
                'user commits',
                'user rollbacks');
```

### 5 — `process`

```sql
-- oracledb_process_count
SELECT COUNT(*) AS count
FROM   v$process;
```



### 6 — `wait_time`

```sql
-- oracledb_wait_time_time_waited_sec_total{wait_class='<class>',con_id=<CID>}
SELECT wait_class,
       ROUND(time_waited / 100, 3) AS time_waited_sec_total,
       con_id
FROM   v$system_wait_class
WHERE  wait_class <> 'Idle';
```



### 7 — `tablespace`

```sql
-- oracledb_tablespace_bytes
-- oracledb_tablespace_max_bytes
-- oracledb_tablespace_free
-- oracledb_tablespace_used_percent
SELECT dt.tablespace_name           AS tablespace,
       dt.contents                  AS type,
       dt.block_size * dtum.used_space          AS bytes,
       dt.block_size * dtum.tablespace_size     AS max_bytes,
       dt.block_size * (dtum.tablespace_size
                         - dtum.used_space)     AS free,
       dtum.used_percent
FROM   dba_tablespace_usage_metrics dtum
JOIN   dba_tablespaces              dt
  ON   dtum.tablespace_name = dt.tablespace_name
WHERE  dt.contents <> 'TEMPORARY'
UNION
SELECT dt.tablespace_name           AS tablespace,
       'TEMPORARY'                  AS type,
       dt.tablespace_size - dt.free_space        AS bytes,
       dt.tablespace_size                          AS max_bytes,
       dt.free_space                                AS free,
       (dt.tablespace_size - dt.free_space)
/       dt.tablespace_size                         AS used_percent
FROM   dba_temp_free_space dt
ORDER  BY tablespace;
```


### 8 — `db_system` (instance-level parameters)

```sql
-- oracledb_db_system_value{name='<parameter>'}
SELECT name,
       value
FROM   v$parameter
WHERE  name IN ('cpu_count',
                'sga_max_size',
                'pga_aggregate_limit');
```


### 9 — `db_platform`

```sql
-- oracledb_db_platform_value{platform_name='<platform>'}
SELECT platform_name,
       1 AS value
FROM   v$database;
```


### 10 — `top_sql`

```sql
-- oracledb_top_sql_elapsed{sql_id='<id>',sql_text='<truncated text>'}
SELECT *
FROM (
        SELECT sql_id,
               elapsed_time / 1_000_000  AS elapsed,
               SUBSTRB(REPLACE(sql_text, CHR(0), ' '), 1, 55) AS sql_text
        FROM   v$sqlstats
        ORDER  BY elapsed_time DESC
     )
WHERE  ROWNUM <= 15;
```


### 11 — `cache_hit_ratio`

```sql
-- oracledb_cache_hit_ratio_value{cache_hit_type='<metric>'}
SELECT metric_name  AS cache_hit_type,
       value
FROM   v$sysmetric
WHERE  group_id = 2
  AND  metric_id IN (2000, 2050, 2112, 2110);
```


---



