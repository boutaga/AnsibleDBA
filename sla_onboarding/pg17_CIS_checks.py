import subprocess
import os
import configparser
import datetime
import sys
import re

try:
    # Using psycopg instead of psycopg2 if available (newer library)
    # Specify binary version to avoid build dependencies if possible
    try:
        import psycopg
        from psycopg.errors import OperationalError, InsufficientPrivilege, UndefinedTable, UndefinedColumn, UndefinedObject, UndefinedParameter
        PG_ERRORS = (OperationalError, InsufficientPrivilege, UndefinedTable, UndefinedColumn, UndefinedObject, UndefinedParameter)
        PSYCOPG_VERSION = 3
    except ImportError:
        import psycopg2
        from psycopg2 import OperationalError, errors
        # Map common psycopg2 errors
        InsufficientPrivilege = errors.InsufficientPrivilege
        UndefinedTable = errors.UndefinedTable
        UndefinedColumn = errors.UndefinedColumn
        UndefinedObject = errors.UndefinedObject
        UndefinedParameter = errors.lookup('42P02') # Undefined parameter may not have a specific class
        PG_ERRORS = (OperationalError, InsufficientPrivilege, UndefinedTable, UndefinedColumn, UndefinedObject, UndefinedParameter)
        PSYCOPG_VERSION = 2

except ImportError:
    print("Error: The 'psycopg' (recommended) or 'psycopg2' library is required.")
    print("Please install it using: pip install \"psycopg[binary]\" OR pip install psycopg2")
    sys.exit(1)

# --- Configuration ---
CONFIG_FILE = 'pg17_CIS_config.ini'
TIMESTAMP = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
OUTPUT_FILE = f'postgresql_cis_check_{TIMESTAMP}.txt'
# Paths might need adjustment based on installation
PG_VERSION = "17" # Used for service name, paths etc. - ADJUST IF NEEDED
PG_CONFIG_CMD = f"/usr/pgsql-{PG_VERSION}/bin/pg_config" # Command to find paths
PG_SERVICE_NAME = f"postgresql-{PG_VERSION}.service" # Common systemd service name
POSTGRES_USER = "postgres" # Default OS user for postgres
POSTGRES_GROUP = "postgres" # Default OS group for postgres

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
        # Use check=True only if we expect failure to be exceptional
        run_check = (not ignore_errors)

        result = subprocess.run(command, shell=True, check=run_check, capture_output=True, text=True, errors='ignore')

        if check_output:
            # Combine stdout and stderr for more context on failure if check=False
            if result.returncode != 0 and ignore_errors:
                 return f"CMD_ERROR: Exit Code {result.returncode} - {result.stderr.strip() or result.stdout.strip()}"
            return result.stdout.strip()

        else:
            return result.returncode == 0 # Return True if command succeeds (exit code 0)

    except subprocess.CalledProcessError as e:
        write_output(f"  Error running command '{original_command}': {e.stderr or e.stdout}")
        if check_output:
            return f"CMD_ERROR: {e.stderr or e.stdout}"
        else:
            return False
    except FileNotFoundError as e:
         write_output(f"  Error: Command prefix not found for '{original_command}': {e}. Is the program installed and in PATH?")
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

def get_pg_config_value(config_key):
    """Gets a value using pg_config command."""
    output = run_shell_command(f"{PG_CONFIG_CMD} --{config_key}")
    if "CMD_ERROR" in output:
        write_output(f"  Warning: Could not run pg_config for --{config_key}. Path '{PG_CONFIG_CMD}' correct?")
        return None
    return output

def get_pg_data_dir(cursor):
    """Attempts to get PGDATA from DB setting or pg_config."""
    pgdata = None
    if cursor:
        pgdata = execute_sql(cursor, "SHOW data_directory;", fetch_one=True)
        if isinstance(pgdata, str) and pgdata.startswith("SQL_ERROR:"):
             pgdata = None # Fallback if DB query fails

    if not pgdata:
        pgdata = get_pg_config_value("pgdata") # Fallback to pg_config

    if not pgdata:
         write_output("  CRITICAL: Could not determine PostgreSQL data directory (PGDATA). File permission checks will fail.")
    return pgdata

def get_postgres_conf_path(pgdata):
     """Determines the path to postgresql.conf"""
     if pgdata:
         return os.path.join(pgdata, "postgresql.conf")
     else:
         # Fallback guess - adjust if needed
         return f"/var/lib/pgsql/{PG_VERSION}/data/postgresql.conf"


def execute_sql(cursor, sql_query, params=None, fetch_one=False):
    """Executes an SQL query and returns the result."""
    if not cursor:
        return "SQL_ERROR: No database connection"
    try:
        cursor.execute(sql_query, params)
        if fetch_one:
            result = cursor.fetchone()
            # psycopg returns a tuple even for single column, psycopg2 might return single value directly
            return result[0] if result else None
        else:
            return cursor.fetchall()
    except PG_ERRORS as err:
        # Check for specific errors like undefined parameter/table
        if isinstance(err, (UndefinedParameter, UndefinedObject, UndefinedTable, UndefinedColumn)):
             write_output(f"  Info: SQL query failed possibly due to missing feature/object '{sql_query}': {err}")
             return f"SQL_INFO: Feature/Object missing - {err}"
        else:
             write_output(f"  Error executing SQL '{sql_query}' (Params: {params}): {err}")
             # Propagate the error message for checks to interpret
             return f"SQL_ERROR: {err}"
    except Exception as e:
        write_output(f"  Unexpected error executing SQL '{sql_query}' (Params: {params}): {e}")
        return f"SQL_ERROR: Unexpected {e}"


