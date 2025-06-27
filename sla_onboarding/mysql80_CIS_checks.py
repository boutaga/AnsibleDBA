import subprocess
import os
import configparser
import datetime
import sys
import re

try:
    # Try to import mysql-connector-python first (most common)
    try:
        import mysql.connector
        from mysql.connector import Error as MySQLError
        MYSQL_LIB = 'mysql.connector'
    except ImportError:
        # Fall back to PyMySQL
        import pymysql
        from pymysql import Error as MySQLError
        MYSQL_LIB = 'pymysql'
        # Make PyMySQL compatible with mysql.connector interface
        mysql = type('mysql', (), {})()
        mysql.connector = pymysql

except ImportError:
    print("Error: A MySQL Python library is required.")
    print("Please install one of: pip install mysql-connector-python OR pip install PyMySQL")
    sys.exit(1)

# --- Configuration ---
CONFIG_FILE = 'mysql80_CIS_config.ini'
TIMESTAMP = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
OUTPUT_FILE = f'mysql80_cis_check_{TIMESTAMP}.txt'
MYSQL_VERSION = "8.0"  # Target MySQL version
MYSQL_USER = "mysql"   # Default OS user for MySQL
MYSQL_GROUP = "mysql"  # Default OS group for MySQL

# --- Helper Functions ---

def write_output(line):
    """Appends a line to the output file and prints to console."""
    print(line)
    with open(OUTPUT_FILE, 'a', encoding='utf-8') as f:
        f.write(line + '\n')

def run_shell_command(command, check_output=True, use_sudo=False, ignore_errors=False):
    """Executes a shell command and returns its output or exit code."""
    original_command = command
    if use_sudo:
        command = f"sudo {command}"
    try:
        run_check = (not ignore_errors)
        result = subprocess.run(command, shell=True, check=run_check, capture_output=True, text=True, errors='ignore')

        if check_output:
            if result.returncode != 0 and ignore_errors:
                return f"CMD_ERROR: Exit Code {result.returncode} - {result.stderr.strip() or result.stdout.strip()}"
            return result.stdout.strip()
        else:
            return result.returncode == 0

    except subprocess.CalledProcessError as e:
        write_output(f"  Error running command '{original_command}': {e.stderr or e.stdout}")
        if check_output:
            return f"CMD_ERROR: {e.stderr or e.stdout}"
        else:
            return False
    except FileNotFoundError as e:
        write_output(f"  Error: Command not found for '{original_command}': {e}")
        if check_output:
            return "CMD_ERROR: Command not found"
        else:
            return False
    except Exception as e:
        write_output(f"  Unexpected error running command '{original_command}': {e}")
        if check_output:
            return f"CMD_ERROR: Unexpected {e}"
        else:
            return False

def execute_sql(cursor, sql_query, params=None, fetch_one=False):
    """Executes a MySQL query and returns the result."""
    if not cursor:
        return "SQL_ERROR: No database connection"
    try:
        cursor.execute(sql_query, params)
        if fetch_one:
            result = cursor.fetchone()
            return result[0] if result else None
        else:
            return cursor.fetchall()
    except MySQLError as err:
        write_output(f"  Error executing SQL '{sql_query}': {err}")
        return f"SQL_ERROR: {err}"
    except Exception as e:
        write_output(f"  Unexpected error executing SQL '{sql_query}': {e}")
        return f"SQL_ERROR: Unexpected {e}"

