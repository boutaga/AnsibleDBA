---
tags:
  - PMM
  - exporter
  - customer-AP
date: 22-05-2025
---

---

## Installation of the Oracle exporter

Below is a **clean, end-to-end procedure** that folds the repeated commands you captured into one logical flow and explains _why_ each step matters. Feel free to copy-paste the commands, but read the explanations so you can adapt paths, versions, or security settings later.

---

## 0. Prerequisites

|What|Why|
|---|---|
|**Oracle client libraries** (Instant Client ≥ 19) available in `LD_LIBRARY_PATH`|The exporter uses OCI to connect.|
|**Prometheus server** (any recent version)|To scrape the metrics you will expose on port `9161`.|
|`curl`, `tar`, `systemd` and `sudo` access|Basic tooling needed below.|

> **Test the Oracle login** the exporter will use before you begin:  
> `sqlplus 'user/password@127.0.0.1:1521/ORCLCDB'`

---

## 1. Download and install the binary

```bash
# Download the exact release you need
wget https://github.com/iamseth/oracledb_exporter/releases/download/0.6.0/oracledb_exporter.tar.gz

# Unpack (-x extract, -v verbose, -f file, -z gzip)
tar xvfz oracledb_exporter.tar.gz

# Move the binary into PATH
sudo cp ./oracledb_exporter-0.6.0.linux-amd64/oracledb_exporter /usr/local/bin/

# Secure the binary: owned by root, no world write
sudo chown root:root /usr/local/bin/oracledb_exporter
sudo chmod 755 /usr/local/bin/oracledb_exporter

# Sanity check
/usr/local/bin/oracledb_exporter --version
```

_Why:_ keeping the exporter under `/usr/local/bin` lets systemd find it without a long path, and tight permissions ensure no unprivileged user can swap the binary.

---

## 2. Create a dedicated service account

```bash
# Create a non-login user and matching group
sudo groupadd --system sql_exporter
sudo useradd  --system \
              --home /nonexistent \
              --shell /usr/sbin/nologin \
              --gid sql_exporter \
              sql_exporter
```

_Why:_ running exporters as their own UID/GID limits blast radius if the binary is compromised.

---

## 3. Prepare configuration directory and custom metrics

```bash
# Create the directory the exporter expects
sudo mkdir -p /etc/oracledb_exporter

# Paste or edit your TOML custom-metrics file
sudo vi /etc/oracledb_exporter/custom-metrics.toml
```

Example contents (re-shown for clarity):

```toml
# /etc/oracledb_exporter/custom-metrics.toml
[[metric]]
context = "oracle_instance_status"
labels  = ["instance_name"]
metrics = [
  { value = "1", name = "up", help = "Oracle instance status (1=up)", kind = "gauge" }
]
request = "SELECT (SELECT INSTANCE_NAME FROM V$INSTANCE) AS instance_name FROM DUAL"

[[metric]]
context = "oracle_sessions"
labels  = ["status"]
metrics = [
  { value = "session_count", name = "count", help = "Number of sessions by status", kind = "gauge" }
]
request = "SELECT status, COUNT(*) AS session_count FROM v$session GROUP BY status"

[[metric]]
context = "oracle_tablespace_usage"
labels  = ["tablespace_name"]
metrics = [
  { value = "used_percent", name = "used_percent", help = "Tablespace usage in percent", kind = "gauge" }
]
request = """
SELECT
  fs.tablespace_name,
  ROUND(((df.total_space_bytes - fs.free_space_bytes) / df.total_space_bytes) * 100, 2) AS used_percent
FROM
  (SELECT tablespace_name, SUM(bytes) AS free_space_bytes FROM dba_free_space GROUP BY tablespace_name) fs
JOIN
  (SELECT tablespace_name, SUM(bytes) AS total_space_bytes FROM dba_data_files GROUP BY tablespace_name) df
ON fs.tablespace_name = df.tablespace_name
WHERE df.total_space_bytes > 0
"""
```

```bash
# Lock down ownership and permissions
sudo chown -R sql_exporter:sql_exporter /etc/oracledb_exporter
sudo chmod 750 /etc/oracledb_exporter
sudo chmod 640 /etc/oracledb_exporter/custom-metrics.toml
```

