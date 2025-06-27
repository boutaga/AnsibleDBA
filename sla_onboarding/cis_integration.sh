#!/bin/bash
# PostgreSQL CIS Compliance Integration Module
# Integrates CIS PostgreSQL 17 security compliance checks with SLA onboarding scripts

# CIS compliance configuration
CIS_SCRIPT_NAME="pg17_CIS_checks.py"
CIS_CONFIG_NAME="pg17_CIS_config.ini"
CIS_OUTPUT_PREFIX="postgresql_cis_check"

# PostgreSQL CIS Compliance Check Wrapper
pg_cis_compliance_check() {
    # Skip CIS checks if explicitly disabled in interactive mode
    if [ "${INTERACTIVE_CIS_ENABLED:-}" = "false" ]; then
        echo "CIS Compliance|Skipped per user request in interactive mode"
        return 0
    fi
    
    echo "=== PostgreSQL CIS Compliance Assessment ==="
    
    local script_dir=$(dirname "$0")
    local cis_script="$script_dir/$CIS_SCRIPT_NAME"
    local cis_config="$script_dir/$CIS_CONFIG_NAME"
    local cis_passed=false
    
    # Pre-flight checks
    echo "--- CIS Compliance Pre-flight Checks ---"
    if ! validate_cis_prerequisites; then
        echo "CIS Compliance|Prerequisites not met - skipping CIS checks"
        return 1
    fi
    
    # Create or update CIS configuration
    echo "--- CIS Configuration Setup ---"
    if ! create_cis_configuration; then
        echo "CIS Compliance|Configuration setup failed - skipping CIS checks"
        return 1
    fi
    
    # Execute CIS compliance checks
    echo "--- Running CIS PostgreSQL 17 Security Compliance Checks ---"
    echo "This may take several minutes to complete..."
    
    local cis_output_file=""
    local cis_exit_code=0
    
    if cd "$script_dir" && python3 "$CIS_SCRIPT_NAME" 2>/dev/null; then
        cis_exit_code=0
        # Find the most recent CIS output file
        cis_output_file=$(ls -t ${CIS_OUTPUT_PREFIX}_*.txt 2>/dev/null | head -1)
        if [ -n "$cis_output_file" ]; then
            echo "CIS Compliance|Assessment completed successfully"
            echo "CIS Output File|$cis_output_file"
            cis_passed=true
        else
            echo "CIS Compliance|Assessment completed but output file not found"
        fi
    else
        cis_exit_code=$?
        echo "CIS Compliance|Assessment failed with exit code $cis_exit_code"
    fi
    
    # Parse and integrate CIS results
    if [ "$cis_passed" = true ] && [ -n "$cis_output_file" ]; then
        echo "--- CIS Compliance Results ---"
        parse_cis_output "$script_dir/$cis_output_file"
        
        # Generate compliance summary
        echo "--- CIS Compliance Summary ---"
        generate_cis_summary "$script_dir/$cis_output_file"
    fi
    
    echo ""
    return 0
}

