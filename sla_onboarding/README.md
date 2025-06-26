# SLA Onboarding Scripts

This folder contains scripts used to collect onboarding information for database servers. The `onboard_review.sh` script gathers server and database metadata for PostgreSQL, MariaDB and MySQL instances. The output format and destination can be chosen via the command line. Supported formats are:

- **Text** (`.txt`)
- **CSV** (`.csv`)
- **JSON** (`.json`)

Run the script with optional flags:

```bash
./onboard_review.sh            # default text output in the current directory
./onboard_review.sh -f csv     # CSV output
./onboard_review.sh -f all -o /tmp  # all formats in /tmp
```

You may also provide custom paths for binaries and configuration files using `--psql`, `--mysql`, `--mariadb`, `--pgconf`, `--mysqlconf`, and `--mariadbconf`.