_Why:_ only the exporter should read the credentials/queries; world-readable files may leak schema details.

---

## 4. Create the systemd service unit

```bash
sudo vi /etc/systemd/system/oracledb_exporter.service
```

Paste:

```ini
[Unit]
Description=Prometheus Oracle DB Exporter
After=network-online.target
Wants=network-online.target

[Service]
User=sql_exporter
Group=sql_exporter
Type=simple
Restart=on-failure

# Oracle connection string   user/pass@host:port/servicename
Environment="DATA_SOURCE_NAME=oracle://C##PMM:pmmuser@127.0.0.1:1521/ORCLCDB"

# Comment out if the Instant Client installs its libs in the default path
#Environment="LD_LIBRARY_PATH=/usr/lib/oracle/21/client64/lib"

ExecStart=/usr/local/bin/oracledb_exporter \
  --web.listen-address=":9161" \
  --custom.metrics="/etc/oracledb_exporter/custom-metrics.toml" \
  --default.metrics=false

[Install]
WantedBy=multi-user.target
```

> **Troubleshooting invisible characters**  
> If you copied the unit file from a web page, stray non-breaking-spaces (`0xC2A0`) may sneak in.  
> Clean them with:  
> `sudo sed -i 's/\xC2\xA0/ /g' /etc/systemd/system/oracledb_exporter.service`

---

## 5. Start and enable the service

```bash
# Pick up the new unit file
sudo systemctl daemon-reload

# Enable at boot
sudo systemctl enable --now oracledb_exporter.service

# Check status and last 50 log lines
sudo systemctl status  oracledb_exporter.service
sudo journalctl -u oracledb_exporter.service -n 50 --no-pager
```

### Common startup errors

|Symptom|Likely cause|Fix|
|---|---|---|
|`sql.ErrORA-12541: TNS:no listener`|Wrong host/port in `DATA_SOURCE_NAME`|Verify `tnsping` or connect with sqlplus.|
|`cannot load shared object libclntsh.so`|Missing or mis-located Instant Client|Export `LD_LIBRARY_PATH` in the unit or install the RPM.|
|_Metrics endpoint returns 500_|Syntax error in TOML or query|Run exporter in foreground (`ExecStart` manually) to read stderr.|

---

## 6. Add scrape job to Prometheus

On your Prometheus server `prometheus.yml`:

```yaml
scrape_configs:
  - job_name: oracledb
    static_configs:
      - targets: ['db-host-ip:9161']
```

Reload Prometheus (`kill -HUP $(pidof prometheus)` or via its `/-/reload` HTTP endpoint).

---

## 7. Verify in a browser

1. `http://<exporter-host>:9161/metrics` — you should see `oracle_up 1`.
    
2. Use **Prometheus** → _Graph_ to query `oracle_instance_status_up{instance_name="ORCLCDB"}` or your custom series.
    

---

## 8. Extending the exporter

- Each new metric block in `custom-metrics.toml` translates one row per label combination into Prometheus samples.
    
- If a query returns multiple numeric columns you must **create one `[[metric]]` per numeric column** (the exporter does not emit multiple values from one block).
    
- After editing the file:
    
    ```bash
    sudo systemctl restart oracledb_exporter.service
    sudo journalctl -u oracledb_exporter -n 30 --no-pager   # watch for parse errors
    ```
    

---

## 9. Keeping up to date

```bash
# When a new version is released
systemctl stop oracledb_exporter
# Repeat section 1 with a newer tarball, overwrite binary
systemctl start oracledb_exporter
```

---

### Quick reference (one-liner per phase)

