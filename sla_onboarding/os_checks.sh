#!/bin/bash
# Basic OS related checks

os_summary() {
  echo "# System Summary ######################"
  echo "        Date | $(date -u)"
  echo "    Hostname | $(hostname)"
  echo "      Uptime | $(uptime -p)"
  echo "    Platform | $(uname -o)"
  if command -v lsb_release >/dev/null 2>&1; then
    echo "     Release | $(lsb_release -d | cut -f2)"
  fi
  echo "      Kernel | $(uname -r)"
  echo "Architecture | CPU = $(uname -m), OS = 64-bit"
  echo "   Threading | $(getconf GNU_LIBPTHREAD_VERSION)"
  echo "     SELinux | $(getenforce 2>/dev/null || echo 'No SELinux detected')"
  echo " Virtualized | $(systemd-detect-virt || echo 'No virtualization detected')"
  echo "# Processor ##################################################"
  lscpu | grep -E '^CPU\(s\):|Model name|Socket\(s\):|Thread\(s\) per core:|Core\(s\) per socket:'
  echo "# Memory #####################################################"
  free -h
  echo "# Mounted Filesystems ########################################"
  df -h | grep -vE '^tmpfs|cdrom'
  echo "# Network Config #############################################"
  echo " FIN Timeout | $(sysctl net.ipv4.tcp_fin_timeout | awk '{print $3}')"
  echo "  Port Range | $(sysctl net.ipv4.ip_local_port_range | awk '{print $3}')"
  echo "# Interface Statistics #######################################"
  ip -s link show | awk '/^[0-9]+: / {print \"\"; print $2} {print $1, $2, $3}'
  echo "# Top Processes ##############################################"
  top -b -n 1 | head -n 15
  if command -v aa-status >/dev/null 2>&1; then
    echo "# AppArmor Status ############################################"
    aa-status 2>/dev/null
  else
    echo "AppArmor status: not installed"
  fi
}

os_security() {
  echo "# Security Configuration #################################"
  echo "    Firewall | $(systemctl is-active firewalld 2>/dev/null || echo 'Not running')"
  echo "         SSH | $(systemctl is-active sshd 2>/dev/null || echo 'Not running')"
  echo "   SSH Users | $(grep -c '^[^:]*:[^:]*:[0-9]*:.*:/bin/bash' /etc/passwd) shell users"
  echo "        sudo | $(getent group sudo wheel 2>/dev/null | wc -l) admin groups"
  echo "# SSH Configuration ###################################"
  if [ -f /etc/ssh/sshd_config ]; then
    echo "SSH Config: /etc/ssh/sshd_config ($(stat -c%Y /etc/ssh/sshd_config | xargs -I{} date -d @{} '+%Y-%m-%d %H:%M'))"
    grep -E '^(Port|PermitRootLogin|PasswordAuthentication|PubkeyAuthentication)' /etc/ssh/sshd_config 2>/dev/null | sed 's/^/  /'
  fi
}

os_storage() {
  echo "# Storage Configuration ##################################"
  echo "Mount Points:"
  findmnt -D 2>/dev/null | grep -E '(ext[234]|xfs|btrfs)' | awk '{print "  " $1, $2, $3}' || echo "  findmnt not available"
  echo "LVM Volumes:"
  if command -v lvs >/dev/null 2>&1; then
    lvs 2>/dev/null | grep -v LV | sed 's/^/  /' || echo "  No LVM detected"
  else
    echo "  LVM tools not installed"
  fi
  echo "Disk Usage by Mount:"
  df -h | grep -vE '^tmpfs|cdrom|udev' | awk 'NR>1 {print "  " $6, $5, $4}'
  echo "Block Devices:"
  lsblk 2>/dev/null | sed 's/^/  /' || echo "  lsblk not available"
}

os_services() {
  echo "# Database-Related Services ##############################"
  systemctl list-units --type=service --state=active 2>/dev/null | grep -E '(postgres|mysql|mariadb|oracle)' | sed 's/^/  /' || echo "  No database services found"
  echo "# Backup/Monitoring Services ############################"
  systemctl list-units --type=service --state=active 2>/dev/null | grep -E '(cron|zabbix|prometheus|telegraf|backup)' | sed 's/^/  /' || echo "  No monitoring services found"
  echo "# Failed Services ####################################"
  systemctl list-units --failed 2>/dev/null | grep -v "0 loaded units" | sed 's/^/  /' || echo "  No failed services"
}

