# SLA Onboarding Scripts

This folder contains comprehensive scripts designed to assess database environments for Service Desk contract onboarding. The tools help Service Desk operators and DBAs understand the RDBMS environment they will be supporting.

## Overview

The `main_cli.sh` wrapper provides both automated and interactive modes for database environment assessment. It includes:

- **Interactive Mode**: Guided execution for Service Desk operators with step-by-step database discovery
- **Comprehensive Assessment**: Database configuration, performance metrics, security analysis, and backup validation
- **CIS Security Compliance**: PostgreSQL CIS (Center for Internet Security) benchmark automated compliance checking
- **SLA-Focused Reporting**: Automated SLA tier recommendations based on environment analysis including security posture
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
3. Optionally run PostgreSQL CIS security compliance checks
4. Guide you through the assessment process
5. Generate SLA-focused reports with security compliance scoring
6. Save results in JSON format with timestamp

### Manual Mode

```bash
# Individual database assessments
./main_cli.sh --os
./main_cli.sh --postgres  
./main_cli.sh --mysql
./main_cli.sh --mariadb

# Complete assessment with CIS compliance
./main_cli.sh --all

# Test CIS integration prerequisites  
./main_cli.sh --test-cis
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

### CIS Security Compliance (Multi-Database)
- **PostgreSQL**: Automated CIS Benchmark v17 security assessment (60+ checks)
- **MySQL**: Automated CIS Benchmark v8.0 security assessment (50+ checks)  
- **MariaDB**: Automated CIS Benchmark v10.11 security assessment (50+ checks with Galera support)
- File permission and ownership validation
- Authentication and access control analysis
- SSL/TLS configuration verification
- Logging and auditing compliance
- Security compliance scoring for SLA tier determination

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

## CIS Security Compliance

### Overview
The scripts automatically integrate CIS (Center for Internet Security) Benchmark compliance checking for multiple database platforms when assessments are run. This provides enterprise-grade security assessment capabilities across your entire database infrastructure.

### Prerequisites

#### For All Databases
1. **Python 3**: `python3` command available (3.6 or higher)

#### Python Virtual Environment Setup (Recommended)
It's strongly recommended to use a Python virtual environment to avoid dependency conflicts:

```bash
# Navigate to the sla_onboarding directory
cd sla_onboarding

# Create a virtual environment
python3 -m venv venv

# Activate the virtual environment
source venv/bin/activate

# Upgrade pip to latest version
pip install --upgrade pip

# Install all required dependencies using requirements.txt
pip install -r requirements.txt

# Alternative: Install manually
# pip install "psycopg[binary]" mysql-connector-python

# Verify installations
python -c "import psycopg; print('PostgreSQL library: OK')"
python -c "import mysql.connector; print('MySQL library: OK')"
```

**Important Notes:**
- Remember to activate the virtual environment before running CIS assessments: `source venv/bin/activate`
- The virtual environment needs to be activated each time you open a new terminal session
- To deactivate the virtual environment when done: `deactivate`

#### Manual Installation (Alternative)
If you prefer system-wide installation:

##### For PostgreSQL CIS Compliance
2. **PostgreSQL Python Library**: Install with:
   ```bash
   # Recommended - includes binary dependencies
   pip3 install "psycopg[binary]"
   
   # Alternative - may require build tools
   pip3 install psycopg2
   ```

##### For MySQL/MariaDB CIS Compliance
3. **MySQL/MariaDB Python Library**: Install with:
   ```bash
   # Option 1: MySQL Connector (recommended)
   pip3 install mysql-connector-python
   
   # Option 2: PyMySQL (lighter alternative)
   pip3 install PyMySQL
   ```

#### Required CIS Script Files
4. **CIS Script Files**: Ensure these files are in the sla_onboarding directory:
   - `pg17_CIS_checks.py` - PostgreSQL CIS compliance script
   - `mysql80_CIS_checks.py` - MySQL 8.0 CIS compliance script
   - `mariadb1011_CIS_checks.py` - MariaDB 10.11 CIS compliance script
   - Configuration files (auto-generated): `pg17_CIS_config.ini`, `mysql80_CIS_config.ini`, `mariadb1011_CIS_config.ini`

### Usage Examples

#### Basic CIS Integration

**With Virtual Environment (Recommended):**
```bash
# Activate the virtual environment first
source venv/bin/activate

# PostgreSQL assessment with automatic CIS compliance
./main_cli.sh --postgres --format=json

# MySQL assessment with automatic CIS compliance
./main_cli.sh --mysql --format=json

# MariaDB assessment with automatic CIS compliance
./main_cli.sh --mariadb --format=json