```bash
# 1) download+install (update VERSION variable as needed)
VERS=0.6.0; wget -q https://github.com/iamseth/oracledb_exporter/releases/download/${VERS}/oracledb_exporter.tar.gz \
&& tar xfz oracledb_exporter.tar.gz \
&& sudo install -o root -g root -m 755 oracledb_exporter-${VERS}.linux-amd64/oracledb_exporter /usr/local/bin/

# 2) user+group
sudo groupadd -r sql_exporter && sudo useradd -r -g sql_exporter -s /usr/sbin/nologin -d /nonexistent sql_exporter

# 3) config dir & perms
sudo mkdir -p /etc/oracledb_exporter && sudo chown -R sql_exporter:sql_exporter /etc/oracledb_exporter && sudo chmod 750 /etc/oracledb_exporter

# 4) systemd unit (as shown above)

# 5) enable & start
sudo systemctl daemon-reload && sudo systemctl enable --now oracledb_exporter
```

---





## Summary of the commands 

```bash 

cd /tmp # Or a suitable download directory
    # Replace with the actual version/link you find
wget https://github.com/iamseth/oracledb_exporter/releases/download/v0.5.0/oracledb_exporter-0.5.0.linux-amd64.tar.gz 
tar xvfz oracledb_exporter-0.5.0.linux-amd64.tar.gz


# The binary might be directly in the archive or in a subdirectory after extraction
sudo cp ./oracledb_exporter-0.5.0.linux-amd64/oracledb_exporter /usr/local/bin/
sudo chown root:root /usr/local/bin/oracledb_exporter
sudo chmod 755 /usr/local/bin/oracledb_exporter



/usr/local/bin/oracledb_exporter --version



sudo vi /etc/oracledb_exporter/custom-metrics.toml

# /etc/oracledb_exporter/custom-metrics.toml
# Example custom metrics for oracledb_exporter

[[metric]]
context = "oracle_instance_status" # A grouping name
labels = ["instance_name"] # Labels to apply to all metrics in this context
metrics = [
  { value="1", name="up", help="Oracle instance status (1=up)", kind="gauge"}
]
request = "SELECT (SELECT INSTANCE_NAME FROM V$INSTANCE) AS instance_name FROM DUAL"

[[metric]]
context = "oracle_sessions"
labels = ["status"]
metrics = [
  { value="session_count", name="count", help="Number of sessions by status", kind="gauge"}
]
request = "SELECT status, COUNT(*) AS session_count FROM v$session GROUP BY status"

# Add more [[metric]] blocks for other custom queries
# Example for tablespace (simplified, adjust as per oracledb_exporter's multi-column handling)
# You might need one [[metric]] block per value column (used_percent, total_bytes etc.) 
# or check its documentation for how it handles multiple values from one query.

[[metric]]
context = "oracle_tablespace_usage"
labels = ["tablespace_name"]
metrics = [
  { value="used_percent", name="used_percent", help="Tablespace usage in percent", kind="gauge"}
  # { value="total_mb", name="total_mb", help="Tablespace total size in MB", kind="gauge"},
  # { value="free_mb", name="free_mb", help="Tablespace free size in MB", kind="gauge"}
]
request = """
SELECT
  fs.tablespace_name,
  ROUND(((df.total_space_bytes - fs.free_space_bytes) / df.total_space_bytes) * 100, 2) AS used_percent,
  ROUND(df.total_space_bytes / 1024 / 1024) AS total_mb,
  ROUND(fs.free_space_bytes / 1024 / 1024) AS free_mb
FROM
  (SELECT tablespace_name, SUM(bytes) AS free_space_bytes FROM dba_free_space GROUP BY tablespace_name) fs
JOIN
  (SELECT tablespace_name, SUM(bytes) AS total_space_bytes FROM dba_data_files GROUP BY tablespace_name) df
ON fs.tablespace_name = df.tablespace_name
WHERE df.total_space_bytes > 0
"""


sudo vi /etc/systemd/system/oracledb_exporter.service



[Unit]
Description=Prometheus Oracle DB Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=sql_exporter # Create this user: sudo useradd -rs /bin/false sql_exporter
Group=sql_exporter # Create this group: sudo groupadd sql_exporter
Restart=on-failure
# Set your Oracle DSN here. For production, consider more secure ways like Vault/secrets management.
Environment="DATA_SOURCE_NAME=oracle://C##PMM:YourPassword@127.0.0.1:1521/ORCLCDB"
# Optional: If you are NOT using Oracle Instant Client because the exporter has a pure Go driver
# you might not need LD_LIBRARY_PATH. If it needs client libs, uncomment and set path:
# Environment="LD_LIBRARY_PATH=/usr/lib/oracle/21/client64/lib" 

ExecStart=/usr/local/bin/oracledb_exporter \
  --web.listen-address=":9161" \
  --custom.metrics="/etc/oracledb_exporter/custom-metrics.toml" \
  --default.metrics=false 
  # Add other flags as needed, e.g. --log.level

[Install]
WantedBy=multi-user.target


sudo groupadd sql_exporter
sudo useradd -rs /sbin/nologin -g sql_exporter sql_exporter



sudo systemctl daemon-reload
sudo systemctl enable oracledb_exporter.service
sudo systemctl start oracledb_exporter.service



sudo systemctl status oracledb_exporter.service
sudo journalctl -u oracledb_exporter.service -f

```









