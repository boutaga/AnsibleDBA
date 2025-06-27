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

