#!/bin/bash
# Configuration template for SLA onboarding scripts
# Copy this file to config.sh and modify the paths for your environment

# =============================================================================
# POSTGRESQL CONFIGURATION
# =============================================================================
# Standard pattern: /u01/app/postgres/product/MAJOR/db_MINOR
# Example: /u01/app/postgres/product/17/db_1

export PG_BASE_PATHS=(
  "/var/lib/postgresql"           # Standard Debian/Ubuntu package
  "/usr/local/pgsql"             # Standard source install
  "/opt/postgresql"              # Standard RPM package
  "/u01/app/postgres/product"    # OFA base path for binaries
  "/u02/pgdata"                  # OFA data path
  "/u03/pglogs"                  # OFA logs path (optional)
)

# =============================================================================
# MYSQL CONFIGURATION  
# =============================================================================
# Standard pattern: /u01/app/mysql/product/MAJOR.MINOR/db_INSTANCE
# Example: /u01/app/mysql/product/8.0/db_1

export MYSQL_BASE_PATHS=(
  "/usr/bin"                     # Standard package binaries
  "/usr/local/bin"               # Standard source binaries
  "/opt/mysql/bin"               # Standard MySQL binaries
  "/u01/app/mysql/product"       # OFA base path for binaries
  "/u01/app/mysql/bin"           # OFA direct binary path
)

export MYSQL_DATA_PATHS=(
  "/var/lib/mysql"               # Standard package data
  "/usr/local/mysql/data"        # Standard source data
  "/opt/mysql/data"              # Standard MySQL data
  "/u02/mysql"                   # OFA data path
  "/u03/mysql/logs"              # OFA logs path (optional)
)

# =============================================================================
# MARIADB CONFIGURATION
# =============================================================================
# Standard pattern: /u01/app/mariadb/product/MAJOR.MINOR/db_INSTANCE  
# Example: /u01/app/mariadb/product/10.11/db_1

export MARIADB_BASE_PATHS=(
  "/usr/bin"                     # Standard package binaries
  "/usr/local/bin"               # Standard source binaries
  "/opt/mariadb/bin"             # Standard MariaDB binaries
  "/u01/app/mariadb/product"     # OFA base path for binaries
  "/u01/app/mariadb/bin"         # OFA direct binary path
)

export MARIADB_DATA_PATHS=(
  "/var/lib/mysql"               # Standard package data (shared with MySQL)
  "/usr/local/mariadb/data"      # Standard source data
  "/opt/mariadb/data"            # Standard MariaDB data
  "/u02/mariadb"                 # OFA data path
  "/u03/mariadb/logs"            # OFA logs path (optional)
)

# =============================================================================
# COMMON OFA PATTERNS
# =============================================================================
# 
# Typical OFA structure:
# /u01/app/{product}/product/{version}/db_{instance}/bin/{binary}
# /u02/{product}/{version}/{alias}/{datafiles}
# /u03/{product}/{version}/{alias}/{logs}
# /u04/{product}/{version}/{alias}/{backups}
#
# Examples:
# PostgreSQL:
#   Binary:  /u01/app/postgres/product/17/db_1/bin/postgres
#   Data:    /u02/pgdata/17/main/
#   Logs:    /u03/pglogs/17/main/
#   Archive: /u04/pgarch/17/main/
#
# MySQL:
#   Binary:  /u01/app/mysql/product/8.0/db_1/bin/mysql
#   Data:    /u02/mysql/8.0/main/
#   Logs:    /u03/mysql/8.0/main/
#   Backups: /u04/mysql/8.0/main/
#
# MariaDB:
#   Binary:  /u01/app/mariadb/product/10.11/db_1/bin/mariadb
#   Data:    /u02/mariadb/10.11/galera1/
#   Logs:    /u03/mariadb/10.11/galera1/
#   Backups: /u04/mariadb/10.11/galera1/
#
# =============================================================================