----

### Setting up the Recommended Oracle Exporter (deprecated version of the procedure)

The `iamseth/oracledb_exporter` was very popular, and its GitHub page now directs users to Oracle's official `oracle-db-appdev-monitoring` project. Recent Oracle blogs and documentation for "Oracle Database Monitoring with Prometheus and Grafana" still refer to using the `oracledb_exporter` binary (often from `iamseth`'s releases) and provide guidance around it.

This suggests that Oracle's official approach is to use a specific (possibly this existing) exporter binary, complemented by their own dashboards and best practices found in the `oracle-db-appdev-monitoring` resources.

The key advantages of `oracledb_exporter` (especially v0.5.0+) include:

- It often uses a pure Go Oracle driver, meaning **you might not need to install Oracle Instant Client binaries** on the machine running the exporter, simplifying deployment.
- It supports a `custom-metrics.toml` file (or a similar mechanism if a newer fork changed it) for defining your own SQL queries.

Here's a general procedure to set up an `oracledb_exporter`-like solution for Oracle, which aligns with what Oracle's `oracle-db-appdev-monitoring` project seems to endorse:

**Part 1: Clean Up Previous Exporter Setup**

1. **Stop and disable the old service:**
    
    

    ```
    sudo systemctl stop sql_exporter
    sudo systemctl disable sql_exporter
    ```
    
2. **Remove the old `burningalchemist/sql_exporter` binary:**
    
    Bash
    
    ```
    sudo rm -f /usr/local/bin/sql_exporter
    ```
    
3. **Remove the old source code directory:**
    
    Bash
    
    ```
    cd ~
    rm -rf sql_exporter # This was the burningalchemist clone
    ```
    
4. **Remove or rename old configuration files (optional but recommended to avoid confusion):**
    
    Bash
    
    ```
    sudo mv /etc/sql_exporter /etc/sql_exporter_old_burningalchemist 
    sudo mkdir -p /etc/oracledb_exporter # New directory for the new exporter's config
    ```
    

**Part 2: Download and Install `oracledb_exporter`**

Oracle blogs often point to the releases page of `iamseth/oracledb_exporter`. Even if the repo says "no longer maintained" by Seth, Oracle's examples are still based on it. Let's get a recent release (e.g., v0.5.0 or newer if available, as these use the Go driver).

