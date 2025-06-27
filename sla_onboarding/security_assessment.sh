#!/bin/bash
# Security Assessment Module for Database Environment
# Evaluates security configurations and compliance for Service Desk awareness

# PostgreSQL Security Assessment
pg_security_assessment() {
    echo "=== PostgreSQL Security Assessment ==="
    
    local conn_info=$(get_pg_connection_info)
    if [ -z "$conn_info" ]; then
        echo "Security assessment: Unable to connect to PostgreSQL"
        return 1
    fi
    
    # Authentication configuration
    echo "--- Authentication Security ---"
    assess_postgres_authentication "$conn_info"
    
    # User and role security
    echo "--- User Security ---"
    assess_postgres_users "$conn_info"
    
    # SSL/TLS configuration
    echo "--- Connection Security ---"
    assess_postgres_ssl "$conn_info"
    
    # Database permissions
    echo "--- Database Permissions ---"
    assess_postgres_permissions "$conn_info"
    
    # Security extensions and features
    echo "--- Security Features ---"
    assess_postgres_security_features "$conn_info"
    
    echo ""
}

# MySQL Security Assessment
mysql_security_assessment() {
    echo "=== MySQL Security Assessment ==="
    
    local mysql_cmd=$(get_mysql_connection_cmd)
    if [ -z "$mysql_cmd" ]; then
        echo "Security assessment: Unable to connect to MySQL"
        return 1
    fi
    
    # User authentication
    echo "--- Authentication Security ---"
    assess_mysql_authentication "$mysql_cmd"
    
    # User privileges
    echo "--- User Privileges ---"
    assess_mysql_users "$mysql_cmd"
    
    # SSL configuration
    echo "--- Connection Security ---"
    assess_mysql_ssl "$mysql_cmd"
    
    # Security plugins and features
    echo "--- Security Features ---"
    assess_mysql_security_features "$mysql_cmd"
    
    # Network security
    echo "--- Network Security ---"
    assess_mysql_network_security "$mysql_cmd"
    
    echo ""
}

# MariaDB Security Assessment
mariadb_security_assessment() {
    echo "=== MariaDB Security Assessment ==="
    
    local mariadb_cmd=$(get_mariadb_connection_cmd)
    if [ -z "$mariadb_cmd" ]; then
        echo "Security assessment: Unable to connect to MariaDB"
        return 1
    fi
    
    # Authentication security
    echo "--- Authentication Security ---"
    assess_mariadb_authentication "$mariadb_cmd"
    
    # User privileges
    echo "--- User Privileges ---"
    assess_mariadb_users "$mariadb_cmd"
    
    # SSL configuration
    echo "--- Connection Security ---"
    assess_mariadb_ssl "$mariadb_cmd"
    
    # MariaDB-specific security features
    echo "--- Security Features ---"
    assess_mariadb_security_features "$mariadb_cmd"
    
    # Galera cluster security
    if safe_mariadb_exec "$mariadb_cmd -e \"SHOW STATUS LIKE 'wsrep_cluster_size';\"" "galera check" 10 | grep -q "wsrep_cluster_size"; then
        echo "--- Galera Cluster Security ---"
        assess_mariadb_galera_security "$mariadb_cmd"
    fi
    
    echo ""
}

# PostgreSQL Authentication Assessment
assess_postgres_authentication() {
    local conn_info="$1"
    
    # Get data directory for pg_hba.conf location
    local data_dir=$(safe_postgres_exec "psql $conn_info -t -c \"SHOW data_directory;\"" "data directory" 10 2>/dev/null | tr -d ' ')
    
    if [ -n "$data_dir" ] && [ -f "$data_dir/pg_hba.conf" ]; then
        echo "Authentication Config|$data_dir/pg_hba.conf"
        
        # Check for trust authentication
        local trust_entries=$(grep -v "^#" "$data_dir/pg_hba.conf" 2>/dev/null | grep -c "trust" || echo "0")
        if [ "$trust_entries" -gt 0 ]; then
            echo "Trust Authentication|$trust_entries entries (SECURITY RISK)"
        else
            echo "Trust Authentication|No trust entries found (Good)"
        fi
        
        # Check for password authentication methods
        local password_methods=$(grep -v "^#" "$data_dir/pg_hba.conf" 2>/dev/null | grep -E "md5|scram-sha-256" | wc -l)
        echo "Password Authentication|$password_methods entries using encrypted passwords"
        
        # Check for peer/ident authentication
        local peer_methods=$(grep -v "^#" "$data_dir/pg_hba.conf" 2>/dev/null | grep -E "peer|ident" | wc -l)
        echo "System Authentication|$peer_methods entries using peer/ident"
        
    else
        echo "Authentication Config|Unable to access pg_hba.conf"
    fi
    
    # Check password encryption method
    safe_postgres_exec "psql $conn_info -t -c \"
        SELECT 'Password Encryption|' || setting 
        FROM pg_settings 
        WHERE name = 'password_encryption';\"" "password encryption" 15
}