def check_mysql_variable(cursor, variable_name, expected_value, comparison='=='):
    """Checks a MySQL system variable against an expected value."""
    sql = f"SHOW VARIABLES LIKE '{variable_name}';"
    result = execute_sql(cursor, sql)
    status = "FAIL"
    actual_value = "Not Found"
    
    if isinstance(result, str) and result.startswith("SQL_ERROR:"):
        actual_value = result
    elif result and len(result) > 0:
        actual_value = result[0][1]  # Get the value from SHOW VARIABLES result
        
        # Convert actual_value for comparison
        converted_actual = actual_value
        try:
            if isinstance(expected_value, bool):
                # MySQL returns 'ON'/'OFF' for booleans
                converted_actual = actual_value.upper() == 'ON'
            elif isinstance(expected_value, int):
                converted_actual = int(actual_value)
            elif isinstance(expected_value, float):
                converted_actual = float(actual_value)
        except (ValueError, TypeError):
            pass  # Use string comparison if conversion fails

        # Perform comparison
        try:
            passed = False
            if comparison == '==':
                passed = converted_actual == expected_value
            elif comparison == '!=':
                passed = converted_actual != expected_value
            elif comparison == '>=':
                passed = converted_actual >= expected_value
            elif comparison == '<=':
                passed = converted_actual <= expected_value
            elif comparison == '>':
                passed = converted_actual > expected_value
            elif comparison == '<':
                passed = converted_actual < expected_value
            elif comparison == 'in':
                passed = str(expected_value) in str(actual_value)
            elif comparison == 'not_in':
                passed = str(expected_value) not in str(actual_value)
            elif comparison == 'is_set':
                passed = actual_value is not None and actual_value != ''
            elif comparison == 'matches_pattern':
                passed = re.search(expected_value, str(actual_value)) is not None

            if passed:
                status = "PASS"
        except Exception as e:
            write_output(f"  Warning: Comparison error for {variable_name}: {e}")

    write_output(f"  Checking: {variable_name}")
    write_output(f"  Expected: {comparison} {expected_value}")
    write_output(f"  Actual:   {actual_value}")
    write_output(f"  Status:   {status}")
    return status == "PASS"

def check_file_permissions(path, expected_perms_regex, owner, group, is_dir=False, use_sudo=True):
    """Checks file/directory permissions and ownership."""
    if not path or path == 'NULL':
        write_output(f"  Path is not set or invalid: {path}")
        write_output(f"  Status:   FAIL (Path Invalid)")
        return False

    ls_command = f"ls -ld {path}" if is_dir else f"ls -l {path}"
    output = run_shell_command(ls_command, use_sudo=use_sudo, ignore_errors=True)
    actual_perms = "NOT_FOUND"
    actual_owner = "NOT_FOUND"
    actual_group = "NOT_FOUND"
    status = "FAIL"

    if "CMD_ERROR" in output or "No such file or directory" in output:
        actual_perms = output
    else:
        parts = output.split()
        if len(parts) >= 4:
            actual_perms = parts[0]
            actual_owner = parts[2]
            actual_group = parts[3]

            perm_match = re.match(expected_perms_regex, actual_perms)
            owner_match = actual_owner == owner
            group_match = actual_group == group

            if perm_match and owner_match and group_match:
                status = "PASS"
            else:
                fail_reason = []
                if not perm_match: 
                    fail_reason.append(f"Permissions mismatch ('{actual_perms}' vs regex '{expected_perms_regex}')")
                if not owner_match: 
                    fail_reason.append(f"Owner mismatch ('{actual_owner}' vs '{owner}')")
                if not group_match: 
                    fail_reason.append(f"Group mismatch ('{actual_group}' vs '{group}')")
                write_output(f"  Failure reasons: {'; '.join(fail_reason)}")

    write_output(f"  Path:     {path}")
    write_output(f"  Expected: Permissions ~'{expected_perms_regex}', Owner '{owner}', Group '{group}'")
    write_output(f"  Actual:   Permissions '{actual_perms}', Owner '{actual_owner}', Group '{actual_group}'")
    write_output(f"  Status:   {status}")
    return status == "PASS"

def get_mysql_data_dir(cursor):
    """Gets MySQL data directory."""
    data_dir = execute_sql(cursor, "SHOW VARIABLES LIKE 'datadir';", fetch_one=False)
    if isinstance(data_dir, str) and data_dir.startswith("SQL_ERROR:"):
        return None
    elif data_dir and len(data_dir) > 0:
        return data_dir[0][1]  # Get the value from SHOW VARIABLES result
    return None