# Validate CIS prerequisites
validate_cis_prerequisites() {
    local all_good=true
    
    # Check Python3 availability
    if ! command -v python3 >/dev/null 2>&1; then
        echo "CIS Prerequisites|Python3 not available"
        handle_cis_error "PYTHON_MISSING" "CIS compliance check"
        all_good=false
    else
        echo "CIS Prerequisites|Python3 available"
    fi
    
    # Check psycopg library availability
    if ! python3 -c "import psycopg" 2>/dev/null && ! python3 -c "import psycopg2" 2>/dev/null; then
        echo "CIS Prerequisites|psycopg/psycopg2 library not available"
        echo "CIS Prerequisites|Install with: pip install \"psycopg[binary]\" or pip install psycopg2"
        handle_cis_error "MISSING_DEPENDENCIES" "CIS compliance check"
        all_good=false
    else
        echo "CIS Prerequisites|PostgreSQL Python library available"
    fi
    
    # Check if CIS script exists
    local script_dir=$(dirname "$0")
    if [ ! -f "$script_dir/$CIS_SCRIPT_NAME" ]; then
        echo "CIS Prerequisites|CIS compliance script not found: $CIS_SCRIPT_NAME"
        handle_cis_error "CONFIG_NOT_FOUND" "CIS compliance check"
        all_good=false
    else
        echo "CIS Prerequisites|CIS compliance script found"
    fi
    
    # Check PostgreSQL connectivity using existing functions
    local conn_info=$(get_pg_connection_info 2>/dev/null)
    if [ -z "$conn_info" ]; then
        echo "CIS Prerequisites|PostgreSQL connectivity issues detected"
        echo "CIS Prerequisites|Basic connectivity will be attempted during CIS execution"
        # Don't fail here - let CIS script handle DB connection issues
    else
        echo "CIS Prerequisites|PostgreSQL connectivity validated"
    fi
    
    return $([ "$all_good" = true ] && echo 0 || echo 1)
}

# Create CIS configuration file from environment
create_cis_configuration() {
    local script_dir=$(dirname "$0")
    local cis_config="$script_dir/$CIS_CONFIG_NAME"
    
    # Determine PostgreSQL connection parameters
    local pg_host="${PGHOST:-localhost}"
    local pg_port="${PGPORT:-5432}"
    local pg_user="${PGUSER:-postgres}"
    local pg_database="${PGDATABASE:-postgres}"
    local pg_password="${PGPASSWORD:-}"
    
    # Try to get connection info from existing functions
    local conn_info=$(get_pg_connection_info 2>/dev/null)
    if [ -n "$conn_info" ]; then
        # Parse connection info if available
        if [[ "$conn_info" =~ -h[[:space:]]+([^[:space:]]+) ]]; then
            pg_host="${BASH_REMATCH[1]}"
        fi
        if [[ "$conn_info" =~ -p[[:space:]]+([^[:space:]]+) ]]; then
            pg_port="${BASH_REMATCH[1]}"
        fi
        if [[ "$conn_info" =~ -U[[:space:]]+([^[:space:]]+) ]]; then
            pg_user="${BASH_REMATCH[1]}"
        fi
    fi
    
    # Check for .pgpass file
    if [ -z "$pg_password" ] && [ -f "$HOME/.pgpass" ]; then
        echo "CIS Configuration|Using .pgpass file for authentication"
        pg_password="# Using .pgpass file"
    elif [ -z "$pg_password" ]; then
        echo "CIS Configuration|No password specified - will attempt peer/trust authentication"
        pg_password="# No password - attempting peer/trust auth"
    fi
    
    # Create CIS configuration file
    cat > "$cis_config" <<EOF
[postgresql]
host = $pg_host
port = $pg_port
user = $pg_user
password = $pg_password
dbname = $pg_database
EOF
    
    # Secure the configuration file
    chmod 600 "$cis_config" 2>/dev/null || true
    
    echo "CIS Configuration|Created: $cis_config"
    echo "CIS Configuration|Host: $pg_host, Port: $pg_port, User: $pg_user, DB: $pg_database"
    
    return 0
}

# Create MySQL CIS configuration file from environment
create_mysql_cis_configuration() {
    local script_dir=$(dirname "$0")
    local cis_config="$script_dir/$MYSQL_CIS_CONFIG_NAME"
    
    # Determine MySQL connection parameters
    local mysql_host="${MYSQL_HOST:-localhost}"
    local mysql_port="${MYSQL_PORT:-3306}"
    local mysql_user="${MYSQL_USER:-root}"
    local mysql_database="${MYSQL_DATABASE:-mysql}"
    local mysql_password="${MYSQL_PASSWORD:-}"
    
    # Check for .my.cnf file
    if [ -z "$mysql_password" ] && [ -f "$HOME/.my.cnf" ]; then
        echo "CIS Configuration|Using .my.cnf file for authentication"
        mysql_password="# Using .my.cnf file"
    elif [ -z "$mysql_password" ]; then
        echo "CIS Configuration|No password specified - update configuration manually"
        mysql_password="your_mysql_password"
    fi
    
    # Create CIS configuration file
    cat > "$cis_config" <<EOF
[mysql]
host = $mysql_host
port = $mysql_port
user = $mysql_user
password = $mysql_password
database = $mysql_database
EOF
    
    # Secure the configuration file
    chmod 600 "$cis_config" 2>/dev/null || true
    
    echo "CIS Configuration|Created: $cis_config"
    echo "CIS Configuration|Host: $mysql_host, Port: $mysql_port, User: $mysql_user, DB: $mysql_database"
    
    return 0
}

