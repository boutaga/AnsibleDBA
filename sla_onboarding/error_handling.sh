#!/bin/bash
# Enhanced Error Handling and Remediation for SLA Onboarding Scripts
# Provides clear error messages and remediation steps for Service Desk operators

# Error codes and messages
declare -A ERROR_CODES=(
    ["DB_CONN_FAILED"]="Database connection failed"
    ["DB_NOT_RUNNING"]="Database service not running"
    ["INSUFFICIENT_PERMS"]="Insufficient permissions for database access"
    ["MISSING_COMMANDS"]="Required database commands not found"
    ["CONFIG_NOT_FOUND"]="Database configuration files not accessible"
    ["TIMEOUT_ERROR"]="Database operation timed out"
    ["AUTH_ERROR"]="Database authentication failed"
    ["DISK_SPACE_LOW"]="Insufficient disk space for operations"
    ["NETWORK_ERROR"]="Network connectivity issues"
    ["SERVICE_UNAVAILABLE"]="Database service unavailable"
)

declare -A REMEDIATION_STEPS=(
    ["DB_CONN_FAILED"]="1. Check if database service is running: systemctl status postgresql/mysql/mariadb
2. Verify network connectivity: telnet localhost 5432/3306
3. Check authentication credentials
4. Review database logs for connection errors
5. Escalate to DBA if service appears healthy but connections fail"

    ["DB_NOT_RUNNING"]="1. Start database service: systemctl start postgresql/mysql/mariadb
2. Check service status: systemctl status <service>
3. Review system logs: journalctl -u <service> -n 50
4. Check for resource issues (disk space, memory)
5. If service fails to start, escalate to DBA immediately"

    ["INSUFFICIENT_PERMS"]="1. Ensure running user has proper sudo permissions
2. Try running as database user: sudo -u postgres/mysql
3. Check file permissions on database directories
4. Verify user is in required groups (postgres, mysql, etc.)
5. Contact system administrator for permission adjustments"

    ["MISSING_COMMANDS"]="1. Verify database software is installed: which psql/mysql/mariadb
2. Check PATH environment variable
3. Install missing database client tools
4. For OFA installations, source environment files
5. Contact DBA for proper installation paths"

    ["CONFIG_NOT_FOUND"]="1. Check standard config locations: /etc/postgresql/, /etc/mysql/
2. Look for custom config paths in running processes
3. Check if database is running with custom config location
4. Use runtime detection: ps aux | grep postgres/mysql
5. Contact DBA for custom installation details"

    ["TIMEOUT_ERROR"]="1. Check database load: ps aux | grep postgres/mysql
2. Verify system resources: free -h, df -h
3. Check for long-running queries or locks
4. Retry operation during low-usage period
5. If persistent, escalate to DBA for performance analysis"

    ["AUTH_ERROR"]="1. Try different authentication methods (trust, peer, md5)
2. Check pg_hba.conf or mysql user permissions
3. Test with default users (postgres, root)
4. Review authentication logs
5. Request DBA assistance for user/permission setup"

    ["DISK_SPACE_LOW"]="1. Check disk usage: df -h
2. Clear temporary files if safe to do so
3. Check for large log files that can be rotated
4. Alert system administrator immediately
5. Do not proceed with operations that may increase disk usage"

    ["NETWORK_ERROR"]="1. Test basic connectivity: ping localhost
2. Check if database port is listening: netstat -tlnp | grep 5432/3306
3. Review firewall rules: iptables -L or firewall-cmd --list-all
4. Check for network interface issues
5. Contact network administrator if connectivity problems persist"

    ["SERVICE_UNAVAILABLE"]="1. Check service status across all database instances
2. Look for maintenance windows or scheduled downtime
3. Check system resources and load
4. Review recent system changes or updates
5. Escalate to DBA and system administrator immediately"
)

# Logging configuration
ERROR_LOG="/tmp/sla_onboarding_errors.log"
DEBUG_MODE=false

# Enable debug mode if environment variable is set
if [ "${SLA_DEBUG:-}" = "true" ]; then
    DEBUG_MODE=true
fi

# Initialize error handling
init_error_handling() {
    # Set up error log
    touch "$ERROR_LOG" 2>/dev/null || ERROR_LOG="/dev/null"
    
    # Set trap for unexpected errors
    trap 'handle_unexpected_error $? $LINENO "$BASH_COMMAND"' ERR
    
    log_debug "Error handling initialized"
}

# Log functions
log_error() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] ERROR: $message" | tee -a "$ERROR_LOG" >&2
}

log_warning() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] WARNING: $message" | tee -a "$ERROR_LOG" >&2
}

log_info() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] INFO: $message"
}

log_debug() {
    if [ "$DEBUG_MODE" = true ]; then
        local message="$1"
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        echo "[$timestamp] DEBUG: $message" >> "$ERROR_LOG"
    fi
}

# Handle unexpected errors
handle_unexpected_error() {
    local exit_code=$1
    local line_number=$2
    local command="$3"
    
    log_error "Unexpected error on line $line_number: $command (exit code: $exit_code)"
    
    echo ""
    echo "======================================="
    echo "         UNEXPECTED ERROR"
    echo "======================================="
    echo "An unexpected error occurred during the assessment."
    echo ""
    echo "Details:"
    echo "  Line: $line_number"
    echo "  Command: $command"
    echo "  Exit Code: $exit_code"
    echo ""
    echo "Troubleshooting Steps:"
    echo "1. Check system resources (disk space, memory)"
    echo "2. Verify database services are running"
    echo "3. Review error log: $ERROR_LOG"
    echo "4. Try running with debug mode: SLA_DEBUG=true"
    echo "5. Contact DBA support with error details"
    echo ""
    
    # Don't exit on trapped errors in interactive mode
    if [ "${interactive:-false}" = "true" ]; then
        echo "Press Enter to continue or Ctrl+C to exit..."
        read -r
        return 0
    fi
    
    exit $exit_code
}

