# AnsibleDBA

A comprehensive collection of Ansible playbooks and shell scripts designed to help PostgreSQL, MariaDB, and MySQL DBAs automate critical production database administration tasks.

## Objective

This repository provides production-ready automation tools for database administrators managing open source database environments. The toolkit focuses on:

- **Database Assessment & Onboarding**: Automated discovery and evaluation of database configurations for SLA compliance
- **Monitoring Integration**: Streamlined setup and management of database monitoring with PMM (Percona Monitoring and Management)
- **Production Operations**: Automated maintenance, backup validation, and routine DBA tasks
- **Multi-Engine Support**: Consistent automation across PostgreSQL, MySQL, and MariaDB environments

## Key Benefits

- **Reduce Manual Effort**: Automate repetitive DBA tasks and standardize operations across environments
- **Improve Reliability**: Consistent, tested procedures reduce human error in production operations
- **Accelerate Onboarding**: Quickly assess and integrate new database instances into monitoring and management systems
- **Enterprise-Ready**: Support for both standard package installations and enterprise OFA (Optimal Flexible Architecture) deployments

## Repository Structure

### Active Components
- **`sla_onboarding/`** - Shell-based database assessment and discovery tools
- **`AnsiblePMM/`** - Ansible playbooks for PMM monitoring integration

### Supported Database Engines
- PostgreSQL (all major versions)
- MySQL (5.7+, 8.0+)
- MariaDB (10.3+)

## Quick Start

### Database Assessment
```bash
# Assess all database instances on a system
./sla_onboarding/main_cli.sh --all --format=json --output=assessment.json

# Check specific database type
./sla_onboarding/main_cli.sh --postgres --format=csv
```

### PMM Integration
```bash
# Deploy PMM monitoring (when implemented)
ansible-playbook -i inventories/production AnsiblePMM/playbooks/pmm_deploy.yml
```

## Use Cases

- **New Environment Onboarding**: Quickly discover and document database configurations
- **SLA Compliance Assessment**: Evaluate database settings against operational standards  
- **Monitoring Setup**: Automate PMM agent deployment and service registration
- **Routine Maintenance**: Standardize backup validation, log rotation, and health checks
- **Disaster Recovery**: Automate failover procedures and recovery validation

## Target Audience

- Database Administrators managing open source database environments
- DevOps engineers implementing database automation
- Site Reliability Engineers (SREs) maintaining database infrastructure
- Organizations adopting Infrastructure as Code for database management 
