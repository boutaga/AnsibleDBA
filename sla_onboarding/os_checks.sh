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