def check_pg_variable(cursor, variable_name, expected_value, comparison='=='):
    """Checks a PostgreSQL GUC variable against an expected value."""
    sql = f"SHOW {variable_name};"
    # Use fetch_one=True for SHOW command
    actual_value = execute_sql(cursor, sql, fetch_one=True)
    status = "FAIL"
    expected_display = f"{expected_value}"

    if isinstance(actual_value, str) and actual_value.startswith("SQL_ERROR:"):
        pass # Error already written by execute_sql
    elif isinstance(actual_value, str) and actual_value.startswith("SQL_INFO:"):
        # Treat missing variable/feature as NA or FAIL depending on context
        # For now, let's treat as FAIL unless check logic overrides
        status = "NA"
        write_output(f"  Info: Variable '{variable_name}' might not exist or feature disabled.")
    elif actual_value is None:
        actual_value = "Not Set/NULL"
        # Decide if NULL is acceptable based on comparison
        if comparison == 'is_not_null' and expected_value is None:
            status = "FAIL" # Expected not null, got null
        elif comparison == '==' and expected_value is None:
             status = "PASS" # Expected NULL, got NULL
    else:
        # Convert actual_value type for comparison if possible
        converted_actual = actual_value
        try:
            if isinstance(expected_value, bool):
                # PostgreSQL returns 'on'/'off' for bools
                converted_actual = actual_value.lower() == 'on'
            elif isinstance(expected_value, int):
                converted_actual = int(actual_value)
            elif isinstance(expected_value, float):
                converted_actual = float(actual_value)
            # Add other conversions if needed (e.g., memory units)

        except (ValueError, TypeError):
            pass # Use string comparison if conversion fails

        try:
            passed = False
            if comparison == '==':
                passed = converted_actual == expected_value
            elif comparison == '!=':
                 passed = converted_actual != expected_value
            elif comparison == '>=':
                 passed = converted_actual >= expected_value
            elif comparison == '<=':
                 # Special case for log_min_messages/log_min_error_statement levels
                 levels = ['debug5','debug4','debug3','debug2','debug1','info','notice','warning','error','log','fatal','panic']
                 if variable_name in ['log_min_messages', 'log_min_error_statement'] and isinstance(expected_value, str) and actual_value in levels:
                     expected_display = f"at least '{expected_value}'"
                     passed = levels.index(actual_value) >= levels.index(expected_value)
                 elif variable_name == 'log_rotation_age' and isinstance(expected_value, int) and actual_value.endswith('d'):
                      # Convert days to minutes for comparison if expected is int (minutes)
                      days = int(actual_value[:-1])
                      passed = (days * 1440) <= expected_value # Benchmark implies 1d is default/ok
                 elif isinstance(expected_value, int): # Generic <= for numbers
                       passed = converted_actual <= expected_value
                 else: # Fallback for non-numeric/level types
                      passed = str(converted_actual) <= str(expected_value)

            elif comparison == '>':
                  passed = converted_actual > expected_value
            elif comparison == '<':
                  passed = converted_actual < expected_value
            elif comparison == 'in':
                 passed = str(expected_value) in str(actual_value) # String contains check
            elif comparison == 'notin':
                 passed = str(expected_value) not in str(actual_value) # String does not contain
            elif comparison == 'is_set': # Check if not NULL or empty
                 passed = actual_value is not None and actual_value != ''
            elif comparison == 'matches_pattern':
                  expected_display = f"matches pattern '{expected_value}'"
                  passed = re.search(expected_value, str(actual_value)) is not None


            if passed:
                 status = "PASS"

        except Exception as e:
             write_output(f"  Warning: Comparison error for {variable_name} ('{actual_value}' vs '{expected_value}'): {e}")


    write_output(f"  Checking: {variable_name}")
    write_output(f"  Expected: {comparison} {expected_display}")
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
    # Use sudo by default as some files/dirs might require root access
    output = run_shell_command(ls_command, use_sudo=use_sudo, ignore_errors=True) # Ignore errors to parse output
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

            # Simple regex check
            perm_match = re.match(expected_perms_regex, actual_perms)
            owner_match = actual_owner == owner
            group_match = actual_group == group

            if perm_match and owner_match and group_match:
                 status = "PASS"
            else:
                 # Provide more detail on failure
                 fail_reason = []
                 if not perm_match: fail_reason.append(f"Permissions mismatch ('{actual_perms}' vs regex '{expected_perms_regex}')")
                 if not owner_match: fail_reason.append(f"Owner mismatch ('{actual_owner}' vs '{owner}')")
                 if not group_match: fail_reason.append(f"Group mismatch ('{actual_group}' vs '{group}')")
                 write_output(f"  Failure reasons: {'; '.join(fail_reason)}")

    write_output(f"  Path:     {path}")
    write_output(f"  Expected: Permissions ~'{expected_perms_regex}', Owner '{owner}', Group '{group}'")
    write_output(f"  Actual:   Permissions '{actual_perms}', Owner '{actual_owner}', Group '{actual_group}'")
    write_output(f"  Status:   {status}")
    return status == "PASS"

def check_config_file_value(config_path, setting_name, expected_value, comparison='=='):
    """Checks a specific setting in postgresql.conf."""
    # Note: requires read access to the file, potentially sudo
    command = f"sudo grep -E '^{setting_name}\s*=' {config_path}"
    output = run_shell_command(command, ignore_errors=True) # Ignore non-zero exit if grep finds nothing
    actual_value = "Not Set / Error Reading"
    status = "FAIL"

    if "CMD_ERROR" in output:
         actual_value = output # Report the error
    elif not output:
         actual_value = "Not Found in Config" # Setting might be using default
         # TODO: Need logic to check default value if not set in file? Complicated.
         # For now, assume if check requires a specific value, it must be set explicitly.
    else:
         # Found the setting, parse the value
         try:
             # Split first line found, handle potential comments
             line = output.splitlines()[0]
             line = line.split('#')[0].strip() # Remove comments
             parts = line.split('=', 1)
             actual_value_str = parts[1].strip().strip("'\"") # Get value, strip quotes

             # Convert type if possible
             converted_actual = actual_value_str
             if isinstance(expected_value, bool):
                 converted_actual = actual_value_str.lower() in ['on', 'true', '1', 'yes']
             elif isinstance(expected_value, int):
                 converted_actual = int(actual_value_str)
             # Add other conversions as needed

             # Perform comparison
             passed = False
             if comparison == '==':
                 passed = converted_actual == expected_value
             elif comparison == '!=':
                 passed = converted_actual != expected_value
             # Add other comparisons if needed

             if passed:
                  status = "PASS"
             actual_value = actual_value_str # Report the raw string value found

         except Exception as e:
             actual_value = f"Error parsing value from line '{output.splitlines()[0]}': {e}"

    write_output(f"  Checking Config: {config_path}")
    write_output(f"  Setting:  {setting_name}")
    write_output(f"  Expected: {comparison} {expected_value}")
    write_output(f"  Actual:   {actual_value}")
    write_output(f"  Status:   {status}")
    return status == "PASS"