# PostgreSQL User Security Assessment
assess_postgres_users() {
    local conn_info="$1"
    
    # Count users and roles
    safe_postgres_exec "psql $conn_info -t -c \"
        SELECT 'Total Roles|' || count(*) 
        FROM pg_roles;\"" "total roles" 15
    
    safe_postgres_exec "psql $conn_info -t -c \"
        SELECT 'Superusers|' || count(*) 
        FROM pg_roles 
        WHERE rolsuper = true;\"" "superuser count" 15
    
    safe_postgres_exec "psql $conn_info -t -c \"
        SELECT 'Login Roles|' || count(*) 
        FROM pg_roles 
        WHERE rolcanlogin = true;\"" "login roles" 15
    
    # Check for default/weak passwords (basic check)
    safe_postgres_exec "psql $conn_info -t -c \"
        SELECT 'Roles with Login|' || string_agg(rolname, ', ') 
        FROM pg_roles 
        WHERE rolcanlogin = true 
        ORDER BY rolname;\"" "login role names" 15
        
    # Check for password expiry
    safe_postgres_exec "psql $conn_info -t -c \"
        SELECT 'Password Validity|' || 
        CASE WHEN count(*) = 0 THEN 'No expiry policies set'
        ELSE count(*)::text || ' roles with expiry'
        END
        FROM pg_roles 
        WHERE rolvaliduntil IS NOT NULL;\"" "password validity" 15
}

# PostgreSQL SSL Assessment
assess_postgres_ssl() {
    local conn_info="$1"
    
    safe_postgres_exec "psql $conn_info -t -c \"
        SELECT 'SSL Status|' || 
        CASE WHEN setting = 'on' THEN 'Enabled' ELSE 'Disabled' END
        FROM pg_settings 
        WHERE name = 'ssl';\"" "ssl status" 15
    
    if safe_postgres_exec "psql $conn_info -t -c \"SELECT setting FROM pg_settings WHERE name = 'ssl';\"" "ssl check" 10 | grep -q "on"; then
        safe_postgres_exec "psql $conn_info -t -c \"
            SELECT 'SSL Cert File|' || setting 
            FROM pg_settings 
            WHERE name = 'ssl_cert_file';\"" "ssl cert file" 15
        
        safe_postgres_exec "psql $conn_info -t -c \"
            SELECT 'SSL Key File|' || setting 
            FROM pg_settings 
            WHERE name = 'ssl_key_file';\"" "ssl key file" 15
        
        safe_postgres_exec "psql $conn_info -t -c \"
            SELECT 'SSL CA File|' || setting 
            FROM pg_settings 
            WHERE name = 'ssl_ca_file';\"" "ssl ca file" 15
    fi
}

# PostgreSQL Permissions Assessment  
assess_postgres_permissions() {
    local conn_info="$1"
    
    # Check database access permissions
    safe_postgres_exec "psql $conn_info -t -c \"
        SELECT 'Databases Accessible|' || count(*) 
        FROM pg_database 
        WHERE datallowconn = true;\"" "accessible databases" 15
    
    # Check for public schema permissions
    safe_postgres_exec "psql $conn_info -t -c \"
        SELECT 'Public Schema Permissions|' || 
        CASE WHEN has_schema_privilege('public', 'public', 'CREATE') 
        THEN 'CREATE allowed for PUBLIC (review required)'
        ELSE 'CREATE restricted (good)'
        END;\"" "public schema perms" 15
}

# PostgreSQL Security Features Assessment
assess_postgres_security_features() {
    local conn_info="$1"
    
    # Check for security-related extensions
    safe_postgres_exec "psql $conn_info -t -c \"
        SELECT 'Security Extensions|' || 
        CASE WHEN count(*) = 0 THEN 'None installed'
        ELSE string_agg(extname, ', ')
        END
        FROM pg_extension 
        WHERE extname IN ('passwordcheck', 'pgaudit', 'pgcrypto', 'uuid-ossp');\"" "security extensions" 15
    
    # Check logging configuration
    safe_postgres_exec "psql $conn_info -t -c \"
        SELECT 'Connection Logging|' || setting 
        FROM pg_settings 
        WHERE name = 'log_connections';\"" "connection logging" 15
    
    safe_postgres_exec "psql $conn_info -t -c \"
        SELECT 'Statement Logging|' || setting 
        FROM pg_settings 
        WHERE name = 'log_statement';\"" "statement logging" 15
}

