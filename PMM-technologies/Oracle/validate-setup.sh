#!/bin/bash
# Oracle Database Monitoring Setup Validation Script
# Tests Oracle exporter configuration and metrics

set -euo pipefail

# Configuration
SERVICE_NAME="oracledb_exporter"
METRICS_PORT="9161"
CONFIG_DIR="/etc/oracledb_exporter"
BINARY_PATH="/usr/local/bin/oracledb_exporter"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results tracking
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓ PASS]${NC} $1"
    ((TESTS_PASSED++))
}

log_fail() {
    echo -e "${RED}[✗ FAIL]${NC} $1"
    ((TESTS_FAILED++))
}

log_warning() {
    echo -e "${YELLOW}[⚠ WARN]${NC} $1"
}

# Increment test counter
test_start() {
    ((TESTS_TOTAL++))
}

# Test binary installation
test_binary() {
    test_start
    log_info "Testing Oracle exporter binary installation"
    
    if [[ -f "$BINARY_PATH" ]]; then
        if [[ -x "$BINARY_PATH" ]]; then
            # Try to get version
            if timeout 5 "$BINARY_PATH" --version >/dev/null 2>&1; then
                local version=$("$BINARY_PATH" --version 2>/dev/null | head -1 || echo "unknown")
                log_success "Oracle exporter binary installed and executable (${version})"
            else
                log_success "Oracle exporter binary installed and executable (version check failed)"
            fi
        else
            log_fail "Oracle exporter binary exists but is not executable"
        fi
    else
        log_fail "Oracle exporter binary not found at $BINARY_PATH"
    fi
}

# Test user and group
test_user() {
    test_start
    log_info "Testing system user and group"
    
    if getent passwd sql_exporter >/dev/null 2>&1; then
        if getent group sql_exporter >/dev/null 2>&1; then
            log_success "System user and group 'sql_exporter' exist"
        else
            log_fail "User 'sql_exporter' exists but group does not"
        fi
    else
        log_fail "System user 'sql_exporter' does not exist"
    fi
}

# Test configuration directory and files
test_config() {
    test_start
    log_info "Testing configuration directory and files"
    
    if [[ -d "$CONFIG_DIR" ]]; then
        local perms=$(stat -c "%a" "$CONFIG_DIR" 2>/dev/null || echo "000")
        if [[ "$perms" == "750" ]]; then
            log_success "Configuration directory exists with correct permissions ($perms)"
        else
            log_warning "Configuration directory exists but permissions are $perms (expected 750)"
        fi
        
        # Check for custom metrics file
        if [[ -f "$CONFIG_DIR/custom-metrics.toml" ]]; then
            local file_perms=$(stat -c "%a" "$CONFIG_DIR/custom-metrics.toml" 2>/dev/null || echo "000")
            if [[ "$file_perms" == "640" ]]; then
                log_success "Custom metrics file exists with correct permissions ($file_perms)"
            else
                log_warning "Custom metrics file exists but permissions are $file_perms (expected 640)"
            fi
        else
            log_fail "Custom metrics file not found at $CONFIG_DIR/custom-metrics.toml"
        fi
    else
        log_fail "Configuration directory not found at $CONFIG_DIR"
    fi
}

# Test systemd service
test_service() {
    test_start
    log_info "Testing systemd service configuration"
    
    if systemctl list-unit-files | grep -q "$SERVICE_NAME.service"; then
        if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
            log_success "Systemd service is installed and enabled"
            
            # Check if service is active
            if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
                log_success "Service is currently running"
            else
                log_fail "Service is installed but not running"
                log_info "Service status:"
                systemctl status "$SERVICE_NAME" --no-pager -l || true
            fi
        else
            log_warning "Service is installed but not enabled"
        fi
    else
        log_fail "Systemd service not found"
    fi
}

# Test metrics endpoint
test_metrics_endpoint() {
    test_start
    log_info "Testing metrics endpoint"
    
    if curl -s --connect-timeout 5 "http://localhost:$METRICS_PORT/metrics" >/dev/null 2>&1; then
        log_success "Metrics endpoint is responding"
        
        # Test for specific Oracle metrics
        local metrics_output
        metrics_output=$(curl -s "http://localhost:$METRICS_PORT/metrics" 2>/dev/null || echo "")
        
        if echo "$metrics_output" | grep -q "oracle_instance_detailed_up"; then
            log_success "Oracle instance metrics are present"
        else
            log_warning "Oracle instance metrics not found (may indicate connection issues)"
        fi
        
        if echo "$metrics_output" | grep -q "oracle_dataguard_status"; then
            log_success "DataGuard metrics are present"
        else
            log_warning "DataGuard metrics not found (normal if not using DataGuard)"
        fi
        
        if echo "$metrics_output" | grep -q "oracle_cdb_tablespace_usage"; then
            log_success "CDB tablespace metrics are present"
        else
            log_warning "CDB tablespace metrics not found (normal for non-CDB databases)"
        fi
        
    else
        log_fail "Metrics endpoint not responding at http://localhost:$METRICS_PORT/metrics"
    fi
}