# Create MariaDB CIS configuration file from environment
create_mariadb_cis_configuration() {
    local script_dir=$(dirname "$0")
    local cis_config="$script_dir/$MARIADB_CIS_CONFIG_NAME"
    
    # Determine MariaDB connection parameters
    local mariadb_host="${MARIADB_HOST:-localhost}"
    local mariadb_port="${MARIADB_PORT:-3306}"
    local mariadb_user="${MARIADB_USER:-root}"
    local mariadb_database="${MARIADB_DATABASE:-mysql}"
    local mariadb_password="${MARIADB_PASSWORD:-}"
    
    # Check for .my.cnf file
    if [ -z "$mariadb_password" ] && [ -f "$HOME/.my.cnf" ]; then
        echo "CIS Configuration|Using .my.cnf file for authentication"
        mariadb_password="# Using .my.cnf file"
    elif [ -z "$mariadb_password" ]; then
        echo "CIS Configuration|No password specified - update configuration manually"
        mariadb_password="your_mariadb_password"
    fi
    
    # Create CIS configuration file
    cat > "$cis_config" <<EOF
[mariadb]
host = $mariadb_host
port = $mariadb_port
user = $mariadb_user
password = $mariadb_password
database = $mariadb_database
EOF
    
    # Secure the configuration file
    chmod 600 "$cis_config" 2>/dev/null || true
    
    echo "CIS Configuration|Created: $cis_config"
    echo "CIS Configuration|Host: $mariadb_host, Port: $mariadb_port, User: $mariadb_user, DB: $mariadb_database"
    
    return 0
}