# --- Main Execution ---
if __name__ == "__main__":
    write_output(f"Starting MySQL 8.0 CIS Benchmark Check - {datetime.datetime.now()}")
    write_output(f"Outputting results to: {OUTPUT_FILE}")
    write_output("-" * 40)

    # Read Config
    config = configparser.ConfigParser()
    if not os.path.exists(CONFIG_FILE):
        write_output(f"Error: Configuration file '{CONFIG_FILE}' not found.")
        sys.exit(1)
    config.read(CONFIG_FILE)

    try:
        mysql_config = {
            'user': config['mysql']['user'],
            'password': config['mysql']['password'],
            'host': config['mysql']['host'],
            'port': int(config['mysql']['port']),
            'database': config['mysql']['database']
        }
    except KeyError as e:
        write_output(f"Error: Missing key {e} in configuration file '{CONFIG_FILE}'.")
        sys.exit(1)

    # Connect to MySQL
    conn = None
    cursor = None
    try:
        if MYSQL_LIB == 'mysql.connector':
            conn = mysql.connector.connect(**mysql_config)
            cursor = conn.cursor()
        else:  # PyMySQL
            conn = pymysql.connect(**mysql_config)
            cursor = conn.cursor()
        write_output("Successfully connected to MySQL.")
    except MySQLError as err:
        write_output(f"Error connecting to MySQL: {err}")
        # Continue with OS checks that don't require DB connection
    except Exception as e:
        write_output(f"Unexpected error connecting to MySQL: {e}")

    write_output("-" * 40)

    # --- Determine MySQL Data Directory ---
    data_dir = get_mysql_data_dir(cursor)
    if data_dir:
        write_output(f"Determined MySQL data directory: {data_dir}")
    else:
        write_output("Could not determine MySQL data directory. Some file checks may fail.")

    # --- Perform CIS Checks ---

    # == Section 1: Operating System Level Configuration ==
    write_output("\nSection 1: Operating System Level Configuration")

    # 1.1 Place Databases on a Non-System Partition (Manual)
    write_output("\n[1.1] Place Databases on a Non-System Partition (Manual)")
    if data_dir:
        mount_point = run_shell_command(f"df {data_dir} | tail -1 | awk '{{print $6}}'", ignore_errors=True)
        write_output(f"  Data Directory: {data_dir}")
        write_output(f"  Mount Point: {mount_point}")
        write_output("  Status: MANUAL (Verify data directory is on separate partition)")
    else:
        write_output("  Status: MANUAL (Could not determine data directory)")

    # 1.2 Ensure that the MYSQL_PWD Environment Variable Is Not in Use (Automated)
    write_output("\n[1.2] Ensure that the MYSQL_PWD Environment Variable Is Not in Use (Automated)")
    mysql_pwd_check = run_shell_command("sudo grep -al MYSQL_PWD /proc/*/environ", ignore_errors=True)
    status = "PASS"
    if mysql_pwd_check and "CMD_ERROR" not in mysql_pwd_check:
        # Filter out grep process itself
        lines = [line for line in mysql_pwd_check.splitlines() if '/grep' not in line]
        if lines:
            status = "FAIL"
            write_output(f"  Found MYSQL_PWD in processes: {', '.join(lines)}")
    
    write_output("  Expected: MYSQL_PWD environment variable should not be set")
    write_output(f"  Status: {status}")

    # == Section 2: Installation and Planning ==
    write_output("\nSection 2: Installation and Planning")

    # 2.1 Backup Policy in Place (Manual)
    write_output("\n[2.1] Backup Policy in Place (Manual)")
    write_output("  Status: MANUAL (Verify backup policy and procedures are documented)")

    # 2.2 Verify That MySQL is Not Installed and Operating on the Same Server as Web Server (Manual)
    write_output("\n[2.2] Verify That MySQL is Not Installed and Operating on the Same Server as Web Server (Manual)")
    web_servers = ["apache2", "httpd", "nginx"]
    web_server_found = False
    for web_server in web_servers:
        if run_shell_command(f"pgrep {web_server}", check_output=False, ignore_errors=True):
            web_server_found = True
            write_output(f"  Found web server process: {web_server}")
    
    if web_server_found:
        write_output("  Status: MANUAL (Web server detected - verify separation of concerns)")
    else:
        write_output("  Status: PASS (No web server processes detected)")

    # == Section 3: File Permissions ==
    write_output("\nSection 3: File Permissions")

    if cursor:
        # 3.1 Ensure That 'datadir' Has Appropriate Ownership and Permissions (Automated)
        write_output("\n[3.1] Ensure That 'datadir' Has Appropriate Ownership and Permissions (Automated)")
        if data_dir:
            datadir_passed = check_file_permissions(data_dir, r'drwx------', MYSQL_USER, MYSQL_GROUP, is_dir=True)
            write_output(f"  Overall Status: {'PASS' if datadir_passed else 'FAIL'}")
        else:
            write_output("  Status: FAIL (Could not determine data directory)")

        # 3.2 Ensure Log Files Have Appropriate Ownership and Permissions (Automated)
        write_output("\n[3.2] Ensure Log Files Have Appropriate Ownership and Permissions (Automated)")
        log_error = execute_sql(cursor, "SHOW VARIABLES LIKE 'log_error';")
        if log_error and len(log_error) > 0:
            log_file = log_error[0][1]
            if log_file and log_file != '':
                if not os.path.isabs(log_file) and data_dir:
                    log_file = os.path.join(data_dir, log_file)
                log_passed = check_file_permissions(log_file, r'-rw-------', MYSQL_USER, MYSQL_GROUP)
                write_output(f"  Log File Status: {'PASS' if log_passed else 'FAIL'}")
            else:
                write_output("  Status: FAIL (Log error file not configured)")
        else:
            write_output("  Status: FAIL (Could not determine log error file)")

    # == Section 4: General ==
    write_output("\nSection 4: General")

    if cursor:
        # 4.1 Ensure That the Most Recent Security Patches Are Applied (Manual)
        write_output("\n[4.1] Ensure That the Most Recent Security Patches Are Applied (Manual)")
        version_info = execute_sql(cursor, "SELECT VERSION();", fetch_one=True)
        write_output(f"  MySQL Version: {version_info}")
        write_output("  Status: MANUAL (Verify version is current and patched)")

        # 4.2 Ensure that the default password for the root account is changed (Automated)
        write_output("\n[4.2] Ensure that the default password for the root account is changed (Automated)")
        # Check if root account has a password set
        root_users = execute_sql(cursor, "SELECT User, Host, authentication_string FROM mysql.user WHERE User = 'root';")
        status = "FAIL"
        if root_users:
            has_password = False
            for user in root_users:
                if user[2] and user[2] != '':  # authentication_string is not empty
                    has_password = True
                    break
            status = "PASS" if has_password else "FAIL"
            write_output(f"  Found {len(root_users)} root accounts")
            write_output(f"  Status: {status}")
        else:
            write_output("  Status: FAIL (Could not check root accounts)")

        # 4.3 Ensure that the password for the root account is complex (Manual)
        write_output("\n[4.3] Ensure that the password for the root account is complex (Manual)")
        write_output("  Status: MANUAL (Verify root password complexity)")

        # 4.4 Ensure anonymous accounts are not in use (Automated)
        write_output("\n[4.4] Ensure anonymous accounts are not in use (Automated)")
        anon_users = execute_sql(cursor, "SELECT User, Host FROM mysql.user WHERE User = '';")
        status = "PASS" if not anon_users else "FAIL"
        if anon_users:
            write_output(f"  Found {len(anon_users)} anonymous accounts")
        write_output(f"  Status: {status}")

        # 4.5 Ensure no login accounts use wildcards for hostname (Automated)
        write_output("\n[4.5] Ensure no login accounts use wildcards for hostname (Automated)")
        wildcard_users = execute_sql(cursor, "SELECT User, Host FROM mysql.user WHERE Host = '%';")
        status = "PASS" if not wildcard_users else "FAIL"
        if wildcard_users:
            write_output(f"  Found {len(wildcard_users)} accounts with wildcard hostnames")
            for user in wildcard_users:
                write_output(f"    - {user[0]}@{user[1]}")
        write_output(f"  Status: {status}")

        # 4.6 Ensure no accounts exist without a password (Automated)
        write_output("\n[4.6] Ensure no accounts exist without a password (Automated)")
        empty_pwd_users = execute_sql(cursor, "SELECT User, Host FROM mysql.user WHERE authentication_string = '' OR authentication_string IS NULL;")
        status = "PASS" if not empty_pwd_users else "FAIL"
        if empty_pwd_users:
            write_output(f"  Found {len(empty_pwd_users)} accounts without passwords")
            for user in empty_pwd_users:
                write_output(f"    - {user[0]}@{user[1]}")
        write_output(f"  Status: {status}")

        # 4.7 Ensure 'sql_mode' Contains 'STRICT_TRANS_TABLES' (Automated)
        write_output("\n[4.7] Ensure 'sql_mode' Contains 'STRICT_TRANS_TABLES' (Automated)")
        check_mysql_variable(cursor, 'sql_mode', 'STRICT_TRANS_TABLES', 'in')

        # 4.8 Ensure 'local_infile' is Disabled (Automated)
        write_output("\n[4.8] Ensure 'local_infile' is Disabled (Automated)")
        check_mysql_variable(cursor, 'local_infile', False)

        # 4.9 Ensure 'allow-suspicious-udfs' is Disabled (Automated)
        write_output("\n[4.9] Ensure 'allow-suspicious-udfs' is Disabled (Automated)")
        check_mysql_variable(cursor, 'allow_suspicious_udfs', False)

        # 4.10 Ensure 'secure_file_priv' is not empty (Automated)
        write_output("\n[4.10] Ensure 'secure_file_priv' is not empty (Automated)")
        check_mysql_variable(cursor, 'secure_file_priv', '', '!=')

        # 4.11 Ensure SSL/TLS is configured and enabled (Automated)
        write_output("\n[4.11] Ensure SSL/TLS is configured and enabled (Automated)")
        ssl_check = check_mysql_variable(cursor, 'have_ssl', 'YES')
        if ssl_check:
            # Additional SSL configuration checks
            check_mysql_variable(cursor, 'ssl_cert', '', '!=')
            check_mysql_variable(cursor, 'ssl_key', '', '!=')
        write_output(f"  Overall SSL Status: {'PASS' if ssl_check else 'FAIL'}")

        # 4.12 Ensure 'require_secure_transport' is enabled (Automated)
        write_output("\n[4.12] Ensure 'require_secure_transport' is enabled (Automated)")
        check_mysql_variable(cursor, 'require_secure_transport', True)

        # 4.13 Ensure 'super_read_only' is set to 'ON' for read-only replicas (Manual)
        write_output("\n[4.13] Ensure 'super_read_only' is set to 'ON' for read-only replicas (Manual)")
        read_only = execute_sql(cursor, "SHOW VARIABLES LIKE 'read_only';")
        super_read_only = execute_sql(cursor, "SHOW VARIABLES LIKE 'super_read_only';")
        if read_only and len(read_only) > 0:
            write_output(f"  read_only: {read_only[0][1]}")
        if super_read_only and len(super_read_only) > 0:
            write_output(f"  super_read_only: {super_read_only[0][1]}")
        write_output("  Status: MANUAL (Verify setting appropriate for server role)")

        # 4.14 Ensure binary logging is enabled (Automated)
        write_output("\n[4.14] Ensure binary logging is enabled (Automated)")
        check_mysql_variable(cursor, 'log_bin', True)

        # 4.15 Ensure logging is enabled for all instances (Automated)
        write_output("\n[4.15] Ensure logging is enabled for all instances (Automated)")
        general_log = check_mysql_variable(cursor, 'general_log', True)
        write_output(f"  General Log Status: {'PASS' if general_log else 'FAIL'}")

    else:
        write_output("  Skipping DB-dependent checks in Section 4 due to connection failure.")

    # --- Cleanup ---
    write_output("-" * 40)
    write_output(f"Check completed - {datetime.datetime.now()}")
    if cursor:
        cursor.close()
    if conn:
        conn.close()
        write_output("MySQL connection closed.")