# All databases with CIS compliance
./main_cli.sh --all --format=json

# Interactive mode with optional CIS assessments for each database
./main_cli.sh --interactive

# Test all CIS prerequisites and setup
./main_cli.sh --test-cis

# Deactivate when done
deactivate
```

**Without Virtual Environment:**
```bash
# Ensure Python libraries are installed system-wide
# PostgreSQL assessment with automatic CIS compliance
./main_cli.sh --postgres --format=json

# MySQL assessment with automatic CIS compliance
./main_cli.sh --mysql --format=json

# MariaDB assessment with automatic CIS compliance
./main_cli.sh --mariadb --format=json

# All databases with CIS compliance
./main_cli.sh --all --format=json

# Interactive mode with optional CIS assessments for each database
./main_cli.sh --interactive

# Test all CIS prerequisites and setup
./main_cli.sh --test-cis
```

#### Understanding CIS Results
The CIS integration provides:
- **Security Compliance Score**: Percentage of passed security checks
- **Failed Check Details**: Specific security configurations requiring attention
- **SLA Tier Impact**: Security posture influences SLA tier recommendations
- **Remediation Guidance**: Links to CIS benchmark documentation

#### Example CIS Output

**PostgreSQL CIS Assessment:**
```
=== PostgreSQL CIS Compliance Assessment ===
CIS Compliance Score|85% (34/40 applicable checks)
CIS Compliance Level|GOOD
CIS Security Check|✓ PASSED: CIS 3.1.20: Ensure 'log_connections' is enabled
CIS Security Check|✗ FAILED: CIS 6.8: Ensure TLS is enabled and configured correctly
CIS Recommendation|Good security posture. Review failed checks for potential improvements.
```

**MySQL CIS Assessment:**
```
=== MySQL CIS Compliance Assessment ===
CIS Compliance Score|78% (39/50 applicable checks)
CIS Compliance Level|FAIR
CIS Security Check|✓ PASSED: CIS 4.7: Ensure 'sql_mode' Contains 'STRICT_TRANS_TABLES'
CIS Security Check|✗ FAILED: CIS 4.11: Ensure SSL/TLS is configured and enabled
CIS Recommendation|Adequate security but improvement recommended. Prioritize critical failed checks.
```

**MariaDB CIS Assessment:**
```
=== MariaDB CIS Compliance Assessment ===
CIS Compliance Score|92% (46/50 applicable checks)
CIS Compliance Level|EXCELLENT
CIS Security Check|✓ PASSED: CIS 4.6: Ensure 'sql_mode' Contains 'STRICT_TRANS_TABLES'
CIS Security Check|✓ PASSED: CIS 5.1: Ensure Galera cluster authentication is configured
CIS Recommendation|Security posture is excellent. Continue monitoring and maintain current standards.
```

#### SLA Integration
CIS compliance scores are automatically integrated into SLA tier assessment:
- **90%+ compliance**: Increases confidence, may raise SLA tier
- **80-89% compliance**: Good security posture
- **70-79% compliance**: Adequate security
- **<70% compliance**: Security concerns may lower SLA tier due to risk

### Troubleshooting CIS Integration

#### Common Issues

1. **Python/Library Missing**:
   ```bash
   # Install Python3 and required libraries
   sudo apt-get install python3 python3-pip python3-venv  # Debian/Ubuntu
   sudo yum install python3 python3-pip                   # RHEL/CentOS
   
   # Option 1: Use virtual environment (recommended)
   cd sla_onboarding
   python3 -m venv venv
   source venv/bin/activate
   pip install -r requirements.txt
   
   # Option 2: System-wide installation
   # For PostgreSQL
   pip3 install "psycopg[binary]"
   
   # For MySQL/MariaDB
   pip3 install mysql-connector-python
   # OR
   pip3 install PyMySQL
   ```

2. **PostgreSQL Connection Issues**:
   ```bash
   # Test PostgreSQL connectivity
   psql -h localhost -U postgres -c "SELECT version();"
   
   # Check authentication in pg_hba.conf
   sudo grep -v "^#" /etc/postgresql/*/main/pg_hba.conf
   ```

3. **MySQL Connection Issues**:
   ```bash
   # Test MySQL connectivity
   mysql -h localhost -u root -p -e "SELECT VERSION();"
   
   # Check MySQL configuration
   sudo cat /etc/mysql/mysql.conf.d/mysqld.cnf
   ```

4. **MariaDB Connection Issues**:
   ```bash
   # Test MariaDB connectivity
   mariadb -h localhost -u root -p -e "SELECT VERSION();"
   # OR
   mysql -h localhost -u root -p -e "SELECT VERSION();"
   
   # Check MariaDB configuration
   sudo cat /etc/mysql/mariadb.conf.d/50-server.cnf
   ```

5. **Permission Issues**:
   ```bash
   # PostgreSQL: Ensure postgres user can be used
   sudo -u postgres psql -c "SELECT current_user;"
   
   # MySQL/MariaDB: Test root access
   sudo mysql -e "SELECT USER();"
   
   # Create dedicated assessment users with required privileges if needed
   ```

#### Validation Commands

**With Virtual Environment:**
```bash
# Activate virtual environment
source venv/bin/activate

# Test all CIS prerequisites (PostgreSQL, MySQL, MariaDB)
./main_cli.sh --test-cis

# Debug CIS execution for individual databases
SLA_DEBUG=true ./main_cli.sh --postgres   # PostgreSQL with debug
SLA_DEBUG=true ./main_cli.sh --mysql      # MySQL with debug  
SLA_DEBUG=true ./main_cli.sh --mariadb    # MariaDB with debug

# Manual CIS script execution (for troubleshooting)
cd sla_onboarding

# PostgreSQL CIS
python pg17_CIS_checks.py

# MySQL CIS
python mysql80_CIS_checks.py

# MariaDB CIS
python mariadb1011_CIS_checks.py

# Deactivate when done
deactivate
```

**Without Virtual Environment:**
```bash
# Test all CIS prerequisites (PostgreSQL, MySQL, MariaDB)
./main_cli.sh --test-cis

# Debug CIS execution for individual databases
SLA_DEBUG=true ./main_cli.sh --postgres   # PostgreSQL with debug
SLA_DEBUG=true ./main_cli.sh --mysql      # MySQL with debug  
SLA_DEBUG=true ./main_cli.sh --mariadb    # MariaDB with debug

# Manual CIS script execution (for troubleshooting)
cd sla_onboarding

# PostgreSQL CIS
python3 pg17_CIS_checks.py

# MySQL CIS
python3 mysql80_CIS_checks.py

# MariaDB CIS
python3 mariadb1011_CIS_checks.py
```

## Virtual Environment Management

### Quick Reference

**First Time Setup:**
```bash
cd sla_onboarding
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
```

**Daily Usage:**
```bash
# Before running CIS assessments
source venv/bin/activate

# Run your assessments
./main_cli.sh --interactive

# When finished
deactivate
```

### Virtual Environment Benefits

1. **Isolation**: Prevents conflicts with system Python packages
2. **Reproducibility**: Ensures consistent dependency versions
3. **Security**: Reduces risk of package conflicts affecting other applications
4. **Flexibility**: Easy to recreate or modify without affecting system

### Virtual Environment Troubleshooting

**Virtual Environment Not Found:**
```bash
# Recreate if deleted
cd sla_onboarding
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

**Permission Issues:**
```bash
# Ensure you have write permissions in the directory
chmod 755 sla_onboarding
cd sla_onboarding
python3 -m venv venv
```

**Python Version Issues:**
```bash
# Specify Python version explicitly
python3.8 -m venv venv  # or python3.9, python3.10, etc.
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
```

**Dependency Management:**
The project includes a `requirements.txt` file for easy dependency management:
```bash
# Install all dependencies at once
pip install -r requirements.txt

# Generate updated requirements (if you add new packages)
pip freeze > requirements.txt
```

**Git Integration:**
The virtual environment directory (`venv/`) should be excluded from version control. Add to `.gitignore`:
```bash
# Add to .gitignore file
echo "venv/" >> .gitignore
echo "*.pyc" >> .gitignore
echo "__pycache__/" >> .gitignore
echo "requirements-dev.txt" >> .gitignore  # if using dev requirements
```

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
- `cis_integration.sh` - PostgreSQL CIS compliance integration and reporting
- `sla_templates.sh` - SLA tier assessment and reporting with security scoring

### System Requirements
- Bash 4.0+
- Standard Unix tools (ps, netstat, find, etc.)
- Database client tools (psql, mysql, mariadb) for full assessment
- sudo access for comprehensive system analysis

### Optional CIS Compliance Requirements
- **PostgreSQL**: Python 3.6+ with psycopg/psycopg2 library, PostgreSQL connectivity, pg17_CIS_checks.py script
- **MySQL**: Python 3.6+ with mysql-connector-python or PyMySQL library, MySQL connectivity, mysql80_CIS_checks.py script  
- **MariaDB**: Python 3.6+ with mysql-connector-python or PyMySQL library, MariaDB connectivity, mariadb1011_CIS_checks.py script
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
