#!/bin/bash

# Check if running as root
if [ "$(whoami)" != "root" ]; then
  echo "You need to be root to use this program"
  exit 1
fi

# Function to enable IP forwarding
enable_ip_forward() {
  # Define the output file path for the new configuration
  output_file="/etc/systemd/network/Router-$ethDevice.network"

  # Write the configuration to the file
  sudo bash -c "cat <<EOL > $output_file
[Match]
Name=$ethDevice

[Network]
Address=$ipAddress/24
DHCPServer=yes
DNS=8.8.8.8 8.8.4.4

[DHCPServer]
PoolOffset=100
PoolSize=50
LeaseTime=1h
EOL"
  echo "Configuration file has been created at $output_file"
  # Restart systemd-networkd to apply the new configuration
  sudo systemctl restart systemd-networkd
  # Enable IP forwarding
  echo 1 > /proc/sys/net/ipv4/ip_forward
  # Add iptables rules for NAT and forwarding
  add_iptables_rule "-t nat -A POSTROUTING -o $wifiDevice -j MASQUERADE"
  add_iptables_rule "-A FORWARD -i $wifiDevice -o $ethDevice -m state --state RELATED,ESTABLISHED -j ACCEPT"
  add_iptables_rule "-A FORWARD -i $ethDevice -o $wifiDevice -j ACCEPT"
}

# Function to disable IP forwarding and revert settings
disable_ip_forward() {
  # Revert router settings
  sudo rm "/etc/systemd/network/Router-$ethDevice.network"
  sudo systemctl restart systemd-networkd
  # Disable IP forwarding
  echo 0 > /proc/sys/net/ipv4/ip_forward
  # Remove iptables rules
  remove_iptables_rule "-t nat -D POSTROUTING -o $wifiDevice -j MASQUERADE"
  remove_iptables_rule "-D FORWARD -i $wifiDevice -o $ethDevice -m state --state RELATED,ESTABLISHED -j ACCEPT"
  remove_iptables_rule "-D FORWARD -i $ethDevice -o $wifiDevice -j ACCEPT"
}

# Function to add iptables rule
add_iptables_rule() {
  sudo iptables $1
}

# Function to remove iptables rule
remove_iptables_rule() {
  sudo iptables $1
}

# Detect network interfaces
interfaces=$(ip -o link show)
ethDevice=""
wifiDevice=""
correctDevices="n"
ipAddress="172.37.37.1"

# Identify Ethernet and WiFi devices
while IFS= read -r line; do
  iface=$(echo "$line" | awk -F': ' '{print $2}')
  
  if [[ "$iface" =~ ^(en|eth|eno) ]]; then
    ethDevice="$iface"
  fi
  
  if [[ "$iface" =~ ^wl ]]; then
    wifiDevice="$iface"
  fi
done <<< "$interfaces"

# Check if router configuration file exists
if [ -f "/etc/systemd/network/Router-$ethDevice.network" ]; then
  echo -n "Router settings already exist. Would you like to revert them? (Y/n) "
  read answer
  if [ "$answer" = "n" ]; then
    echo "Exiting program."
    exit 0
  fi
  disable_ip_forward
  exit 0
fi

# Prompt user for correct network devices if needed
echo "Ethernet device: $ethDevice"
echo "WiFi device    : $wifiDevice"

while [ "$correctDevices" = "n" ]; do
  echo -n "Are these your WiFi and Ethernet devices? (Y/n) "
  read correctDevices

  if [ "$correctDevices" = "n" ]; then
    ip addr
    echo -n "Put your Ethernet device: "
    read ethDevice
    echo -n "Put your WiFi device: "
    read wifiDevice
  fi
done

# Enable IP forwarding and configure router settings
enable_ip_forward

exit 0