# Test Oracle connectivity prerequisites
test_oracle_prerequisites() {
    test_start
    log_info "Testing Oracle connectivity prerequisites"
    
    # Check for Oracle client
    if command -v sqlplus >/dev/null 2>&1; then
        log_success "Oracle SQL*Plus client is available"
    else
        log_warning "Oracle SQL*Plus not found (may use Go driver instead)"
    fi
    
    # Check environment variables
    if [[ -n "${ORACLE_HOME:-}" ]]; then
        log_info "ORACLE_HOME is set: $ORACLE_HOME"
        if [[ -d "$ORACLE_HOME" ]]; then
            log_success "ORACLE_HOME directory exists"
        else
            log_warning "ORACLE_HOME is set but directory doesn't exist"
        fi
    else
        log_info "ORACLE_HOME not set (may not be needed for Go driver)"
    fi
    
    if [[ -n "${LD_LIBRARY_PATH:-}" ]]; then
        log_info "LD_LIBRARY_PATH is set: $LD_LIBRARY_PATH"
    else
        log_info "LD_LIBRARY_PATH not set (may not be needed for Go driver)"
    fi
}

# Test service logs for errors
test_service_logs() {
    test_start
    log_info "Checking service logs for errors"
    
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        local error_count
        error_count=$(journalctl -u "$SERVICE_NAME" --since "10 minutes ago" --no-pager -q | grep -i -c "error\|failed\|fatal" || echo 0)
        
        if [[ "$error_count" -eq 0 ]]; then
            log_success "No errors found in recent service logs"
        else
            log_warning "Found $error_count error(s) in recent service logs"
            log_info "Recent errors:"
            journalctl -u "$SERVICE_NAME" --since "10 minutes ago" --no-pager -q | grep -i "error\|failed\|fatal" | tail -5 || true
        fi
    else
        log_warning "Service not running - cannot check logs"
    fi
}

# Test database connection (if environment is available)
test_database_connection() {
    test_start
    log_info "Testing database connection (if credentials available)"
    
    # Try to extract connection info from systemd service
    local service_file="/etc/systemd/system/$SERVICE_NAME.service"
    local dsn=""
    
    if [[ -f "$service_file" ]]; then
        dsn=$(grep "DATA_SOURCE_NAME" "$service_file" | sed 's/.*DATA_SOURCE_NAME="\([^"]*\)".*/\1/' || echo "")
    fi
    
    if [[ -n "$dsn" ]] && [[ "$dsn" != *"your_password"* ]] && [[ "$dsn" != *"YOUR_PASSWORD"* ]]; then
        # Extract connection components (simplified)
        if command -v sqlplus >/dev/null 2>&1; then
            local connect_string
            connect_string=$(echo "$dsn" | sed 's/oracle:\/\/\([^@]*\)@\(.*\)/\1@\2/')
            
            if echo "SELECT 'CONNECTION_TEST_OK' FROM DUAL;" | timeout 10 sqlplus -s "$connect_string" 2>/dev/null | grep -q "CONNECTION_TEST_OK"; then
                log_success "Database connection test successful"
            else
                log_warning "Database connection test failed (check credentials and network)"
            fi
        else
            log_warning "Cannot test database connection - sqlplus not available"
        fi
    else
        log_info "Skipping database connection test (credentials not configured or using defaults)"
    fi
}

