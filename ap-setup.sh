#!/bin/sh

usage() {
    echo "Usage: sudo $0"
}

[ "$(id -u)" -ne 0 ] && usage && exit 1

read -p "Enter SSID name: " AP_SSID
read -p "Enter passphrase: " AP_PASS

apt-get update -yqq && apt-get upgrade -yqq
apt-get install dnsmasq hostapd -yqq

cat >> /etc/network/interfaces <<EOF

auto lo
iface lo inet loopback

allow-hotplug eth0
iface eth0 inet manual
    pre-up iptables-restore < /etc/iptables.ipv4.nat

allow-hotplug wlan0
iface wlan0 inet manual
EOF

cat >> /etc/dhcpcd.conf <<EOF
interface wlan0
static ip_address=192.168.137.1/24
static routers=192.168.137.1
static domain_name_servers=8.8.8.8 8.8.4.4
EOF

cat > /etc/dnsmasq.conf <<EOF
interface=wlan0
dhcp-range=192.168.137.10,192.168.137.100,12h
dhcp-option=3,192.168.137.1
dhcp-option=6,192.168.137.1
EOF

cat > /etc/hostapd/hostapd.conf <<EOF
interface=wlan0
driver=nl80211
ssid=${AP_SSID}
hw_mode=g
channel=6
auth_algs=1
macaddr_acl=0
wpa=2
wpa_passphrase=${AP_PASS}
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
EOF

sed -i 's/^#DAEMON_CONF=.*/DAEMON_CONF="\/etc\/hostapd\/hostapd.conf"/g' /etc/default/hostapd

# Enable forwarding
sed -i 's/^#net.ipv4.ip_forward.*/net.ipv4.ip_forward=1/g' /etc/sysctl.conf
sysctl -p

# NAT
iptables -F
iptables -t nat -F
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
iptables -A FORWARD -i eth0 -o wlan0 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i wlan0 -o eth0 -j ACCEPT
iptables-save > /etc/iptables.ipv4.nat

# Enable services
systemctl enable dhcpcd
systemctl enable dnsmasq
systemctl enable hostapd

read -p "Configuration complete. Press ENTER to reboot... " REPLY
shutdown -r now