# MySQL Authentication Assessment
assess_mysql_authentication() {
    local mysql_cmd="$1"
    
    # Check authentication plugins
    safe_mysql_exec "$mysql_cmd -e \"
        SELECT CONCAT('Default Auth Plugin|', @@default_authentication_plugin);\"" "default auth plugin" 15
    
    # Check for users with empty passwords
    safe_mysql_exec "$mysql_cmd -e \"
        SELECT CONCAT('Empty Password Users|', COUNT(*)) 
        FROM mysql.user 
        WHERE authentication_string = '' OR password = '';\"" "empty password users" 15
    
    # Check for users with old password hashes
    safe_mysql_exec "$mysql_cmd -e \"
        SELECT CONCAT('Old Password Hash Users|', COUNT(*)) 
        FROM mysql.user 
        WHERE plugin = 'mysql_old_password' OR LENGTH(password) = 16;\"" "old password users" 15
}

# MySQL User Privileges Assessment
assess_mysql_users() {
    local mysql_cmd="$1"
    
    # Count total users
    safe_mysql_exec "$mysql_cmd -e \"
        SELECT CONCAT('Total Users|', COUNT(*)) 
        FROM mysql.user;\"" "total users" 15
    
    # Check for users with ALL privileges
    safe_mysql_exec "$mysql_cmd -e \"
        SELECT CONCAT('Users with ALL Privileges|', COUNT(*)) 
        FROM mysql.user 
        WHERE Super_priv = 'Y' OR Grant_priv = 'Y';\"" "privileged users" 15
    
    # Check for remote root access
    safe_mysql_exec "$mysql_cmd -e \"
        SELECT CONCAT('Remote Root Access|', 
        CASE WHEN COUNT(*) > 0 THEN 'ENABLED (Security Risk)' 
        ELSE 'Disabled (Good)' 
        END)
        FROM mysql.user 
        WHERE User = 'root' AND Host != 'localhost' AND Host != '127.0.0.1';\"" "remote root access" 15
    
    # Check for anonymous users
    safe_mysql_exec "$mysql_cmd -e \"
        SELECT CONCAT('Anonymous Users|', COUNT(*)) 
        FROM mysql.user 
        WHERE User = '';\"" "anonymous users" 15
}

# MySQL SSL Assessment
assess_mysql_ssl() {
    local mysql_cmd="$1"
    
    safe_mysql_exec "$mysql_cmd -e \"
        SHOW VARIABLES LIKE 'have_ssl';\" | 
        awk 'NR==2 {print \"SSL Support|\" \$2}'" "ssl support" 15
    
    if safe_mysql_exec "$mysql_cmd -e \"SELECT @@have_ssl;\"" "ssl check" 10 | grep -qi "yes"; then
        safe_mysql_exec "$mysql_cmd -e \"
            SHOW VARIABLES LIKE 'ssl_cert';\" | 
            awk 'NR==2 {print \"SSL Certificate|\" \$2}'" "ssl cert" 15
        
        safe_mysql_exec "$mysql_cmd -e \"
            SHOW VARIABLES LIKE 'ssl_key';\" | 
            awk 'NR==2 {print \"SSL Key|\" \$2}'" "ssl key" 15
    fi
}

# MySQL Security Features Assessment
assess_mysql_security_features() {
    local mysql_cmd="$1"
    
    # Check if validate_password plugin is loaded
    safe_mysql_exec "$mysql_cmd -e \"
        SELECT CONCAT('Password Validation|', 
        CASE WHEN COUNT(*) > 0 THEN 'Enabled' ELSE 'Disabled' END)
        FROM INFORMATION_SCHEMA.PLUGINS 
        WHERE PLUGIN_NAME LIKE '%password%' AND PLUGIN_STATUS = 'ACTIVE';\"" "password validation" 15
    
    # Check general log status
    safe_mysql_exec "$mysql_cmd -e \"
        SELECT CONCAT('General Logging|', @@general_log);\"" "general logging" 15
    
    # Check slow query log
    safe_mysql_exec "$mysql_cmd -e \"
        SELECT CONCAT('Slow Query Log|', @@slow_query_log);\"" "slow query log" 15
}

