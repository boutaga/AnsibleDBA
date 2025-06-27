# SLA Onboarding Scripts

This folder contains comprehensive scripts designed to assess database environments for Service Desk contract onboarding. The tools help Service Desk operators and DBAs understand the RDBMS environment they will be supporting.

## Overview

The `main_cli.sh` wrapper provides both automated and interactive modes for database environment assessment. It includes:

- **Interactive Mode**: Guided execution for Service Desk operators with step-by-step database discovery
- **Comprehensive Assessment**: Database configuration, performance metrics, security analysis, and backup validation
- **SLA-Focused Reporting**: Automated SLA tier recommendations based on environment analysis
- **Enhanced Error Handling**: Clear error messages with remediation steps for troubleshooting
- **Multi-Format Output**: Text, CSV, and JSON outputs for different use cases

## Basic Usage

### Interactive Mode (Recommended for Service Desk)

```bash
# Guided assessment with automatic database detection
./main_cli.sh --interactive
```

This mode will:
1. Detect system information and database installations
2. Test database connectivity with clear status messages
3. Guide you through the assessment process
4. Generate SLA-focused reports with recommendations
5. Save results in JSON format with timestamp

### Manual Mode

```bash
# Individual database assessments
./main_cli.sh --os
./main_cli.sh --postgres  
./main_cli.sh --mysql
./main_cli.sh --mariadb

# Complete assessment
./main_cli.sh --all
```

## Assessment Features

### SLA Tier Assessment
Automatically analyzes the environment and recommends SLA tiers based on:
- Database criticality indicators (replication, clustering)
- High availability configuration
- Database sizes and activity levels
- Production environment markers
- Support complexity requirements

SLA tiers focus on **intervention timing**:
- **CRITICAL**: 15min response, 24x7 coverage
- **HIGH**: 1hour response, business hours
- **STANDARD**: 4hours response, business hours  
- **LOW**: 24hours response, business hours

### Performance Metrics Collection
- Active connections and query performance
- Memory usage and cache hit ratios
- Replication lag monitoring
- Long-running query detection
- System resource utilization

### Security Assessment
- Authentication configuration analysis
- User privilege review
- SSL/TLS configuration validation
- Security feature detection
- Network security evaluation

### Backup Validation
- WAL archiving status (PostgreSQL)
- Binary logging configuration (MySQL/MariaDB)
- Backup file detection and validation
- Backup tool discovery
- Point-in-time recovery readiness

### Monitoring Discovery
- Detection of existing monitoring agents
- Network port scanning for monitoring services
- Configuration file discovery
- Log management system detection
- Cloud monitoring agent identification

## Output Formats

### Text Format (Default)
Human-readable output with SLA assessment summary:

```bash
./main_cli.sh --all
```

### CSV Format
Structured data suitable for spreadsheet analysis:

```bash
./main_cli.sh --all --format=csv
```

### JSON Format
Complete structured data with SLA assessment:

```bash
./main_cli.sh --all --format=json

# Write to a file
./main_cli.sh --all --format=json --output=server_report.json
```

## Error Handling and Troubleshooting

The scripts include comprehensive error handling:

- **Clear error messages** with specific problem identification
- **Remediation steps** for common database connectivity issues
- **Pre-flight checks** for system readiness
- **Retry mechanisms** for transient failures
- **Debug mode** for detailed troubleshooting: `SLA_DEBUG=true ./main_cli.sh --all`

### Common Issues and Solutions

**Database Connection Failed:**
- Check if database service is running
- Verify authentication credentials
- Review database logs for connection errors

**Insufficient Permissions:**
- Ensure proper sudo permissions
- Run as database user: `sudo -u postgres`
- Check file permissions on database directories

**Command Not Found:**
- Verify database software installation
- Check PATH environment variable
- Source environment files for OFA installations

## Service Desk Integration

### SLA Report Structure
The JSON output includes Service Desk-specific information:

```json
{
  "sla_assessment": {
    "tier": "HIGH",
    "response_time": "1hour",
    "coverage": "business_hours",
    "escalation_triggers": [...],
    "required_information": [...],
    "common_issues": [...]
  }
}
```

### Escalation Criteria
- **Immediate**: Database outages, data corruption, security incidents
- **Scheduled**: Performance tuning, schema changes, backup modifications

## Configuration

### Custom Paths
Create `config.sh` for non-standard installations:

```bash
# PostgreSQL custom paths
export PG_BASE_PATHS=(
  "/u01/app/postgres/product"
  "/custom/postgres/path"
)

# MySQL custom paths  
export MYSQL_BASE_PATHS=(
  "/u01/app/mysql/product"
  "/opt/mysql/custom"
)
```

### Environment Variables
- `SLA_DEBUG=true` - Enable debug logging
- `ERROR_LOG=/path/to/logfile` - Custom error log location

## Files and Dependencies

### Core Scripts
- `main_cli.sh` - Main wrapper with interactive mode
- `postgres_checks.sh` - PostgreSQL-specific assessments
- `mysql_checks.sh` - MySQL-specific assessments  
- `mariadb_checks.sh` - MariaDB-specific assessments
- `os_checks.sh` - Operating system assessments

### Enhancement Modules
- `error_handling.sh` - Enhanced error handling and remediation
- `performance_metrics.sh` - Database and system performance collection
- `backup_validation.sh` - Backup configuration and file validation
- `security_assessment.sh` - Security configuration analysis
- `sla_templates.sh` - SLA tier assessment and reporting

### System Requirements
- Bash 4.0+
- Standard Unix tools (ps, netstat, find, etc.)
- Database client tools (psql, mysql, mariadb) for full assessment
- sudo access for comprehensive system analysis
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
