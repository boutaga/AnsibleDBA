# SLA Onboarding Scripts

This folder contains scripts used to collect onboarding information for database servers.

`main_cli.sh` is a small wrapper that lets you run checks for PostgreSQL, MySQL, MariaDB or general OS information. Each database engine has its own helper script with functions that report version, data directory, memory settings and database sizes. For MySQL and MariaDB the running configuration and InnoDB status are also displayed.

Use the unified `main_cli.sh`:

```bash
./main_cli.sh --os
./main_cli.sh --postgres
./main_cli.sh --mysql
./main_cli.sh --mariadb
./main_cli.sh --all
```
