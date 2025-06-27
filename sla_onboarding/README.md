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
