# PostgreSQL CIS Benchmark Checker Script

## Purpose

This Python script performs automated security configuration checks on a PostgreSQL 17 server based on the recommendations outlined in the **CIS PostgreSQL 17 Benchmark v1.0.0**. It helps identify potential security misconfigurations according to the benchmark's automated checks.

**Disclaimer:** This script only covers checks explicitly marked as **Automated** in the CIS benchmark document. **Manual** checks require human verification and are **not** performed by this script. Always refer to the official CIS benchmark document for complete guidance, rationale, and remediation steps.

## Prerequisites

1.  **Python 3:** Ensure Python 3 is installed on the Linux server where the script will run.
2.  **`psycopg2` Library:** Install the required PostgreSQL database adapter for Python:
    ```bash
    # Recommended: install with binary dependencies
    pip install "psycopg[binary]" 
    # Or standard install (might require build tools like gcc, python3-dev, libpq-dev)
    # pip install psycopg2 
    ```
3.  **Permissions:**
    * **Linux Permissions:** The user running the script needs permissions to:
        * Execute shell commands like `grep`, `find`, `ls`, `systemctl`, `fips-mode-setup`, `pg_config`, `pgbackrest`.
        * Read PostgreSQL configuration files (e.g., `postgresql.conf`, `pg_hba.conf`), user profile files (e.g., `.bashrc`), and potentially `/proc/*/environ`.
        * `sudo` access might be required for some commands (e.g., checking `/proc`, reading restricted files, running `fips-mode-setup`). The script includes placeholders for `sudo`.
    * **PostgreSQL Permissions:** The database user specified in the config file needs sufficient privileges to:
        * Connect to the specified database.
        * Execute `SHOW variable;` commands for various settings.
        * Query system catalogs like `pg_settings`, `pg_roles`, `pg_available_extensions`, `pg_proc`, `pg_class`, `pg_policy`, etc.
        * A PostgreSQL superuser account is often easiest, but a dedicated role with necessary permissions can be created (following the principle of least privilege).
4.  **Configuration File (`pg_config.ini`):**
    * Create a file named `pg_config.ini` in the same directory as the script.
    * Add the following content, replacing placeholder values with your PostgreSQL connection details:

        ```ini
        [postgresql]
        host = your_postgres_host 
        # e.g., localhost or an IP address
        port = your_postgres_port 
        # e.g., 5432
        user = your_postgres_user 
        # e.g., postgres or a dedicated check user
        password = your_postgres_password
        dbname = your_database_name 
        # e.g., postgres or any database the user can connect to
        ```
    * **Secure this file:** `chmod 600 pg_config.ini`

## How to Run

1.  Save the script as `postgresql_cis_checker.py`.
2.  Ensure `pg_config.ini` is created and populated correctly in the same directory.
3.  Run the script from the Linux console:
    ```bash
    python3 postgresql_cis_checker.py
    ```
    If `sudo` is needed for certain checks, you might need to run:
    ```bash
    sudo python3 postgresql_cis_checker.py 
    # Note: Ensure the postgresql section in pg_config.ini still points to the correct user/password needed for DB connection even when running as root.
    ```
4.  The script will print results to the console and save them to a timestamped text file (e.g., `postgresql_cis_check_YYYYMMDD_HHMMSS.txt`).

## Interpreting the Output

* The output file lists each automated check performed, grouped by the benchmark section.
* For each check:
    * **Expected:** Describes the secure state according to the CIS benchmark.
    * **Actual:** Shows the configuration value or status found on your server.
    * **Status:** Indicates `PASS` (configuration meets benchmark requirement), `FAIL` (configuration does not meet benchmark requirement), or `NA` (Not Applicable, e.g., the feature is disabled or not relevant).
* Review `FAIL` entries to identify areas requiring attention and remediation based on the CIS PostgreSQL 17 Benchmark document.

## Important Notes

* **Manual Checks:** This script **cannot** perform manual checks. These must be done separately. Examples include reviewing policies, checking `pg_hba.conf` logic, verifying backup integrity, and assessing complex privilege grants.
* **Environment Specifics:** Default paths (`postgresql.conf`, data directory, service names like `postgresql-17`), user names (`postgres`), and required tools (`fips-mode-setup`, `pg_config`, `pgbackrest`) might need adjustments based on your specific Linux distribution and PostgreSQL installation method.
* **Security:** Running checks, especially those requiring `sudo` or connecting as a privileged database user, should be done cautiously in production environments. Ensure the script and configuration file are secured.
* **Benchmark Version:** This script is based on **CIS PostgreSQL 17 Benchmark v1.0.0**. Ensure it matches the version you intend to comply with.