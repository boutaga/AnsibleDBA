# SLA Onboarding Scripts

This folder contains scripts used to collect onboarding information for database servers.

`main_cli.sh` is a small wrapper that lets you run checks for PostgreSQL, MySQL, MariaDB or general OS information. Each database engine has its own helper script with functions that report version, data directory, memory settings and database sizes. For MySQL and MariaDB the running configuration and InnoDB status are also displayed.

The original `onboard_review.sh` script is still provided for generating TXT/CSV/JSON reports but now you can also run more targeted checks:

```bash
./main_cli.sh --postgres      # PostgreSQL checks
./main_cli.sh --mysql         # MySQL checks
./main_cli.sh --mariadb       # MariaDB checks
./main_cli.sh --os            # OS summary
./main_cli.sh --all           # run everything
```

For `onboard_review.sh`, you may specify output formats and custom binary paths using the existing flags (`--psql`, `--mysql`, `--mariadb`, ...).

Use the unified `main_cli.sh`:

```bash
./main_cli.sh --os
./main_cli.sh --postgres
./main_cli.sh --mysql
./main_cli.sh --mariadb
./main_cli.sh --all
```