# Parse CIS output and convert to our standard format
parse_cis_output() {
    local cis_output_file="$1"
    
    if [ ! -f "$cis_output_file" ]; then
        echo "CIS Output|Output file not found: $cis_output_file"
        return 1
    fi
    
    local current_section=""
    local check_id=""
    local check_description=""
    
    while IFS= read -r line; do
        # Detect section headers
        if [[ "$line" =~ ^Section\ [0-9]+: ]]; then
            current_section=$(echo "$line" | sed 's/^Section //')
            continue
        fi
        
        # Detect check headers
        if [[ "$line" =~ ^\[([0-9]+\.[0-9]+(\.[0-9]+)?)\]\ (.+)$ ]]; then
            check_id="${BASH_REMATCH[1]}"
            check_description="${BASH_REMATCH[3]}"
            continue
        fi
        
        # Parse check results
        if [[ "$line" =~ ^[[:space:]]*Status:[[:space:]]+(PASS|FAIL|NA)$ ]]; then
            local status="${BASH_REMATCH[1]}"
            local result_desc="CIS $check_id"
            if [ -n "$check_description" ]; then
                result_desc="$result_desc: $(echo "$check_description" | sed 's/ (Automated)//' | sed 's/ (Manual)//')"
            fi
            
            case "$status" in
                "PASS")
                    echo "CIS Security Check|✓ PASSED: $result_desc"
                    ;;
                "FAIL") 
                    echo "CIS Security Check|✗ FAILED: $result_desc"
                    ;;
                "NA")
                    echo "CIS Security Check|~ N/A: $result_desc"
                    ;;
            esac
        fi
        
        # Parse specific configuration findings
        if [[ "$line" =~ ^[[:space:]]*Actual:[[:space:]]+(.+)$ ]]; then
            local actual_value="${BASH_REMATCH[1]}"
            if [ -n "$check_id" ] && [ ${#actual_value} -lt 100 ]; then
                echo "CIS Finding|$check_id: $actual_value"
            fi
        fi
        
    done < "$cis_output_file"
}

# Generate CIS compliance summary
generate_cis_summary() {
    local cis_output_file="$1"
    
    if [ ! -f "$cis_output_file" ]; then
        echo "CIS Summary|Unable to generate summary - output file not found"
        return 1
    fi
    
    # Count results
    local total_checks=$(grep -c "Status:[[:space:]]*\(PASS\|FAIL\|NA\)" "$cis_output_file" 2>/dev/null || echo 0)
    local passed_checks=$(grep -c "Status:[[:space:]]*PASS" "$cis_output_file" 2>/dev/null || echo 0)
    local failed_checks=$(grep -c "Status:[[:space:]]*FAIL" "$cis_output_file" 2>/dev/null || echo 0)
    local na_checks=$(grep -c "Status:[[:space:]]*NA" "$cis_output_file" 2>/dev/null || echo 0)
    
    # Calculate compliance percentage
    local compliance_percentage=0
    if [ "$total_checks" -gt 0 ]; then
        # Calculate percentage of passed checks out of applicable checks (PASS + FAIL)
        local applicable_checks=$((passed_checks + failed_checks))
        if [ "$applicable_checks" -gt 0 ]; then
            compliance_percentage=$((passed_checks * 100 / applicable_checks))
        fi
    fi
    
    # Generate summary
    echo "CIS Total Checks|$total_checks security checks performed"
    echo "CIS Passed Checks|$passed_checks checks passed"
    echo "CIS Failed Checks|$failed_checks checks failed"
    echo "CIS N/A Checks|$na_checks checks not applicable"
    echo "CIS Compliance Score|${compliance_percentage}% (${passed_checks}/${applicable_checks} applicable checks)"
    
    # Determine compliance level
    local compliance_level="POOR"
    if [ "$compliance_percentage" -ge 90 ]; then
        compliance_level="EXCELLENT"
    elif [ "$compliance_percentage" -ge 80 ]; then
        compliance_level="GOOD"
    elif [ "$compliance_percentage" -ge 70 ]; then
        compliance_level="FAIR"
    elif [ "$compliance_percentage" -ge 50 ]; then
        compliance_level="NEEDS_IMPROVEMENT"
    fi
    
    echo "CIS Compliance Level|$compliance_level"
    
    # Security recommendations based on compliance level
    case "$compliance_level" in
        "EXCELLENT")
            echo "CIS Recommendation|Security posture is excellent. Continue monitoring and maintain current standards."
            ;;
        "GOOD")
            echo "CIS Recommendation|Good security posture. Review failed checks for potential improvements."
            ;;
        "FAIR")
            echo "CIS Recommendation|Adequate security but improvement recommended. Prioritize critical failed checks."
            ;;
        "NEEDS_IMPROVEMENT")
            echo "CIS Recommendation|Security posture needs improvement. Implement failed checks systematically."
            ;;
        "POOR")
            echo "CIS Recommendation|Poor security posture. Immediate attention required for critical security controls."
            ;;
    esac
    
    # Export summary for SLA integration
    export CIS_COMPLIANCE_SCORE="$compliance_percentage"
    export CIS_COMPLIANCE_LEVEL="$compliance_level"
    export CIS_TOTAL_CHECKS="$total_checks"
    export CIS_FAILED_CHECKS="$failed_checks"
}