1. **Go to the `iamseth/oracledb_exporter` releases page:** [https://github.com/iamseth/oracledb_exporter/releases](https://github.com/iamseth/oracledb_exporter/releases)
2. **Download the appropriate binary for your system (Linux AMD64).** For example, `oracledb_exporter-0.5.0.linux-amd64.tar.gz` (or the latest version).
    
    Bash
    
    ```
    cd /tmp # Or a suitable download directory
    # Replace with the actual version/link you find
    wget https://github.com/iamseth/oracledb_exporter/releases/download/v0.5.0/oracledb_exporter-0.5.0.linux-amd64.tar.gz 
    tar xvfz oracledb_exporter-0.5.0.linux-amd64.tar.gz
    ```
    
3. **Copy the binary to `/usr/local/bin/`:**
    
    Bash
    
    ```
    # The binary might be directly in the archive or in a subdirectory after extraction
    sudo cp ./oracledb_exporter-0.5.0.linux-amd64/oracledb_exporter /usr/local/bin/
    sudo chown root:root /usr/local/bin/oracledb_exporter
    sudo chmod 755 /usr/local/bin/oracledb_exporter
    ```
    
4. **Verify:**
    
    Bash
    
    ```
    /usr/local/bin/oracledb_exporter --version
    ```
    

**Part 3: Configure `oracledb_exporter`**

1. Set the Data Source Name (DSN):
    
    This exporter typically uses the DATA_SOURCE_NAME environment variable.
    
    Example: DATA_SOURCE_NAME="oracle://C##PMM:YourPassword@127.0.0.1:1521/ORCLCDB"
    
    You will set this in the systemd service file.
    
2. Create Custom Metrics Configuration File (Optional but Recommended):
    
    oracledb_exporter allows you to define custom queries. By default, it collects a set of standard metrics. If you need specific metrics (like your active sessions query), you'll use a custom metrics file. The format is often TOML-like or specified in its documentation. Oracle's oracle-db-appdev-monitoring project might provide preferred query sets.
    
    Let's create a placeholder for custom metrics, e.g., /etc/oracledb_exporter/custom-metrics.toml.
    
    The exact syntax can vary slightly between versions or forks, but iamseth/oracledb_exporter often used a format like this:
    
    Bash
    
    ```
    sudo vi /etc/oracledb_exporter/custom-metrics.toml
    ```
    
    Paste the following example content. **You'll need to adapt queries and metric names.**
    
    Ini, TOML
    
    ```
    # /etc/oracledb_exporter/custom-metrics.toml
    # Example custom metrics for oracledb_exporter
    
    [[metric]]
    context = "oracle_instance_status" # A grouping name
    labels = ["instance_name"] # Labels to apply to all metrics in this context
    metrics = [
      { value="1", name="up", help="Oracle instance status (1=up)", kind="gauge"}
    ]
    request = "SELECT (SELECT INSTANCE_NAME FROM V$INSTANCE) AS instance_name FROM DUAL"
    
    [[metric]]
    context = "oracle_sessions"
    labels = ["status"]
    metrics = [
      { value="session_count", name="count", help="Number of sessions by status", kind="gauge"}
    ]
    request = "SELECT status, COUNT(*) AS session_count FROM v$session GROUP BY status"
    
    # Add more [[metric]] blocks for other custom queries
    # Example for tablespace (simplified, adjust as per oracledb_exporter's multi-column handling)
    # You might need one [[metric]] block per value column (used_percent, total_bytes etc.) 
    # or check its documentation for how it handles multiple values from one query.
    
    [[metric]]
    context = "oracle_tablespace_usage"
    labels = ["tablespace_name"]
    metrics = [
      { value="used_percent", name="used_percent", help="Tablespace usage in percent", kind="gauge"}
      # { value="total_mb", name="total_mb", help="Tablespace total size in MB", kind="gauge"},
      # { value="free_mb", name="free_mb", help="Tablespace free size in MB", kind="gauge"}
    ]
    request = """
    SELECT
      fs.tablespace_name,
      ROUND(((df.total_space_bytes - fs.free_space_bytes) / df.total_space_bytes) * 100, 2) AS used_percent,
      ROUND(df.total_space_bytes / 1024 / 1024) AS total_mb,
      ROUND(fs.free_space_bytes / 1024 / 1024) AS free_mb
    FROM
      (SELECT tablespace_name, SUM(bytes) AS free_space_bytes FROM dba_free_space GROUP BY tablespace_name) fs
    JOIN
      (SELECT tablespace_name, SUM(bytes) AS total_space_bytes FROM dba_data_files GROUP BY tablespace_name) df
    ON fs.tablespace_name = df.tablespace_name
    WHERE df.total_space_bytes > 0
    """
    ```
    
    - **Important:** The `custom-metrics.toml` syntax is specific. Check the documentation for the `oracledb_exporter` version you download. The `metrics` array within a `[[metric]]` block defines how columns from the `request` query map to Prometheus metrics.
    - You'll pass the path to this file via a command-line flag (e.g., `--custom.metrics`).
3. **Set permissions for configuration files:**
    
    Bash
    
    ```
    sudo chown sql_exporter:sql_exporter /etc/oracledb_exporter # If you created the user 'sql_exporter'
    sudo chmod 750 /etc/oracledb_exporter
    sudo chown sql_exporter:sql_exporter /etc/oracledb_exporter/custom-metrics.toml
    sudo chmod 640 /etc/oracledb_exporter/custom-metrics.toml
    ```
    
    _(You'll create the `sql_exporter` user if it doesn't exist for the service, or use an existing appropriate user)._
    

**Part 4: Create and Configure `systemd` Service**

1. Create/edit the service file, e.g., `/etc/systemd/system/oracledb_exporter.service` (using a new name to avoid conflict if the old service file is still there).
    
    Bash
    
    ```
    sudo vi /etc/systemd/system/oracledb_exporter.service
    ```
    
    Paste and modify:
    
    Extrait de code
    
    ```
    [Unit]
    Description=Prometheus Oracle DB Exporter
    Wants=network-online.target
    After=network-online.target
    
    [Service]
    User=sql_exporter # Create this user: sudo useradd -rs /bin/false sql_exporter
    Group=sql_exporter # Create this group: sudo groupadd sql_exporter
    Restart=on-failure
    # Set your Oracle DSN here. For production, consider more secure ways like Vault/secrets management.
    Environment="DATA_SOURCE_NAME=oracle://C##PMM:YourPassword@127.0.0.1:1521/ORCLCDB"
    # Optional: If you are NOT using Oracle Instant Client because the exporter has a pure Go driver
    # you might not need LD_LIBRARY_PATH. If it needs client libs, uncomment and set path:
    # Environment="LD_LIBRARY_PATH=/usr/lib/oracle/21/client64/lib" 
    
    ExecStart=/usr/local/bin/oracledb_exporter \
      --web.listen-address=":9161" \
      --custom.metrics="/etc/oracledb_exporter/custom-metrics.toml" \
      --default.metrics=false 
      # Add other flags as needed, e.g. --log.level
    
    [Install]
    WantedBy=multi-user.target
    ```
    
    - **User/Group:** Create a dedicated `sql_exporter` user and group if you haven't:
        
        Bash
        
        ```
        sudo groupadd sql_exporter
        sudo useradd -rs /sbin/nologin -g sql_exporter sql_exporter
        ```
        
    - **`DATA_SOURCE_NAME`:** Replace with your actual DSN.
    - **`LD_LIBRARY_PATH`:** If the `oracledb_exporter` version uses a pure Go driver (like v0.5.0+ often does), you may not need Oracle Instant Client and thus not `LD_LIBRARY_PATH`. If it does require client libraries, ensure this path is correct.
    - **`ExecStart`:**
        - Points to the new binary.
        - `--web.listen-address`: Port for the exporter (e.g., `:9161` is common for `oracledb_exporter`).
        - `--custom.metrics`: Points to your custom metrics definition file.
        - `--default.metrics=false`: This flag is often used if you _only_ want your custom metrics and not the (potentially many) default ones. Set to `true` or omit to get defaults too.
        - Check `/usr/local/bin/oracledb_exporter --help` for all available flags.
2. **Reload `systemd`, enable and start the new service:**
    
    Bash
    
    ```
    sudo systemctl daemon-reload
    sudo systemctl enable oracledb_exporter.service
    sudo systemctl start oracledb_exporter.service
    ```
    
3. **Check status and logs:**
    
    Bash
    
    ```
    sudo systemctl status oracledb_exporter.service
    sudo journalctl -u oracledb_exporter.service -f
    ```
    

This procedure guides you to use an oracledb_exporter-style binary, which aligns with Oracle's recent monitoring guidelines and should be more stable. Always refer to the specific documentation of the exporter version you download and the oracle-db-appdev-monitoring project for the most accurate and up-to-date instructions.

You're right to be concerned about the burningalchemist/sql_exporter if it's giving you this much trouble for Oracle, even if it seems to work for your MS SQL Server setup.

**Regarding `burningalchemist/sql_exporter` and your MS SQL Server:**

As we discovered, the `burningalchemist/sql_exporter` binary (the one you compiled, version 0.17.3, revision `92d2102`) strictly expects its configuration YAML to have a top-level `jobs:` or `target:` key. This was confirmed by the error `"exactly one of 'jobs' and 'target' must be defined"` when you tried the `justwatch`-style YAML (with top-level `collector_name:`, `metrics:`, etc.).

This means:

- If your MS SQL Server setup is using that `justwatch`-style YAML, then the `sql_exporter` binary running for MS SQL Server **cannot be the same `burningalchemist/sql_exporter` binary** (version 0.17.3, revision `92d2102`) that you are trying to use for Oracle.
- You are likely running a different `sql_exporter` binary for MS SQL Server – perhaps an actual `justwatchcom/sql_exporter` or a similar fork that _is_ designed for that YAML structure.

It's important to use the correct configuration style for the specific exporter binary you are running. Trying to force one binary to use a config style it doesn't support will lead to these kinds of persistent errors.

**Let's focus on `oracle-db-appdev-monitoring` for your Oracle needs.**

This is the official Oracle project and the recommended path, especially since `iamseth/oracledb_exporter` (a previously popular choice) defers to it.

**Finding and Understanding `oracle-db-appdev-monitoring`:**

The primary location for this project is on GitHub:

- **Repository:** `https://github.com/oracle/oracle-db-appdev-monitoring`

From a quick review of this repository and related information:

- It provides a **metrics exporter** (often referred to as `observability-exporter` in their examples or container images) that can expose Oracle Database metrics in Prometheus format.
- It often comes with a set of default metrics.
- Custom metrics are typically defined in a `.toml` file (e.g., `custom-metrics.toml` or a user-defined name). This is different from the YAML query definitions you've been working with for the other `sql_exporter` forks.
- The exporter can be run as a standalone binary or as a Docker container. Oracle provides pre-built container images.
- Connection to the database is usually configured via environment variables (like `DB_USERNAME`, `DB_PASSWORD`, `DB_CONNECT_STRING`) when running the container or binary.

**Procedure for Setup (Conceptual Outline & Where to Find Details):**

Since providing an exact, exhaustive setup procedure here that covers every nuance of an official Oracle project would be extensive and might quickly become outdated, I'll give you the general steps and point you to where to find the authoritative instructions. **You must refer to the `oracle/oracle-db-appdev-monitoring` GitHub repository for the most accurate and up-to-date instructions.**

1. **Understand the Project Structure:**
    
    - Go to `https://github.com/oracle/oracle-db-appdev-monitoring`.
    - Read their `README.md` thoroughly. It should explain the components, including the metrics exporter.
    - Look for sections on "Exporter," "Prometheus," "Metrics," or "Observability."
2. **Obtain the Exporter:**
    
    - **Docker/Podman (Recommended if available):** Oracle often provides pre-built container images for this exporter. The GitHub README or related Oracle documentation (like Result 1.3 from my search) will specify the image name (e.g., `container-registry.oracle.com/database/observability-exporter:1.6.1` was an example version). Using a container can simplify dependency management (like Oracle Client libraries, though some modern Go drivers don't need the full client).
    - **Build from Source:** If you prefer to build from source, the repository should contain Go code and instructions (likely using `go build` or a `Makefile`). You've done this before, so the process should be familiar.
3. **Configuration:**
    
    - **Connection Details (DSN):** As seen in the search results (Result 1.3), this is typically set via environment variables when running the exporter (e.g., `DB_USERNAME`, `DB_PASSWORD`, `DB_CONNECT_STRING`). For example:
        - `DB_USERNAME=pdbadmin`
        - `DB_PASSWORD=YourActualPassword`
        - `DB_CONNECT_STRING=yourhost:1521/yourpdb_or_service_name`
    - **Metrics Definition Files:**
        - The exporter usually comes with a set of **default metrics**.
        - **Custom metrics** are defined in separate files, often in TOML format (e.g., `my-custom-metrics.toml`). The path to this file is then provided to the exporter via a command-line flag (like `--custom.metrics` or `--metrics.file` or similar – check the exporter's `--help` output) or an environment variable (like `CUSTOM_METRICS` or `DEFAULT_METRICS` if you're customizing the main set).
        - The structure of these TOML files will be specific to this exporter. Result 1.1 (referring to `iamseth/oracledb_exporter`, which `oracle-db-appdev-monitoring` is related to) mentioned:
            
            Ini, TOML
            
            ```
            # Example structure for custom metrics (likely TOML)
            [[metric]]
            context = "my_context" # Becomes part of the metric name prefix
            metricsdesc = { my_value_column = "Description for this value" }
            labels = ["label_column_from_query"]
            request = "SELECT label_column_from_query, my_value_column FROM my_table"
            ```
            
            You **must** find the exact format in the `oracle/oracle-db-appdev-monitoring` documentation.
4. **Running the Exporter:**
    
    - **Directly (if built from source):**
        
        Bash
        
        ```
        # Set environment variables for DSN
        export DB_USERNAME=your_user
        export DB_PASSWORD=your_password
        export DB_CONNECT_STRING=your_host:1521/your_service
        # Potentially set LD_LIBRARY_PATH if it needs Oracle Client libs and you're not using a native Go driver version
        
        /path/to/your/compiled/observability-exporter \
          --web.listen-address=":9161" \ # Or whatever port it uses
          --custom.metrics="/etc/oracle_exporter/custom_queries.toml" \ # Example flag
          # Add other flags as per its --help output
        ```
        
    - **Via Docker/Podman:**
        
        Bash
        
        ```
        docker run -d --rm \
          -e DB_USERNAME=your_user \
          -e DB_PASSWORD=your_password \
          -e DB_CONNECT_STRING=your_host:1521/your_service \
          -v /path/to/your/custom_metrics.toml:/etc/custom_metrics.toml \ # Mount your custom metrics
          -p 9161:9161 \
          container-registry.oracle.com/database/observability-exporter:latest \ # Use the correct image tag
          --custom.metrics="/etc/custom_metrics.toml" # Tell exporter inside container where to find it
        ```
        
        (The exact volume mounts, environment variable names, and command-line flags will depend on the specific version and documentation of the Oracle exporter image).
5. **Create/Update `systemd` Service File:**
    
    - You'll need a new service file tailored to this exporter.
    - It will use the correct `ExecStart=` line for the binary or `docker run` command.
    - Environment variables for the DSN and paths to metric definition files will be crucial.
    
    Example conceptual `systemd` service for a binary:
    
    Extrait de code
    
    ```
    [Unit]
    Description=Oracle Observability Exporter
    After=network.target
    
    [Service]
    Type=simple
    User=sql_exporter # Or a dedicated user for this exporter
    Group=sql_exporter
    Environment="DB_USERNAME=your_user"
    Environment="DB_PASSWORD=your_password"
    Environment="DB_CONNECT_STRING=your_host:1521/your_service"
    # Environment="LD_LIBRARY_PATH=/usr/lib/oracle/21/client64/lib" # If needed
    
    ExecStart=/usr/local/bin/observability-exporter \
      --web.listen-address=":9161" \
      --custom.metrics="/etc/oracle_exporter/custom_metrics.toml" \
      --log.level="info" 
      # Add other necessary flags
    
    Restart=on-failure
    
    [Install]
    WantedBy=multi-user.target
    ```
    

**To give you a concrete procedure, I need you to:**

1. Go to `https://github.com/oracle/oracle-db-appdev-monitoring`.
2. Find the specific instructions for **building or downloading their Prometheus metrics exporter binary/container**.
3. Find the documentation for **how it expects the DSN to be provided** (env vars are common).
4. Find the documentation for the **format and location of its metric definition files** (especially for custom SQL queries, likely TOML).

Once you have those details from the official source, I can help you refine the `systemd` service and give more specific advice on the configuration file structure they expect. The key is that their documentation will be the source of truth for _their_ exporter.

This approach means you'll be using an exporter directly supported by Oracle, which should be more reliable and better aligned with Oracle database features than trying to get a problematic fork to work.