# --- Main Execution ---
if __name__ == "__main__":
    write_output(f"Starting PostgreSQL CIS Benchmark Check - {datetime.datetime.now()}")
    write_output(f"Outputting results to: {OUTPUT_FILE}")
    write_output("-" * 40)

    # Read Config
    config = configparser.ConfigParser()
    if not os.path.exists(CONFIG_FILE):
        write_output(f"Error: Configuration file '{CONFIG_FILE}' not found.")
        sys.exit(1)
    config.read(CONFIG_FILE)

    try:
        pg_config = {
            'user': config['postgresql']['user'],
            'password': config['postgresql']['password'],
            'host': config['postgresql']['host'],
            'port': config['postgresql']['port'],
            'dbname': config['postgresql']['dbname']
        }
        # Add connect_timeout for robustness
        pg_config['connect_timeout'] = 10 # seconds
    except KeyError as e:
        write_output(f"Error: Missing key {e} in configuration file '{CONFIG_FILE}'.")
        sys.exit(1)

    # Connect to PostgreSQL
    conn = None
    cursor = None
    try:
        if PSYCOPG_VERSION == 3:
             conn = psycopg.connect(**pg_config)
             cursor = conn.cursor()
        else: # psycopg2
             conn = psycopg2.connect(**pg_config)
             cursor = conn.cursor()
        write_output("Successfully connected to PostgreSQL.")
    except OperationalError as err:
        write_output(f"Error connecting to PostgreSQL: {err}")
        # Still proceed with OS checks that don't require DB connection
    except Exception as e:
        write_output(f"Unexpected error connecting to PostgreSQL: {e}")

    write_output("-" * 40)

    # --- Determine PGDATA ---
    pgdata_dir = get_pg_data_dir(cursor)
    if pgdata_dir:
         write_output(f"Determined PGDATA: {pgdata_dir}")
    else:
         write_output("Could not determine PGDATA. Some file/config checks may fail.")

    postgres_conf_path = get_postgres_conf_path(pgdata_dir)


    # --- Perform Checks ---

    # == Section 1: Installation and Patches ==
    write_output("\nSection 1: Installation and Patches")

    # 1.3 Ensure systemd Service Files Are Enabled (Automated)
    write_output(f"\n[1.3] Ensure systemd Service File ({PG_SERVICE_NAME}) Is Enabled (Automated)")
    output = run_shell_command(f"systemctl is-enabled {PG_SERVICE_NAME}", ignore_errors=True)
    status = "FAIL"
    actual_status = output
    if "enabled" in output.lower() and "CMD_ERROR" not in output:
        status = "PASS"
    elif "disabled" in output.lower() and "CMD_ERROR" not in output:
        actual_status = "Disabled"
    elif "CMD_ERROR" in output:
         actual_status = f"Error checking service: {output}"
    elif not output: # Command succeeded but no output likely means service file not found
        actual_status = "Service file not found or command failed silently"


    write_output(f"  Expected: Service '{PG_SERVICE_NAME}' should be enabled.")
    write_output(f"  Actual:   Status is '{actual_status}'")
    write_output(f"  Status:   {status}")


    # 1.4 Ensure Data Cluster Initialized Successfully (Automated)
    write_output("\n[1.4] Ensure Data Cluster Initialized Successfully (Automated)")
    cluster_init_passed = False
    if pgdata_dir:
        # Check permissions on PGDATA itself (owned by postgres, permissions drwx------ typically)
        write_output("  Checking PGDATA permissions...")
        perms_passed = check_file_permissions(pgdata_dir, r'drwx------', POSTGRES_USER, POSTGRES_GROUP, is_dir=True, use_sudo=True)
        write_output("-" * 10)

        # Run the check script (path might vary)
        check_script = f"/usr/pgsql-{PG_VERSION}/bin/postgresql-{PG_VERSION}-check-db-dir"
        write_output(f"  Running {check_script}...")
        # Needs to be run as root according to benchmark example
        script_passed = run_shell_command(f"{check_script} {pgdata_dir}", check_output=False, use_sudo=True)

        write_output(f"  PGDATA Permissions Check Status: {'PASS' if perms_passed else 'FAIL'}")
        write_output(f"  Check Script ({check_script}) Status: {'PASS' if script_passed else 'FAIL'}")
        cluster_init_passed = perms_passed and script_passed
    else:
         write_output("  Skipping check as PGDATA directory could not be determined.")

    write_output(f"  Expected: PGDATA directory should have restrictive permissions (0700 {POSTGRES_USER}:{POSTGRES_GROUP}) and check script should pass.")
    write_output(f"  Status:   {'PASS' if cluster_init_passed else 'FAIL'}")

    # 1.6 Verify That 'PGPASSWORD' is Not Set in Users' Profiles (Automated)
    write_output("\n[1.6] Verify That 'PGPASSWORD' is Not Set in Users' Profiles (Automated)")
    # Needs sudo to read potentially restricted home directories/files
    # Note: Benchmark grep only checks common bash files. Zsh, Csh etc. not checked.
    # Added /etc/environment check based on benchmark example
    command = "sudo grep -Hs PGPASSWORD /home/*/.bashrc /home/*/.profile /home/*/.bash_profile /root/.bashrc /root/.profile /root/.bash_profile /etc/environment"
    try:
        result = subprocess.run(command, shell=True, check=False, capture_output=True, text=True, errors='ignore')
        output = result.stdout.strip()
        status = "PASS"
        actual_output = "PGPASSWORD not found in common profile files or /etc/environment."
        if result.stderr and "No such file or directory" not in result.stderr and "No such device or address" not in result.stderr :
             # Report errors other than 'file not found' or issues reading /proc/*/environ through sudo/grep combo
             status = "FAIL"
             actual_output = f"Error running grep: {result.stderr.strip()}"
        elif output:
             status = "FAIL"
             actual_output = f"PGPASSWORD found in profile file(s):\n  " + "\n  ".join(output.splitlines())

    except Exception as e:
         status = "FAIL"
         actual_output = f"Failed to execute grep command: {e}"

    write_output("  Expected: PGPASSWORD should not be set in user profile scripts or /etc/environment.")
    write_output(f"  Actual:   {actual_output}")
    write_output(f"  Status:   {status}")


    # 1.7 Verify That the 'PGPASSWORD' Environment Variable is Not in Use (Automated)
    write_output("\n[1.7] Verify That the 'PGPASSWORD' Environment Variable is Not in Use (Automated)")
    # Needs sudo to read environ files of processes owned by other users
    # Use -l to list files containing the match, -a to treat binary as text
    output = run_shell_command("sudo grep -al PGPASSWORD /proc/*/environ", check_output=True, ignore_errors=True)
    status = "PASS"
    actual_output = "PGPASSWORD not found in active process environments."
    if "CMD_ERROR" in output:
        # Ignore 'Permission denied' as it's expected for some processes even with sudo
        if "Permission denied" not in output and "Operation not permitted" not in output:
            status = "FAIL"
            actual_output = f"Error checking /proc: {output}. Permissions?"
        else:
            actual_output = "PGPASSWORD not found (ignoring permission errors)."
    elif output:
        # Filter out the grep process itself if it shows up
        # Check if any files listed contain PGPASSWORD - grep -l already did this
        lines = [line for line in output.splitlines() if 'self/environ' not in line and '/grep' not in line]
        if lines:
            status = "FAIL"
            actual_output = f"PGPASSWORD found set for process(es):\n  " + "\n  ".join(lines)

    write_output("  Expected: PGPASSWORD environment variable should not be set for running processes.")
    write_output(f"  Actual:   {actual_output}")
    write_output(f"  Status:   {status}")

    # == Section 2: Directory and File Permissions ==
    write_output("\nSection 2: Directory and File Permissions")

    # 2.2 Ensure extension directory has appropriate ownership and permissions (Automated)
    write_output("\n[2.2] Ensure extension directory has appropriate ownership and permissions (Automated)")
    sharedir = get_pg_config_value("sharedir")
    extdir_passed = False
    if sharedir:
        extdir = os.path.join(sharedir, "extension")
        # Benchmark expects drwxr-xr-x root root (0755) [cite: 213]
        extdir_passed = check_file_permissions(extdir, r'drwxr-xr-x', 'root', 'root', is_dir=True, use_sudo=False) # pg_config runs as current user
    else:
         write_output("  Skipping check as sharedir could not be determined via pg_config.")

    write_output(f"  Overall Status: {'PASS' if extdir_passed else 'FAIL'}")


    # 2.3 Disable PostgreSQL Command History (Automated)
    write_output("\n[2.3] Disable PostgreSQL Command History (Automated)")
    history_files_found = []
    # Using sudo because find might need to traverse dirs owned by root or others
    # Benchmark check seems to expect history file NOT to be symlink to /dev/null,
    # but the remediation makes it a symlink. Let's follow remediation goal.
    cmd_home = "sudo find /home -maxdepth 2 -name '.psql_history' -type l -ls"
    cmd_root = "sudo find /root -maxdepth 1 -name '.psql_history' -type l -ls"
    output_home = run_shell_command(cmd_home, ignore_errors=True)
    output_root = run_shell_command(cmd_root, ignore_errors=True)
    linked_to_null = True
    checked = False

    for out in [output_home, output_root]:
        if "CMD_ERROR" not in out and out:
             checked = True
             if '/dev/null' not in out:
                 linked_to_null = False
                 history_files_found.append(f"Symlink found but not pointing to /dev/null: {out}")
        elif "CMD_ERROR" in out and "No such file or directory" not in out:
             checked = True
             linked_to_null = False # Mark as fail on error
             history_files_found.append(f"Error checking symlinks: {out}")

    # Also check for non-symlink files
    cmd_home_file = "sudo find /home -maxdepth 2 -name '.psql_history' -type f"
    cmd_root_file = "sudo find /root -maxdepth 1 -name '.psql_history' -type f"
    output_home_file = run_shell_command(cmd_home_file, ignore_errors=True)
    output_root_file = run_shell_command(cmd_root_file, ignore_errors=True)
    regular_files_exist = False
    for out in [output_home_file, output_root_file]:
         if "CMD_ERROR" not in out and out:
             checked = True
             regular_files_exist = True
             history_files_found.append(f"Regular history file found: {out}")
         elif "CMD_ERROR" in out and "No such file or directory" not in out:
             checked = True
             regular_files_exist = True # Mark as fail on error
             history_files_found.append(f"Error checking regular files: {out}")


    status = "FAIL" if (not checked or not linked_to_null or regular_files_exist) else "PASS"

    write_output("  Expected: No '.psql_history' files exist OR they are symbolic links to /dev/null.")
    if history_files_found:
         write_output(f"  Actual:   Found issues:\n  " + "\n  ".join(history_files_found))
    elif not checked:
         write_output(f"  Actual:   Could not verify (check command errors above).")
    else:
         write_output(f"  Actual:   No problematic history files found or they are linked to /dev/null.")
    write_output(f"  Status:   {status}")

    # == Section 3: Logging And Auditing ==
    write_output("\nSection 3: Logging And Auditing")

    if cursor:
        # 3.1.2 Ensure the log destinations are set correctly (Automated)
        write_output("\n[3.1.2] Ensure the log destinations are set correctly (Automated)")
        # Benchmark doesn't mandate specific destination, just that it's set per policy.
        # We check that it's not empty. Manual review still needed.
        check_pg_variable(cursor, 'log_destination', '', '!=') # Check it's not empty


        # 3.1.3 Ensure the logging collector is enabled (Automated)
        write_output("\n[3.1.3] Ensure the logging collector is enabled (Automated)")
        # Required if log_destination includes stderr or csvlog
        log_dest = execute_sql(cursor, "SHOW log_destination;", fetch_one=True)
        collector_needed = False
        if isinstance(log_dest, str) and not log_dest.startswith("SQL_"):
             if 'stderr' in log_dest or 'csvlog' in log_dest:
                  collector_needed = True
        elif isinstance(log_dest, str) and log_dest.startswith("SQL_"):
              write_output(f"  Could not determine log_destination: {log_dest}")

        if collector_needed:
             check_pg_variable(cursor, 'logging_collector', True) # Checks for 'on'
        else:
             write_output("  Logging collector check not strictly required based on log_destination (no stderr/csvlog).")
             # Optionally still check if it's 'on' as it doesn't hurt
             check_pg_variable(cursor, 'logging_collector', True)
             write_output("  Status: NA (Strictly), but checked value anyway.")


        # 3.1.4 Ensure the log file destination directory is set correctly (Automated)
        write_output("\n[3.1.4] Ensure the log file destination directory is set correctly (Automated)")
        # Check it's set if collector is on. Value depends on policy. Check if set.
        collector_on = execute_sql(cursor, "SHOW logging_collector;", fetch_one=True) == 'on'
        if collector_on:
            check_pg_variable(cursor, 'log_directory', None, 'is_set') # Check it has a value
            # Further check: ensure dir exists and has correct permissions (see 3.1.6)
        else:
            write_output("  Skipping check as logging_collector is off.")
            write_output("  Status: NA")

        # 3.1.5 Ensure the filename pattern for log files is set correctly (Automated)
        write_output("\n[3.1.5] Ensure the filename pattern for log files is set correctly (Automated)")
        if collector_on:
             # Check it's set. Value depends on policy. Check if set.
             check_pg_variable(cursor, 'log_filename', None, 'is_set')
        else:
             write_output("  Skipping check as logging_collector is off.")
             write_output("  Status: NA")


        # 3.1.6 Ensure the log file permissions are set correctly (Automated)
        write_output("\n[3.1.6] Ensure the log file permissions are set correctly (Automated)")
        if collector_on:
            # Benchmark recommends 0600 [cite: 310]
            check_pg_variable(cursor, 'log_file_mode', '0600')
        else:
             write_output("  Skipping check as logging_collector is off.")
             write_output("  Status: NA")


        # 3.1.7 Ensure 'log_truncate_on_rotation' is enabled (Automated)
        write_output("\n[3.1.7] Ensure 'log_truncate_on_rotation' is enabled (Automated)")
        if collector_on:
            # Default is 'on', benchmark implies 'on' is usually correct unless specific rotation needs exist [cite: 321, 324]
            check_pg_variable(cursor, 'log_truncate_on_rotation', True)
        else:
            write_output("  Skipping check as logging_collector is off.")
            write_output("  Status: NA")

        # 3.1.8 Ensure the maximum log file lifetime is set correctly (Automated)
        write_output("\n[3.1.8] Ensure the maximum log file lifetime (log_rotation_age) is set correctly (Automated)")
        if collector_on:
            # Default 1d. Check if it's <= 1d (1440 mins) or 0 (disabled, relies on size)
            # Benchmark implies daily rotation is best practice [cite: 334]
            # We check if it's <= 1440 minutes. Note: Value is string like '1d'.
            check_pg_variable(cursor, 'log_rotation_age', 1440, '<=')
        else:
            write_output("  Skipping check as logging_collector is off.")
            write_output("  Status: NA")


        # 3.1.9 Ensure the maximum log file size is set correctly (Automated)
        write_output("\n[3.1.9] Ensure the maximum log file size (log_rotation_size) is set correctly (Automated)")
        if collector_on:
             # Default 0 (disabled). Check if > 0 (enabled) unless age rotation handles it.
             # Check if value is non-zero OR if log_rotation_age is > 0
             age_rot_set = execute_sql(cursor, "SHOW log_rotation_age;", fetch_one=True) != '0'
             size_rot_set = execute_sql(cursor, "SHOW log_rotation_size;", fetch_one=True) != '0'
             status = "PASS" if age_rot_set or size_rot_set else "FAIL"
             write_output(f"  Actual: age_rotation={age_rot_set}, size_rotation={size_rot_set}")
             write_output("  Expected: Either log_rotation_age > 0 OR log_rotation_size > 0 (or both)")
             write_output(f"  Status: {status}")

        else:
             write_output("  Skipping check as logging_collector is off.")
             write_output("  Status: NA")

        # 3.1.11 Ensure syslog messages are not suppressed (Automated)
        write_output("\n[3.1.11] Ensure syslog messages are not suppressed (Automated)")
        log_dest = execute_sql(cursor, "SHOW log_destination;", fetch_one=True)
        syslog_active = isinstance(log_dest, str) and 'syslog' in log_dest
        if syslog_active:
             check_pg_variable(cursor, 'syslog_sequence_numbers', True)
        else:
             write_output("  Skipping check as syslog is not in log_destination.")
             write_output("  Status: NA")


        # 3.1.12 Ensure syslog messages are not lost due to size (Automated)
        write_output("\n[3.1.12] Ensure syslog messages are not lost due to size (Automated)")
        if syslog_active:
            # Default is 'on', benchmark implies 'on' is best unless syslog server handles large messages [cite: 376]
            check_pg_variable(cursor, 'syslog_split_messages', True)
        else:
            write_output("  Skipping check as syslog is not in log_destination.")
            write_output("  Status: NA")

        # 3.1.13 Ensure the program name for PostgreSQL syslog messages are correct (Automated)
        write_output("\n[3.1.13] Ensure the program name for PostgreSQL syslog messages (syslog_ident) is correct (Automated)")
        if syslog_active:
             # Default is 'postgres'. Check if set to non-empty value.
             check_pg_variable(cursor, 'syslog_ident', None, 'is_set')
        else:
             write_output("  Skipping check as syslog is not in log_destination.")
             write_output("  Status: NA")

        # 3.1.14 Ensure the correct messages are written to the server log (Automated)
        write_output("\n[3.1.14] Ensure log_min_messages is 'warning' or lower (Automated)")
        # Check level is warning, notice, info, debug1-5
        check_pg_variable(cursor, 'log_min_messages', 'warning', '<=')


        # 3.1.15 Ensure the correct SQL statements generating errors are recorded (Automated)
        write_output("\n[3.1.15] Ensure log_min_error_statement is 'error' or lower (Automated)")
        check_pg_variable(cursor, 'log_min_error_statement', 'error', '<=')

        # 3.1.16 Ensure 'debug_print_parse' is disabled (Automated)
        write_output("\n[3.1.16] Ensure 'debug_print_parse' is disabled (Automated)")
        check_pg_variable(cursor, 'debug_print_parse', False)

        # 3.1.17 Ensure 'debug_print_rewritten' is disabled (Automated)
        write_output("\n[3.1.17] Ensure 'debug_print_rewritten' is disabled (Automated)")
        check_pg_variable(cursor, 'debug_print_rewritten', False)

        # 3.1.18 Ensure 'debug_print_plan' is disabled (Automated)
        write_output("\n[3.1.18] Ensure 'debug_print_plan' is disabled (Automated)")
        check_pg_variable(cursor, 'debug_print_plan', False)

        # 3.1.19 Ensure 'debug_pretty_print' is enabled (Automated)
        write_output("\n[3.1.19] Ensure 'debug_pretty_print' is enabled (Automated)")
        # Only relevant if debug_* options above are on, but check anyway.
        check_pg_variable(cursor, 'debug_pretty_print', True)

        # 3.1.20 Ensure 'log_connections' is enabled (Automated)
        write_output("\n[3.1.20] Ensure 'log_connections' is enabled (Automated)")
        check_pg_variable(cursor, 'log_connections', True)

        # 3.1.21 Ensure 'log_disconnections' is enabled (Automated)
        write_output("\n[3.1.21] Ensure 'log_disconnections' is enabled (Automated)")
        check_pg_variable(cursor, 'log_disconnections', True)

        # 3.1.22 Ensure 'log_error_verbosity' is set correctly (Automated)
        write_output("\n[3.1.22] Ensure 'log_error_verbosity' is 'default' or 'verbose' (Automated)")
        verb = execute_sql(cursor, "SHOW log_error_verbosity;", fetch_one=True)
        status = "FAIL"
        if isinstance(verb, str) and verb.startswith("SQL_"):
             actual_verb = verb
        elif verb in ['default', 'verbose']:
             status = "PASS"
             actual_verb = verb
        elif verb:
             actual_verb = verb
        else:
             actual_verb = "Not Set"

        write_output("  Expected: 'default' or 'verbose'")
        write_output(f"  Actual:   {actual_verb}")
        write_output(f"  Status:   {status}")


        # 3.1.23 Ensure 'log_hostname' is set correctly (Automated)
        write_output("\n[3.1.23] Ensure 'log_hostname' is disabled (off) (Automated)")
        check_pg_variable(cursor, 'log_hostname', False)

        # 3.1.24 Ensure 'log_line_prefix' is set correctly (Automated)
        write_output("\n[3.1.24] Ensure 'log_line_prefix' is set correctly (Automated)")
        # Benchmark recommends specific complex format for pgBadger compatibility [cite: 514, 524]
        # Simplified check: ensure it's not the default '%m [%p]'
        check_pg_variable(cursor, 'log_line_prefix', '%m [%p]', '!=')
        # Manual check recommended for full compliance with pgbadger format

        # 3.1.25 Ensure 'log_statement' is set correctly (Automated)
        write_output("\n[3.1.25] Ensure 'log_statement' is 'ddl', 'mod', or 'all' (Automated)")
        log_stmt = execute_sql(cursor, "SHOW log_statement;", fetch_one=True)
        status = "FAIL"
        if isinstance(log_stmt, str) and log_stmt.startswith("SQL_"):
            actual_stmt = log_stmt
        elif log_stmt in ['ddl', 'mod', 'all']:
            status = "PASS"
            actual_stmt = log_stmt
        elif log_stmt:
            actual_stmt = log_stmt
        else:
            actual_stmt = "Not Set"

        write_output("  Expected: 'ddl', 'mod', or 'all' (not 'none')")
        write_output(f"  Actual:   {actual_stmt}")
        write_output(f"  Status:   {status}")

        # 3.1.26 Ensure 'log_timezone' is set correctly (Automated)
        write_output("\n[3.1.26] Ensure 'log_timezone' is 'UTC' or 'GMT' (Automated)")
        log_tz = execute_sql(cursor, "SHOW log_timezone;", fetch_one=True)
        status = "FAIL"
        if isinstance(log_tz, str) and log_tz.startswith("SQL_"):
            actual_tz = log_tz
        elif log_tz and log_tz.upper() in ['UTC', 'GMT']:
            status = "PASS"
            actual_tz = log_tz
        elif log_tz:
            actual_tz = log_tz
            write_output("  Warning: log_timezone is set, but not to UTC/GMT. Verify against site policy.")
            status="FAIL" # Consider FAIL unless known site policy allows it
        else:
            actual_tz = "Not Set"

        write_output("  Expected: 'UTC', 'GMT' (or site policy)")
        write_output(f"  Actual:   {actual_tz}")
        write_output(f"  Status:   {status}")


        # 3.2 Ensure the PostgreSQL Audit Extension (pgAudit) is enabled (Automated)
        write_output("\n[3.2] Ensure the PostgreSQL Audit Extension (pgAudit) is enabled (Automated)")
        preload_libs = execute_sql(cursor, "SHOW shared_preload_libraries;", fetch_one=True)
        pgaudit_loaded = False
        if isinstance(preload_libs, str) and not preload_libs.startswith("SQL_"):
             if 'pgaudit' in preload_libs.lower():
                  pgaudit_loaded = True

        pgaudit_active = False
        if pgaudit_loaded:
             # Check if extension is created in the current DB (might need check across all DBs?)
             try:
                 # Check if the pgaudit.log setting exists (implies extension is active)
                 pgaudit_log_setting = execute_sql(cursor, "SHOW pgaudit.log;", fetch_one=True)
                 # If the SHOW command doesn't raise an UndefinedParameter error, it's likely active
                 if not (isinstance(pgaudit_log_setting, str) and pgaudit_log_setting.startswith("SQL_INFO:")):
                     pgaudit_active = True
             except Exception as e:
                 write_output(f"  Info: Could not check pgaudit.log setting (may not be active): {e}")

        status = "PASS" if pgaudit_loaded and pgaudit_active else "FAIL"
        write_output(f"  Actual: shared_preload_libraries contains pgaudit: {pgaudit_loaded}")
        write_output(f"  Actual: pgaudit appears active (pgaudit.log setting exists): {pgaudit_active}")
        write_output("  Expected: 'pgaudit' in shared_preload_libraries AND extension active.")
        write_output(f"  Status:   {status}")

    else:
         write_output("  Skipping DB-dependent checks in Section 3 due to connection failure.")

    # == Section 4: User Access and Authorization ==
    write_output("\nSection 4: User Access and Authorization")
    if cursor:
        # 4.5 Ensure excessive function privileges are revoked (Automated)
        write_output("\n[4.5] Ensure excessive function privileges are revoked (Automated)")
        # Check for SECURITY DEFINER functions NOT owned by superusers or trusted roles
        # This is complex: requires identifying superusers and joining pg_proc with pg_authid
        # Simplified check: List SECURITY DEFINER functions for manual review
        sql_secdef = """
            SELECT n.nspname, p.proname, pg_get_function_identity_arguments(p.oid) as args, r.rolname as owner
            FROM pg_proc p
            JOIN pg_namespace n ON p.pronamespace = n.oid
            JOIN pg_authid r ON p.proowner = r.oid
            WHERE p.prosecdef = true
              AND n.nspname NOT IN ('pg_catalog', 'information_schema')
              AND r.rolname != 'postgres'; -- Exclude functions owned by 'postgres' (adjust if superuser name differs)
        """
        secdef_funcs = execute_sql(cursor, sql_secdef)
        status = "FAIL" # Assume fail unless proven otherwise; requires manual review
        if isinstance(secdef_funcs, str) and secdef_funcs.startswith("SQL_"):
            write_output(f"  Could not query SECURITY DEFINER functions: {secdef_funcs}")
        elif not secdef_funcs:
             write_output("  Actual: No SECURITY DEFINER functions found owned by non-postgres users in non-system schemas.")
             status = "PASS" # Consider pass if none found (best case)
        else:
             write_output("  Actual: Found SECURITY DEFINER functions requiring manual review:")
             for schema, func, args, owner in secdef_funcs:
                  write_output(f"    - {schema}.{func}({args}) OWNER: {owner}")
             write_output("    Manual review needed to ensure these functions do not grant excessive privileges.")

        write_output("  Expected: SECURITY DEFINER functions should be reviewed to ensure they don't grant excessive privileges.")
        write_output(f"  Status:   {status} (Manual Review Recommended)")

        # 4.8 Ensure the set_user extension is installed (Automated)
        write_output("\n[4.8] Ensure the set_user extension is installed (Automated)")
        # Check pg_available_extensions (implies installed in contrib, but not necessarily created)
        # Better: check pg_extension
        sql_set_user = "SELECT extname FROM pg_extension WHERE extname = 'set_user';"
        set_user_ext = execute_sql(cursor, sql_set_user)
        status = "FAIL"
        if isinstance(set_user_ext, str) and set_user_ext.startswith("SQL_"):
             write_output(f"  Could not check pg_extension: {set_user_ext}")
        elif set_user_ext:
            status = "PASS"
            write_output("  Actual: set_user extension is installed in the current database.")
        else:
            write_output("  Actual: set_user extension is NOT installed in the current database.")

        write_output("  Expected: set_user extension should be installed (if used for privilege escalation control).")
        write_output(f"  Status:   {status}")


    else:
        write_output("  Skipping DB-dependent checks in Section 4 due to connection failure.")


    # == Section 5: Connection and Login ==
    write_output("\nSection 5: Connection and Login")

    if cursor:
        # 5.5 Ensure per-account connection limits are used (Automated)
        write_output("\n[5.5] Ensure per-account connection limits are used (Automated)")
        sql_conn_limit = """
            SELECT rolname, rolconnlimit
            FROM pg_roles
            WHERE rolcanlogin = true      -- Only check users who can log in
              AND rolname NOT LIKE 'pg_%' -- Exclude internal roles
              AND rolconnlimit = -1;      -- Find users with no limit
        """
        unlimited_users = execute_sql(cursor, sql_conn_limit)
        status = "FAIL"
        if isinstance(unlimited_users, str) and unlimited_users.startswith("SQL_"):
            write_output(f"  Actual: Could not check connection limits: {unlimited_users}")
        elif not unlimited_users:
            status = "PASS"
            write_output("  Actual: All non-internal login roles have a connection limit set (not -1).")
        else:
            users_list = [user[0] for user in unlimited_users]
            write_output(f"  Actual: Found login roles with no connection limit (-1): {', '.join(users_list)}")

        write_output("  Expected: All non-internal login roles should have rolconnlimit != -1.")
        write_output(f"  Status:   {status}")

    else:
         write_output("  Skipping DB-dependent checks in Section 5 due to connection failure.")


    # == Section 6: PostgreSQL Settings ==
    write_output("\nSection 6: PostgreSQL Settings")

    if cursor:
         # 6.2 Ensure 'backend' runtime parameters are configured correctly (Automated)
         write_output("\n[6.2] Ensure specific 'backend' runtime parameters are configured correctly (Automated)")
         # Check specific params mentioned in benchmark rationale/audit [cite: 975, 976]
         # ignore_system_indexes = off
         passed_idx = check_pg_variable(cursor, 'ignore_system_indexes', False)
         write_output("-" * 10)
         # jit_debugging_support = off
         passed_jit_debug = check_pg_variable(cursor, 'jit_debugging_support', False)
         write_output("-" * 10)
         # jit_profiling_support = off
         passed_jit_prof = check_pg_variable(cursor, 'jit_profiling_support', False)
         write_output("-" * 10)
         # log_connections = on (Covered in 3.1.20)
         # log_disconnections = on (Covered in 3.1.21)
         # post_auth_delay = 0
         passed_auth_delay = check_pg_variable(cursor, 'post_auth_delay', 0)

         backend_passed = passed_idx and passed_jit_debug and passed_jit_prof and passed_auth_delay
         write_output(f"  Overall Status (Specific Backend Checks): {'PASS' if backend_passed else 'FAIL'}")

         # 6.7 Ensure FIPS 140-2 OpenSSL Cryptography Is Used (Automated)
         write_output("\n[6.7] Ensure FIPS 140-2 OpenSSL Cryptography Is Used (Automated)")
         # This check is OS specific (RHEL/CentOS/Rocky)
         fips_output = run_shell_command("fips-mode-setup --check", ignore_errors=True, use_sudo=True)
         status = "FAIL"
         if "CMD_ERROR: Command not found" in fips_output:
              actual_fips = "fips-mode-setup command not found (likely not RHEL-based system)."
              status = "NA"
         elif "FIPS mode is enabled" in fips_output:
              status = "PASS"
              actual_fips = "Enabled"
         elif "FIPS mode is disabled" in fips_output:
              actual_fips = "Disabled"
         else:
              actual_fips = f"Unknown or Error: {fips_output}"

         write_output("  Expected: FIPS mode should be enabled (on compatible OS).")
         write_output(f"  Actual:   {actual_fips}")
         write_output(f"  Status:   {status}")

         # 6.8 Ensure TLS is enabled and configured correctly (Automated)
         write_output("\n[6.8] Ensure TLS (SSL) is enabled (Automated)")
         # Basic check for ssl = on
         tls_passed = check_pg_variable(cursor, 'ssl', True)
         # Deeper checks (cert files exist, permissions) require OS access and path info
         if tls_passed:
              cert_file = execute_sql(cursor, "SHOW ssl_cert_file;", fetch_one=True)
              key_file = execute_sql(cursor, "SHOW ssl_key_file;", fetch_one=True)
              files_ok = True
              if cert_file and not (isinstance(cert_file, str) and cert_file.startswith("SQL_")):
                   cert_path = os.path.join(pgdata_dir, cert_file) if pgdata_dir and not os.path.isabs(cert_file) else cert_file
                   write_output("  Checking cert file permissions...")
                   # Perms not specified, check readable by postgres user
                   if not check_file_permissions(cert_path, r'-r[w-][-------]', POSTGRES_USER, POSTGRES_GROUP, use_sudo=True):
                       files_ok = False
              else:
                  write_output(f"  Warning: Could not get or validate ssl_cert_file path ({cert_file})")
                  files_ok = False # Fail if cert path not set

              if key_file and not (isinstance(key_file, str) and key_file.startswith("SQL_")):
                   key_path = os.path.join(pgdata_dir, key_file) if pgdata_dir and not os.path.isabs(key_file) else key_file
                   write_output("  Checking key file permissions...")
                   # Key file needs stricter perms, e.g., 0600 [cite: 1148]
                   if not check_file_permissions(key_path, r'-rw-------', POSTGRES_USER, POSTGRES_GROUP, use_sudo=True):
                       files_ok = False
              else:
                   write_output(f"  Warning: Could not get or validate ssl_key_file path ({key_file})")
                   files_ok = False # Fail if key path not set

              if not files_ok:
                   tls_passed = False # Overall fail if file checks fail

         write_output(f"  Overall Status (SSL=on and basic file checks): {'PASS' if tls_passed else 'FAIL'}")


         # 6.9 Ensure that TLSv1.3, or later, is configured (Automated)
         write_output("\n[6.9] Ensure ssl_min_protocol_version is TLSv1.3 or later (Automated)")
         # Note: Benchmark says TLSv1.3 OR LATER. Check needs adapting if TLSv1.4+ exists.
         # For now, check >= TLSv1.3 (TLSv1.3 is the highest common modern version)
         check_pg_variable(cursor, 'ssl_min_protocol_version', 'TLSv1.3', '>=') # Simple string comparison works here


         # 6.10 Ensure Weak SSL/TLS Ciphers Are Disabled (Automated)
         write_output("\n[6.10] Ensure Weak SSL/TLS Ciphers Are Disabled (Automated)")
         # Requires checking 'ssl_ciphers' against a list of known weak ciphers or comparing to a recommended strong set.
         # Complex to automate perfectly. Simplified check: ensure default isn't used if weak.
         # Default is 'HIGH:MEDIUM:+3DES:!aNULL'. Check if it's NOT this default (implies customization).
         is_default = check_pg_variable(cursor, 'ssl_ciphers', 'HIGH:MEDIUM:+3DES:!aNULL', '==')
         write_output("  Expected: ssl_ciphers should be customized to exclude weak ciphers (not default). Manual review recommended.")
         write_output(f"  Status:   {'FAIL' if is_default else 'PASS'} (Based on *not* being default)")


         # 6.11 Ensure the pgcrypto extension is installed and configured correctly (Automated)
         write_output("\n[6.11] Ensure the pgcrypto extension is installed (Automated)")
         # Check if available (part of contrib usually)
         sql_pgcrypto_avail = "SELECT name FROM pg_available_extensions WHERE name = 'pgcrypto';"
         avail = execute_sql(cursor, sql_pgcrypto_avail)
         available = isinstance(avail, list) and bool(avail)

         # Check if installed (created) in current DB
         sql_pgcrypto_inst = "SELECT extname FROM pg_extension WHERE extname = 'pgcrypto';"
         inst = execute_sql(cursor, sql_pgcrypto_inst)
         installed = isinstance(inst, list) and bool(inst)

         write_output(f"  Actual: pgcrypto Available = {available}, Installed in current DB = {installed}")
         write_output("  Expected: pgcrypto should be available and installed if required for data-at-rest encryption.")
         # Status depends on requirement. Let's PASS if available, WARN if not installed.
         status = "PASS" if available else "FAIL"
         if available and not installed:
              write_output("  Info: pgcrypto is available but not installed in this database.")
              # Keep status as PASS, but user should install if needed.
         elif not available:
              write_output("  Warning: pgcrypto extension package might be missing from the installation.")

         write_output(f"  Status:   {status} (Install/Create if needed)")

    else:
         write_output("  Skipping DB-dependent checks in Section 6 due to connection failure.")

    # == Section 7: Replication ==
    write_output("\nSection 7: Replication")
    if cursor:
         # 7.2 Ensure logging of replication commands is configured (Automated)
         write_output("\n[7.2] Ensure logging of replication commands is configured (Automated)")
         check_pg_variable(cursor, 'log_replication_commands', True)

         # 7.4 Ensure WAL archiving is configured and functional (Automated)
         write_output("\n[7.4] Ensure WAL archiving is configured and functional (Automated)")
         archive_mode = execute_sql(cursor, "SHOW archive_mode;", fetch_one=True)
         archive_cmd = execute_sql(cursor, "SHOW archive_command;", fetch_one=True)
         archive_lib = execute_sql(cursor, "SHOW archive_library;", fetch_one=True)
         status = "FAIL"
         actual_arch = f"Mode={archive_mode}, Cmd='{archive_cmd}', Lib='{archive_lib}'"

         # archive_mode must be 'on' or 'always'
         mode_ok = archive_mode in ['on', 'always']
         # EITHER command OR library must be set to something non-empty
         cmd_or_lib_ok = (archive_cmd and archive_cmd != '' and archive_cmd != '(disabled)') or \
                         (archive_lib and archive_lib != '' and archive_lib != '(disabled)')

         if mode_ok and cmd_or_lib_ok:
              status = "PASS"
              # Note: Functional check requires checking pg_stat_archiver or logs externally

         write_output("  Expected: archive_mode=on/always AND (archive_command OR archive_library is set).")
         write_output(f"  Actual:   {actual_arch}")
         write_output(f"  Status:   {status} (Config check only; functional check needs manual verification)")

    else:
         write_output("  Skipping DB-dependent checks in Section 7 due to connection failure.")


    # == Section 8: Special Configuration Considerations ==
    write_output("\nSection 8: Special Configuration Considerations")
    if cursor:
         # 8.2 Ensure the backup and restore tool, 'pgBackRest', is installed and configured (Automated)
         write_output("\n[8.2] Ensure 'pgBackRest' is installed (Automated)")
         # Simple check if command exists
         output = run_shell_command("pgbackrest", ignore_errors=True)
         status = "FAIL"
         if "pgBackRest" in output and "command not found" not in output.lower() and "CMD_ERROR" not in output :
              status = "PASS"
              actual_out = "pgbackrest command found."
         elif "command not found" in output.lower():
              actual_out = "pgbackrest command not found."
         else:
              actual_out = f"Error checking pgbackrest: {output}"

         write_output("  Expected: pgBackRest command should be available if used as backup tool.")
         write_output(f"  Actual:   {actual_out}")
         write_output(f"  Status:   {status} (Install/Configure if needed)")

    else:
        write_output("  Skipping DB-dependent checks in Section 8 due to connection failure.")


    # --- Cleanup ---
    write_output("-" * 40)
    write_output(f"Check completed - {datetime.datetime.now()}")
    if cursor:
        cursor.close()
    if conn:
        conn.close()
        write_output("PostgreSQL connection closed.")