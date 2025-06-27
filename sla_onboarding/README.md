# SLA Onboarding Scripts

This folder contains scripts used to collect onboarding information for database servers.

`main_cli.sh` is a small wrapper that lets you run checks for PostgreSQL, MySQL, MariaDB or general OS information. Each database engine has its own helper script with functions that report version, data directory, memory settings and database sizes. For MySQL and MariaDB the running configuration and InnoDB status are also displayed.

## Basic Usage

Use the unified `main_cli.sh`:

```bash
./main_cli.sh --os
./main_cli.sh --postgres
./main_cli.sh --mysql
./main_cli.sh --mariadb
./main_cli.sh --all
```

## Output Formats

The script supports multiple output formats:

```bash
# Default text output
./main_cli.sh --all

# Export to CSV format
./main_cli.sh --all --format=csv

# Export to JSON format
./main_cli.sh --all --format=json

# Write to a file
./main_cli.sh --all --format=json --output=server_report.json
```

The CSV format is suitable for importing into spreadsheet applications, while the JSON format is ideal for integrating with other automation tools or creating web dashboards.

## Custom Path Configuration

The scripts are designed to work with both standard package installations and custom OFA-style layouts. You can customize the search paths for your environment:

1. **Copy the configuration template:**
   ```bash
   cp config.template.sh config.sh
   ```

2. **Edit config.sh to match your environment:**
   ```bash
   # Example OFA-style paths
   export PG_BASE_PATHS=(
     "/u01/app/postgres/product"    # OFA binaries
     "/u02/pgdata"                  # OFA data
   )
   
   export MYSQL_BASE_PATHS=(
     "/u01/app/mysql/product"       # OFA binaries  
     "/u01/app/mysql/bin"          # Direct binary path
   )
   ```

3. **The script will automatically detect common patterns:**
   - Version directories: `/u01/app/postgres/product/17/db_1/`
   - Alias directories: `/u02/pgdata/17/main/`
   - Instance directories: `/u02/mysql/8.0/primary/`

## Supported Path Patterns

### Standard Package Installations
- **PostgreSQL**: `/var/lib/postgresql/`, `/usr/local/pgsql/`
- **MySQL**: `/var/lib/mysql/`, `/opt/mysql/`
- **MariaDB**: `/var/lib/mysql/`, `/opt/mariadb/`

### OFA-Style Custom Installations
- **Binaries**: `/u01/app/{product}/product/{version}/db_{instance}/bin/`
- **Data**: `/u02/{product}/{version}/{alias}/`
- **Examples**:
  - PostgreSQL: `/u01/app/postgres/product/17/db_1/bin/postgres`
  - MySQL: `/u01/app/mysql/product/8.0/db_1/bin/mysql`
  - MariaDB: `/u01/app/mariadb/product/10.11/db_1/bin/mariadb`

The scripts will automatically discover running instances and query them for actual runtime paths, making them suitable for complex enterprise environments.
