#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color

function agentinstall {
    echo -e "${GREEN}Installing additional packages...${NC}"
    apt-get -qq install -y xinetd libwww-perl
    cp ./scripts/observium_agent_xinetd /etc/xinetd.d/observium_agent_xinetd
    service xinetd restart
    cp ./scripts/observium_agent /usr/bin/observium_agent
    mkdir -p /usr/lib/observium_agent
    mkdir -p /usr/lib/observium_agent/scripts-available
    mkdir -p /usr/lib/observium_agent/scripts-enabled
    cp -r ./scripts/agent-local/* /usr/lib/observium_agent/scripts-available
    chmod +x /usr/bin/observium_agent
    ln -sf /usr/lib/observium_agent/scripts-available/dmi /usr/lib/observium_agent/scripts-enabled
    ln -sf /usr/lib/observium_agent/scripts-available/apache /usr/lib/observium_agent/scripts-enabled
    ln -sf /usr/lib/observium_agent/scripts-available/mysql /usr/lib/observium_agent/scripts-enabled

    echo "\$config['poller_modules']['unix-agent']                   = 1;" >> ./config.php
    echo -e "${GREEN}DONE! UNIX-agent is installed and this server is now monitored by Observium${NC}"
}

function snmpdinstall {
  echo -e "${GREEN}Installing snmpd...${NC}"
  apt-get -qq install -y snmpd

  cp ./scripts/distro /usr/local/bin/distro
  chmod +x /usr/local/bin/distro
  echo -e "${YELLOW}Reconfiguring local snmpd${NC}"
  echo "agentAddress  udp:127.0.0.1:161" > /etc/snmp/snmpd.conf
  snmpcommunity="$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-15};echo;)"
  echo "rocommunity $snmpcommunity" >> /etc/snmp/snmpd.conf
  
  # Distro sctipt
  echo "# This line allows Observium to detect the host OS if the distro script is installed" >> /etc/snmp/snmpd.conf
  echo "extend .1.3.6.1.4.1.2021.7890.1 distro /usr/local/bin/distro" >> /etc/snmp/snmpd.conf

  # Vendor/hardware extending
  if [ -f "/sys/devices/virtual/dmi/id/product_name" ]; then
    echo "# This lines allows Observium to detect hardware, vendor and serial" >> /etc/snmp/snmpd.conf
    echo "extend .1.3.6.1.4.1.2021.7890.2 hardware /bin/cat /sys/devices/virtual/dmi/id/product_name" >> /etc/snmp/snmpd.conf
    echo "extend .1.3.6.1.4.1.2021.7890.3 vendor   /bin/cat /sys/devices/virtual/dmi/id/sys_vendor" >> /etc/snmp/snmpd.conf
    echo "#extend .1.3.6.1.4.1.2021.7890.4 serial   /bin/cat /sys/devices/virtual/dmi/id/product_serial" >> /etc/snmp/snmpd.conf
  elif [ -f "/proc/device-tree/model" ]; then
    # ARM/RPi specific hardware
    echo "# This lines allows Observium to detect hardware, vendor and serial" >> /etc/snmp/snmpd.conf
    echo "extend .1.3.6.1.4.1.2021.7890.2 hardware /bin/cat /proc/device-tree/model" >> /etc/snmp/snmpd.conf
    echo "#extend .1.3.6.1.4.1.2021.7890.4 serial   /bin/cat /proc/device-tree/serial" >> /etc/snmp/snmpd.conf
  fi

  # Accurate uptime
  echo "# This line allows Observium to collect an accurate uptime" >> /etc/snmp/snmpd.conf
  echo "extend uptime /bin/cat /proc/uptime" >> /etc/snmp/snmpd.conf

  echo "# This line enables Observium's ifAlias description injection" >> /etc/snmp/snmpd.conf
  echo "#pass_persist .1.3.6.1.2.1.31.1.1.1.18 /usr/local/bin/ifAlias_persist" >> /etc/snmp/snmpd.conf
  
  service snmpd restart

  echo -e "${GREEN}DONE! UNIX-agent is installed and this server is now monitored by Observium${NC}"
}

if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}ERROR: You must be a root user${NC}" 2>&1
  exit 1
fi

ARCH=$(uname -m | sed 's/x86_//;s/i[3-6]86/32/')

if [ -f /etc/lsb-release ]; then
    . /etc/lsb-release
    OS=$DISTRIB_ID
    VER=$DISTRIB_RELEASE
elif [ -f /etc/debian_version ]; then
    OS=Debian  # XXX or Ubuntu??
    VER=$(cat /etc/debian_version)
else
    OS=$(uname -s)
    VER=$(uname -r)
fi

if [[ !$OS =~ ^(Ubuntu|Debian)$ ]]; then
    echo -e "${RED} [*] ERROR: This installscript does not support this distro, only Debian or Ubuntu supported. Use the manual guide at https://docs.observium.org/install_rhel7/ ${NC}"
    exit 1
fi

cat << "EOF"
  ___  _                         _
 / _ \| |__  ___  ___ _ ____   _(_)_   _ _ __ ___
| | | | '_ \/ __|/ _ \ '__\ \ / / | | | | '_ ` _ \
| |_| | |_) \__ \  __/ |   \ V /| | |_| | | | | | |
 \___/|_.__/|___/\___|_|    \_/ |_|\__,_|_| |_| |_|
EOF
echo -e "${GREEN}Welcome to Observium 'client installscript"
echo -e ""
echo "1. Install the UNIX-Agent"
echo "2. Install the SNMPD (snmpd-config will be overwritten)"
echo -n "(1-2):"
read -n 1 observ_ver
if [ $observ_ver = 1 ]; then
  agentinstall
  exit 1
elif [ $observ_ver = 2 ]; then
  snmpdinstall
  exit 1
fi