# Test custom metrics configuration
test_custom_metrics_config() {
    test_start
    log_info "Testing custom metrics configuration"
    
    local config_file="$CONFIG_DIR/custom-metrics.toml"
    if [[ -f "$config_file" ]]; then
        # Check for our custom metrics
        local custom_metrics=("oracle_dataguard_status" "oracle_cdb_tablespace_usage" "oracle_rman_backup_status" "oracle_fra_usage" "oracle_asm_diskgroup_space")
        local found_metrics=0
        
        for metric in "${custom_metrics[@]}"; do
            if grep -q "$metric" "$config_file"; then
                ((found_metrics++))
            fi
        done
        
        if [[ "$found_metrics" -eq ${#custom_metrics[@]} ]]; then
            log_success "All custom metrics are configured ($found_metrics/${#custom_metrics[@]})"
        elif [[ "$found_metrics" -gt 0 ]]; then
            log_warning "Some custom metrics are configured ($found_metrics/${#custom_metrics[@]})"
        else
            log_fail "No custom metrics found in configuration"
        fi
        
        # Check TOML syntax (basic)
        if grep -q '\[\[metric\]\]' "$config_file"; then
            log_success "Configuration file has valid TOML structure"
        else
            log_warning "Configuration file may have TOML syntax issues"
        fi
    else
        log_fail "Custom metrics configuration file not found"
    fi
}

# Show detailed service information
show_service_info() {
    log_info "=== Service Information ==="
    echo
    
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        echo "Service Status:"
        systemctl status "$SERVICE_NAME" --no-pager -l || true
        echo
        
        echo "Recent Logs (last 10 lines):"
        journalctl -u "$SERVICE_NAME" -n 10 --no-pager || true
        echo
        
        echo "Service Configuration:"
        local service_file="/etc/systemd/system/$SERVICE_NAME.service"
        if [[ -f "$service_file" ]]; then
            echo "Environment variables:"
            grep "Environment=" "$service_file" | sed 's/Environment=/  /' || echo "  None configured"
            echo "ExecStart:"
            grep "ExecStart=" "$service_file" | sed 's/ExecStart=/  /' || echo "  Not found"
        fi
    else
        echo "Service is not running."
    fi
}

# Show metrics sample
show_metrics_sample() {
    log_info "=== Metrics Sample ==="
    echo
    
    if curl -s --connect-timeout 5 "http://localhost:$METRICS_PORT/metrics" >/dev/null 2>&1; then
        echo "Sample Oracle metrics:"
        curl -s "http://localhost:$METRICS_PORT/metrics" | grep "^oracle_" | head -10 || echo "No Oracle metrics found"
        echo
        
        echo "Metric counts by type:"
        local metrics_output
        metrics_output=$(curl -s "http://localhost:$METRICS_PORT/metrics" 2>/dev/null || echo "")
        
        echo "  Total metrics: $(echo "$metrics_output" | grep -c "^oracle_" || echo 0)"
        echo "  Instance metrics: $(echo "$metrics_output" | grep -c "oracle_instance" || echo 0)"
        echo "  Session metrics: $(echo "$metrics_output" | grep -c "oracle_sessions" || echo 0)"
        echo "  Tablespace metrics: $(echo "$metrics_output" | grep -c "oracle_tablespace\|oracle_cdb_tablespace" || echo 0)"
        echo "  DataGuard metrics: $(echo "$metrics_output" | grep -c "oracle_dataguard" || echo 0)"
        echo "  RMAN metrics: $(echo "$metrics_output" | grep -c "oracle_rman" || echo 0)"
        echo "  ASM metrics: $(echo "$metrics_output" | grep -c "oracle_asm" || echo 0)"
    else
        echo "Metrics endpoint not available."
    fi
}

# Main validation function
main() {
    log_info "Starting Oracle Database Monitoring Setup Validation"
    echo
    
    # Run all tests
    test_binary
    test_user
    test_config
    test_service
    test_oracle_prerequisites
    test_custom_metrics_config
    test_metrics_endpoint
    test_service_logs
    test_database_connection
    
    echo
    log_info "=== Validation Summary ==="
    echo
    echo "Tests completed: $TESTS_TOTAL"
    echo -e "Tests passed:    ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests failed:    ${RED}$TESTS_FAILED${NC}"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo
        log_success "All tests passed! Oracle monitoring setup appears to be working correctly."
    else
        echo
        log_warning "Some tests failed. Review the issues above and check the troubleshooting section in README.md"
    fi
    
    # Show additional information if requested
    if [[ "${1:-}" == "--detailed" ]] || [[ "${1:-}" == "-d" ]]; then
        echo
        show_service_info
        echo
        show_metrics_sample
    fi
    
    echo
    log_info "Next steps:"
    echo "  1. If tests failed, review the error messages and fix issues"
    echo "  2. Configure Prometheus to scrape metrics from http://localhost:$METRICS_PORT/metrics"
    echo "  3. Set up Grafana dashboards for Oracle monitoring"
    echo "  4. Configure alerting rules for critical Oracle metrics"
    echo "  5. Test with: curl http://localhost:$METRICS_PORT/metrics | grep oracle_"
    echo
    echo "For detailed information, run: $0 --detailed"
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "Oracle Database Monitoring Setup Validation Script"
        echo
        echo "Usage: $0 [OPTIONS]"
        echo
        echo "Options:"
        echo "  --detailed, -d    Show detailed service information and metrics sample"
        echo "  --help, -h        Show this help message"
        echo
        echo "This script validates the Oracle Database monitoring setup including:"
        echo "  - Binary installation and permissions"
        echo "  - System user and group configuration"
        echo "  - Configuration files and permissions"
        echo "  - Systemd service setup and status"
        echo "  - Metrics endpoint availability"
        echo "  - Basic Oracle connectivity prerequisites"
        echo "  - Custom metrics configuration"
        echo
        exit 0
        ;;
    --detailed|-d|"")
        main "$@"
        ;;
    *)
        log_fail "Unknown argument: $1"
        echo "Use $0 --help for usage information"
        exit 1
        ;;
esac