# MySQL Network Security Assessment
assess_mysql_network_security() {
    local mysql_cmd="$1"
    
    # Check bind address
    safe_mysql_exec "$mysql_cmd -e \"
        SHOW VARIABLES LIKE 'bind_address';\" | 
        awk 'NR==2 {print \"Bind Address|\" \$2}'" "bind address" 15
    
    # Check skip networking
    safe_mysql_exec "$mysql_cmd -e \"
        SHOW VARIABLES LIKE 'skip_networking';\" | 
        awk 'NR==2 {print \"Skip Networking|\" \$2}'" "skip networking" 15
}

# MariaDB Authentication Assessment (extends MySQL)
assess_mariadb_authentication() {
    assess_mysql_authentication "$1"
    
    # MariaDB-specific authentication plugins
    safe_mariadb_exec "$1 -e \"
        SELECT CONCAT('PAM Authentication|', 
        CASE WHEN COUNT(*) > 0 THEN 'Available' ELSE 'Not Available' END)
        FROM INFORMATION_SCHEMA.PLUGINS 
        WHERE PLUGIN_NAME = 'pam';\"" "pam authentication" 15
}

# MariaDB User Assessment (extends MySQL)
assess_mariadb_users() {
    assess_mysql_users "$1"
}

# MariaDB SSL Assessment (extends MySQL)
assess_mariadb_ssl() {
    assess_mysql_ssl "$1"
}

# MariaDB Security Features Assessment
assess_mariadb_security_features() {
    local mariadb_cmd="$1"
    
    # Check MariaDB-specific security features
    assess_mysql_security_features "$mariadb_cmd"
    
    # Check for audit plugin
    safe_mariadb_exec "$mariadb_cmd -e \"
        SELECT CONCAT('Audit Plugin|', 
        CASE WHEN COUNT(*) > 0 THEN 'Installed' ELSE 'Not Installed' END)
        FROM INFORMATION_SCHEMA.PLUGINS 
        WHERE PLUGIN_NAME LIKE '%audit%' AND PLUGIN_STATUS = 'ACTIVE';\"" "audit plugin" 15
}

# MariaDB Galera Security Assessment
assess_mariadb_galera_security() {
    local mariadb_cmd="$1"
    
    # Check Galera SSL configuration
    safe_mariadb_exec "$mariadb_cmd -e \"
        SHOW VARIABLES LIKE 'wsrep_provider_options';\" | 
        grep -o 'socket.ssl_[^;]*' | 
        awk '{print \"Galera SSL Config|\" \$0}' || 
        echo 'Galera SSL Config|Not configured'" "galera ssl" 15
    
    # Check cluster authentication
    safe_mariadb_exec "$mariadb_cmd -e \"
        SELECT CONCAT('Cluster Auth Method|', 
        CASE WHEN VARIABLE_VALUE LIKE '%auth%' THEN 'Configured' 
        ELSE 'Default (review required)' 
        END)
        FROM INFORMATION_SCHEMA.GLOBAL_VARIABLES 
        WHERE VARIABLE_NAME = 'wsrep_provider_options';\"" "cluster auth" 15
}

# System-level security assessment
system_security_assessment() {
    echo "=== System Security Assessment ==="
    
    # Firewall status
    echo "--- Network Security ---"
    if command -v ufw >/dev/null 2>&1; then
        local ufw_status=$(ufw status 2>/dev/null | head -1 | awk '{print $2}')
        echo "UFW Firewall|$ufw_status"
    elif command -v firewall-cmd >/dev/null 2>&1; then
        local firewalld_status=$(systemctl is-active firewalld 2>/dev/null || echo "inactive")
        echo "FirewallD|$firewalld_status"
    elif command -v iptables >/dev/null 2>&1; then
        local iptables_rules=$(iptables -L 2>/dev/null | grep -c "^ACCEPT\|^DROP\|^REJECT" || echo "0")
        echo "IPTables Rules|$iptables_rules rules configured"
    fi
    
    # SELinux/AppArmor status
    echo "--- Mandatory Access Control ---"
    if command -v getenforce >/dev/null 2>&1; then
        local selinux_status=$(getenforce 2>/dev/null || echo "Not available")
        echo "SELinux|$selinux_status"
    elif command -v aa-status >/dev/null 2>&1; then
        local apparmor_status=$(aa-status --enabled 2>/dev/null && echo "Enabled" || echo "Disabled")
        echo "AppArmor|$apparmor_status"
    fi
    
    # SSH configuration
    echo "--- SSH Security ---"
    if [ -f /etc/ssh/sshd_config ]; then
        local root_login=$(grep "^PermitRootLogin" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "default")
        echo "SSH Root Login|$root_login"
        
        local password_auth=$(grep "^PasswordAuthentication" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "default")
        echo "SSH Password Auth|$password_auth"
    fi
    
    echo ""
}