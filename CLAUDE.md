# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AnsibleDBA is an Ansible playbooks repository for Open Source DBA automation, containing two main components:

1. **sla_onboarding/** - Active shell-based database assessment tools that discover and analyze PostgreSQL, MySQL, MariaDB, and OS configurations
2. **AnsiblePMM/** - Ansible structure for PMM (Percona Monitoring and Management) automation (currently documentation/templates only)

## Key Commands

### SLA Onboarding Scripts
```bash
# Interactive mode for Service Desk operators (recommended)
./sla_onboarding/main_cli.sh --interactive

# Run all database checks with SLA assessment
./sla_onboarding/main_cli.sh --all

# Specific database checks with enhanced output formats
./sla_onboarding/main_cli.sh --postgres --format=json --output=report.json
./sla_onboarding/main_cli.sh --mysql --format=csv
./sla_onboarding/main_cli.sh --mariadb --format=text

# OS-level checks with monitoring discovery
./sla_onboarding/main_cli.sh --os

# Debug mode for troubleshooting
SLA_DEBUG=true ./sla_onboarding/main_cli.sh --all

# Individual database-specific scripts (legacy)
./sla_onboarding/postgres_checks.sh
./sla_onboarding/mysql_checks.sh
./sla_onboarding/mariadb_checks.sh
./sla_onboarding/os_checks.sh
```

### Testing and Validation
Enhanced testing capabilities now include:
- Interactive mode testing with guided database discovery
- Error handling validation with clear remediation steps
- Connectivity pre-checks before full assessment execution
- Performance metrics collection testing
- Security assessment validation
- Backup validation testing
- Monitoring discovery verification

Manual testing procedures:
- Test interactive mode: `./sla_onboarding/main_cli.sh --interactive`
- Verify error handling: Test with disconnected databases
- Validate SLA assessment: Check tier recommendations against expected results
- Test output formats: Verify text, CSV, and JSON outputs with SLA data

## Architecture and Structure

### Database Path Discovery System
The scripts support multiple installation patterns:
- **Standard package paths**: `/var/lib/postgresql`, `/var/lib/mysql`
- **OFA enterprise patterns**: `/u01/app/{product}/product/{version}/db_{instance}/`
- **Runtime discovery**: Scripts query running processes to find actual database directories
- **Custom configuration**: Via `sla_onboarding/config.sh` file

### Script Architecture Pattern
- `main_cli.sh` - Unified CLI wrapper that orchestrates database-specific checks
- Individual check scripts (`*_checks.sh`) - Database-engine-specific logic
- Shared configuration through environment variables and `config.template.sh`
- Multi-format output generation (text/CSV/JSON) built into each script

### Ansible Structure (AnsiblePMM)
Currently contains directory structure and documentation for intended roles:
- `pmm_add_service/` - Adding database services to PMM
- `pmm_remove_service/` - Removing services from PMM  
- `alerting_add/` - Managing alerting configurations
- `alerting_maintenance/` - Maintenance mode management

Note: Actual Ansible playbook implementations are not yet present - only structural templates.

## Development Patterns

### Shell Script Conventions
- Use bash with set -euo pipefail for error handling
- Support multiple output formats via `--format` parameter
- Include help text accessible via `--help`
- Use environment variables for configuration paths
- Implement runtime discovery before falling back to standard paths

### Database Discovery Logic
1. Check for custom paths in config.sh
2. Query running processes for actual runtime paths
3. Fall back to standard package installation paths
4. Support both systemd and traditional service patterns

### Output Format Standards
- **Text**: Human-readable with clear sections and labels
- **CSV**: Comma-separated with headers for spreadsheet import
- **JSON**: Structured data with consistent field naming

## Important Notes

- The sla_onboarding scripts are the actively maintained and functional component
- AnsiblePMM directory contains architecture documentation but no implemented playbooks
- No CI/CD, testing framework, or build system currently exists
- All scripts are designed for Unix/Linux environments with minimal dependencies
- GNU GPL v3 licensed - ensure any contributions maintain open source compliance