# CIS-specific error handling
handle_cis_error() {
    local error_type="$1"
    local context="$2"
    local additional_info="${3:-}"
    
    case "$error_type" in
        "PYTHON_MISSING")
            echo "CIS Error|Python3 not available for CIS compliance checks"
            echo "CIS Remediation|Install Python3: apt-get install python3 (Debian/Ubuntu) or yum install python3 (RHEL/CentOS)"
            ;;
        "MISSING_DEPENDENCIES")
            echo "CIS Error|Required Python libraries not available"
            echo "CIS Remediation|Install psycopg: pip3 install \"psycopg[binary]\" or pip3 install psycopg2"
            ;;
        "CONFIG_NOT_FOUND")
            echo "CIS Error|CIS compliance script not found"
            echo "CIS Remediation|Ensure $CIS_SCRIPT_NAME is in the same directory as main_cli.sh"
            ;;
        "DB_CONNECTION_FAILED")
            echo "CIS Error|Database connection failed for CIS checks"
            echo "CIS Remediation|Check PostgreSQL connectivity and authentication in $CIS_CONFIG_NAME"
            ;;
        "INSUFFICIENT_PRIVILEGES")
            echo "CIS Error|Insufficient database privileges for CIS checks"
            echo "CIS Remediation|Use a superuser account or grant necessary permissions for system catalog access"
            ;;
        *)
            echo "CIS Error|Unknown error type: $error_type"
            echo "CIS Remediation|Check CIS compliance script logs and PostgreSQL connectivity"
            ;;
    esac
    
    if [ -n "$additional_info" ]; then
        echo "CIS Additional Info|$additional_info"
    fi
}

# Interactive CIS compliance check
interactive_cis_check() {
    echo ""
    echo "=== Interactive CIS Compliance Assessment ==="
    echo ""
    echo "This will run PostgreSQL CIS (Center for Internet Security) compliance checks"
    echo "to assess the security configuration of your PostgreSQL installation."
    echo ""
    echo "Prerequisites:"
    echo "  - Python3 with psycopg/psycopg2 library"
    echo "  - PostgreSQL connectivity"
    echo "  - Sufficient database privileges for security assessment"
    echo ""
    
    read -p "Run CIS compliance assessment? (y/N): " run_cis
    if [[ "$run_cis" =~ ^[Yy]$ ]]; then
        echo ""
        echo "Running CIS compliance assessment..."
        pg_cis_compliance_check
        
        echo ""
        echo "CIS compliance assessment completed."
        echo "Review the results above for security configuration recommendations."
        echo ""
        
        if [ -n "${CIS_COMPLIANCE_SCORE:-}" ]; then
            echo "Overall Compliance Score: ${CIS_COMPLIANCE_SCORE}% (${CIS_COMPLIANCE_LEVEL})"
            if [ "${CIS_FAILED_CHECKS:-0}" -gt 0 ]; then
                echo "⚠ Found ${CIS_FAILED_CHECKS} security configuration issues requiring attention"
            fi
        fi
    else
        echo "CIS compliance assessment skipped."
    fi
}

# Test CIS integration safely
test_cis_integration() {
    echo "=== Testing CIS Integration ==="
    echo ""
    
    echo "1. Testing prerequisites..."
    if validate_cis_prerequisites; then
        echo "✓ Prerequisites validation passed"
    else
        echo "✗ Prerequisites validation failed"
        return 1
    fi
    
    echo ""
    echo "2. Testing configuration creation..."
    if create_cis_configuration; then
        echo "✓ Configuration creation passed"
    else
        echo "✗ Configuration creation failed"
        return 1
    fi
    
    echo ""
    echo "3. Testing CIS script execution (dry run)..."
    local script_dir=$(dirname "$0")
    if [ -f "$script_dir/$CIS_SCRIPT_NAME" ]; then
        echo "✓ CIS script found"
        if python3 -m py_compile "$script_dir/$CIS_SCRIPT_NAME" 2>/dev/null; then
            echo "✓ CIS script syntax validation passed"
        else
            echo "✗ CIS script syntax validation failed"
            return 1
        fi
    else
        echo "✗ CIS script not found"
        return 1
    fi
    
    echo ""
    echo "CIS integration test completed successfully!"
    echo "Ready for full CIS compliance assessment."
    return 0
}