# Report error with remediation steps
report_error() {
    local error_code="$1"
    local context="$2"
    local additional_info="${3:-}"
    
    local error_message="${ERROR_CODES[$error_code]:-Unknown error}"
    local remediation="${REMEDIATION_STEPS[$error_code]:-Contact support for assistance}"
    
    log_error "$error_message in context: $context"
    
    echo ""
    echo "======================================="
    echo "         ERROR DETECTED"
    echo "======================================="
    echo "Error: $error_message"
    echo "Context: $context"
    
    if [ -n "$additional_info" ]; then
        echo "Additional Info: $additional_info"
    fi
    
    echo ""
    echo "Remediation Steps:"
    echo "$remediation" | sed 's/^/  /'
    echo ""
    echo "If the issue persists after trying these steps:"
    echo "  - Check the error log: $ERROR_LOG"
    echo "  - Contact DBA support with this error information"
    echo "  - Include system details and recent changes"
    echo ""
    
    # In interactive mode, ask if user wants to continue
    if [ "${interactive:-false}" = "true" ]; then
        echo "Do you want to:"
        echo "  1. Continue with other checks (skip this database)"
        echo "  2. Retry this operation"
        echo "  3. Exit assessment"
        read -p "Select option (1-3): " choice
        
        case "$choice" in
            2) return 2 ;;  # Retry
            3) exit 1 ;;    # Exit
            *) return 1 ;;  # Continue/Skip
        esac
    fi
    
    return 1
}

# Database-specific error handling functions
handle_postgres_error() {
    local exit_code=$1
    local operation="$2"
    
    case $exit_code in
        1) report_error "DB_CONN_FAILED" "PostgreSQL - $operation" ;;
        2) report_error "AUTH_ERROR" "PostgreSQL - $operation" ;;
        7) report_error "DB_NOT_RUNNING" "PostgreSQL - $operation" ;;
        *) report_error "SERVICE_UNAVAILABLE" "PostgreSQL - $operation" "Exit code: $exit_code" ;;
    esac
}

handle_mysql_error() {
    local exit_code=$1
    local operation="$2"
    
    case $exit_code in
        1) report_error "AUTH_ERROR" "MySQL - $operation" ;;
        2) report_error "DB_CONN_FAILED" "MySQL - $operation" ;;
        126|127) report_error "MISSING_COMMANDS" "MySQL - $operation" ;;
        *) report_error "SERVICE_UNAVAILABLE" "MySQL - $operation" "Exit code: $exit_code" ;;
    esac
}

handle_mariadb_error() {
    local exit_code=$1
    local operation="$2"
    
    case $exit_code in
        1) report_error "AUTH_ERROR" "MariaDB - $operation" ;;
        2) report_error "DB_CONN_FAILED" "MariaDB - $operation" ;;
        126|127) report_error "MISSING_COMMANDS" "MariaDB - $operation" ;;
        *) report_error "SERVICE_UNAVAILABLE" "MariaDB - $operation" "Exit code: $exit_code" ;;
    esac
}

# Safe execution wrappers
safe_postgres_exec() {
    local command="$1"
    local description="$2"
    local timeout="${3:-30}"
    
    log_debug "Executing PostgreSQL command: $command"
    
    if timeout "$timeout" bash -c "$command" 2>/dev/null; then
        return 0
    else
        local exit_code=$?
        handle_postgres_error $exit_code "$description"
        return $exit_code
    fi
}

safe_mysql_exec() {
    local command="$1"
    local description="$2"
    local timeout="${3:-30}"
    
    log_debug "Executing MySQL command: $command"
    
    if timeout "$timeout" bash -c "$command" 2>/dev/null; then
        return 0
    else
        local exit_code=$?
        handle_mysql_error $exit_code "$description"
        return $exit_code
    fi
}

safe_mariadb_exec() {
    local command="$1"
    local description="$2"
    local timeout="${3:-30}"
    
    log_debug "Executing MariaDB command: $command"
    
    if timeout "$timeout" bash -c "$command" 2>/dev/null; then
        return 0
    else
        local exit_code=$?
        handle_mariadb_error $exit_code "$description"
        return $exit_code
    fi
}

# Pre-flight checks
check_prerequisites() {
    local issues=()
    
    # Check disk space
    local disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ "$disk_usage" -gt 90 ]; then
        issues+=("Disk space critical: ${disk_usage}% used")
    fi
    
    # Check memory
    local mem_available=$(free | awk 'NR==2{printf "%.1f", $7/$2*100}')
    if (( $(echo "$mem_available < 10" | bc -l 2>/dev/null || echo "0") )); then
        issues+=("Low memory: ${mem_available}% available")
    fi
    
    # Check basic commands
    for cmd in ps netstat df free; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            issues+=("Missing required command: $cmd")
        fi
    done
    
    if [ ${#issues[@]} -gt 0 ]; then
        echo "⚠ Pre-flight check warnings:"
        for issue in "${issues[@]}"; do
            echo "  - $issue"
        done
        echo ""
        
        if [ "${interactive:-false}" = "true" ]; then
            read -p "Continue despite warnings? (y/N): " continue_anyway
            if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
                echo "Assessment cancelled due to system issues."
                exit 1
            fi
        fi
    fi
}

# Cleanup function
cleanup_error_handling() {
    trap - ERR
    log_debug "Error handling cleanup completed"
}