os_patches() {
  echo "# System Maintenance #####################################"
  echo "Last Boot | $(who -b 2>/dev/null | awk '{print $3, $4}' || uptime -s 2>/dev/null || echo 'Unknown')"
  if command -v yum >/dev/null 2>&1; then
    echo "Updates   | $(yum check-update 2>/dev/null | wc -l) packages available"
    echo "Last Update | $(rpm -qa --last | head -1 | awk '{print $3, $4, $5, $6}')"
  elif command -v apt >/dev/null 2>&1; then
    echo "Updates   | $(apt list --upgradable 2>/dev/null | wc -l) packages available"
    echo "Last Update | $(stat -c %y /var/log/apt/history.log 2>/dev/null | cut -d' ' -f1 || echo 'Unknown')"
  elif command -v zypper >/dev/null 2>&1; then
    echo "Updates   | $(zypper list-updates 2>/dev/null | wc -l) packages available"
  else
    echo "Package manager not recognized"
  fi
  echo "Kernel    | Running: $(uname -r), Available: $(ls /boot/vmlinuz-* 2>/dev/null | tail -1 | sed 's/.*vmlinuz-//' || echo 'Unknown')"
}

# Monitoring solution discovery
os_monitoring_discovery() {
  echo "# Monitoring Solutions Discovery #########################"
  
  # Common monitoring agents and tools
  local monitoring_tools=(
    "nagios"
    "zabbix-agent" 
    "zabbix-agent2"
    "collectd"
    "telegraf"
    "node_exporter"
    "prometheus"
    "grafana-server"
    "pmm-agent"
    "datadog-agent"
    "newrelic-daemon"
    "splunk"
    "elastic-agent"
    "filebeat"
    "metricbeat"
    "osquery"
    "wazuh-agent"
    "sensu-agent"
  )
  
  echo "--- Process-Based Detection ---"
  local found_processes=0
  for tool in "${monitoring_tools[@]}"; do
    if pgrep -f "$tool" >/dev/null 2>&1; then
      local process_count=$(pgrep -f "$tool" | wc -l)
      echo "Running Process|$tool ($process_count processes)"
      found_processes=$((found_processes + 1))
    fi
  done
  
  if [ $found_processes -eq 0 ]; then
    echo "Running Processes|No common monitoring agents detected"
  fi
  
  # Service-based detection
  echo "--- Service-Based Detection ---"
  local found_services=0
  for tool in "${monitoring_tools[@]}"; do
    if systemctl is-active "$tool" >/dev/null 2>&1; then
      local service_status=$(systemctl is-active "$tool")
      echo "Active Service|$tool ($service_status)"
      found_services=$((found_services + 1))
    elif systemctl list-units --all | grep -q "$tool"; then
      local service_status=$(systemctl is-active "$tool" 2>/dev/null || echo "inactive")
      echo "Installed Service|$tool ($service_status)"
      found_services=$((found_services + 1))
    fi
  done
  
  if [ $found_services -eq 0 ]; then
    echo "System Services|No monitoring services detected"
  fi
  
  # Network monitoring detection
  echo "--- Network Monitoring Detection ---"
  local monitoring_ports=(
    "5666:NRPE"
    "10050:Zabbix Agent"
    "10051:Zabbix Server" 
    "8125:StatsD"
    "9090:Prometheus"
    "3000:Grafana"
    "8086:InfluxDB"
    "9100:Node Exporter"
    "42000:PMM"
    "42001:PMM mysqld_exporter"
    "42002:PMM postgres_exporter"
  )
  
  local found_ports=0
  for port_info in "${monitoring_ports[@]}"; do
    local port="${port_info%%:*}"
    local service="${port_info##*:}"
    
    if netstat -tlnp 2>/dev/null | grep ":$port " >/dev/null; then
      local process=$(netstat -tlnp 2>/dev/null | grep ":$port " | awk '{print $7}' | head -1)
      echo "Listening Port|$port ($service) - $process"
      found_ports=$((found_ports + 1))
    fi
  done
  
  if [ $found_ports -eq 0 ]; then
    echo "Monitoring Ports|No monitoring ports detected"
  fi
  
  # Configuration file detection
  echo "--- Configuration File Detection ---"
  local config_paths=(
    "/etc/nagios"
    "/etc/zabbix"
    "/etc/collectd"
    "/etc/telegraf"
    "/etc/prometheus"
    "/etc/grafana"
    "/usr/local/percona/pmm-agent"
    "/etc/datadog-agent"
    "/etc/newrelic"
    "/opt/splunkforwarder"
    "/etc/osquery"
    "/var/ossec"
    "/etc/wazuh-agent"
  )
  
  local found_configs=0
  for config_path in "${config_paths[@]}"; do
    if [ -d "$config_path" ]; then
      local config_files=$(find "$config_path" -name "*.conf" -o -name "*.cfg" -o -name "*.yaml" -o -name "*.yml" 2>/dev/null | wc -l)
      if [ "$config_files" -gt 0 ]; then
        echo "Config Directory|$config_path ($config_files files)"
        found_configs=$((found_configs + 1))
      fi
    fi
  done
  
  if [ $found_configs -eq 0 ]; then
    echo "Config Directories|No monitoring configuration directories found"
  fi
  
  # Log shipping detection
  echo "--- Log Management Detection ---"
  local log_shippers=(
    "rsyslog"
    "syslog-ng"
    "fluentd"
    "fluent-bit"
    "logstash"
    "filebeat"
    "journalctl"
  )
  
  local found_loggers=0
  for logger in "${log_shippers[@]}"; do
    if command -v "$logger" >/dev/null 2>&1; then
      if systemctl is-active "$logger" >/dev/null 2>&1; then
        echo "Log Shipper|$logger (active)"
      else
        echo "Log Shipper|$logger (installed but inactive)"
      fi
      found_loggers=$((found_loggers + 1))
    fi
  done
  
  if [ $found_loggers -eq 0 ]; then
    echo "Log Shippers|No centralized log shippers detected"
  fi
  
  # SNMP detection
  echo "--- SNMP Detection ---"
  if systemctl is-active snmpd >/dev/null 2>&1; then
    echo "SNMP Agent|Active"
    if [ -f /etc/snmp/snmpd.conf ]; then
      local community_strings=$(grep -c "^community" /etc/snmp/snmpd.conf 2>/dev/null || echo "0")
      echo "SNMP Communities|$community_strings configured"
    fi
  elif command -v snmpd >/dev/null 2>&1; then
    echo "SNMP Agent|Installed but inactive"
  else
    echo "SNMP Agent|Not installed"
  fi
  
  # Cloud monitoring agents
  echo "--- Cloud Monitoring Detection ---"
  local cloud_agents=(
    "amazon-cloudwatch-agent"
    "google-cloud-ops-agent"
    "azure-monitoring-agent"
    "oci-monitoring-agent"
  )
  
  local found_cloud=0
  for agent in "${cloud_agents[@]}"; do
    if systemctl list-units --all | grep -q "$agent" || pgrep -f "$agent" >/dev/null 2>&1; then
      local status=$(systemctl is-active "$agent" 2>/dev/null || echo "detected")
      echo "Cloud Agent|$agent ($status)"
      found_cloud=$((found_cloud + 1))
    fi
  done
  
  if [ $found_cloud -eq 0 ]; then
    echo "Cloud Agents|No cloud monitoring agents detected"
  fi
  
  # Summary assessment
  echo "--- Monitoring Assessment ---"
  local total_found=$((found_processes + found_services + found_ports + found_configs + found_loggers))
  if [ $total_found -eq 0 ]; then
    echo "Monitoring Status|No monitoring infrastructure detected"
    echo "Monitoring Recommendation|Consider implementing monitoring for production support"
  elif [ $total_found -le 3 ]; then
    echo "Monitoring Status|Basic monitoring detected"
    echo "Monitoring Recommendation|Evaluate monitoring coverage for database services"
  else
    echo "Monitoring Status|Comprehensive monitoring infrastructure detected"
    echo "Monitoring Recommendation|Verify database-specific monitoring coverage"
  fi
}

