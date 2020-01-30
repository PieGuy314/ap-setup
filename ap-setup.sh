#!/bin/sh
#
# Create Raspberry Pi Access Point
#
# Should work with Raspbian Buster Lite (2019-09-26) - Clean install
#
# AP with user specified SSID/Pass/Chan on wlan0. Network traffic forwarded to eth0.
#
# Defaults:
#    IP of AP (wlan0): 192.168.137.1/24
#    DHCP server range: 192.168.137.10 - 192.168.137.100
#

usage() {
    echo "Usage: sudo $0"
}

[ "$(id -u)" -ne 0 ] && usage && exit 1

read -p "Enter SSID name: " AP_SSID
read -p "Enter passphrase: " AP_PASS
until [ "${AP_CHAN}" ] ; do
    read -p "Enter Wi-Fi channel (1,6,11): " AP_CHAN
    case ${AP_CHAN} in
        1|6|11)
            break;;
        *)
            echo -n "Invalid input. " && AP_CHAN=
            continue;;
    esac
done

apt-get update -yqq && apt-get upgrade -yqq
apt-get install dnsmasq hostapd -yqq

# Services not yet configured
systemctl stop dnsmasq
systemctl stop hostapd

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
nohook wpa_supplicant
EOF

cat > /etc/dnsmasq.conf <<EOF
interface=wlan0
dhcp-range=192.168.137.10,192.168.137.100,24h
dhcp-option=3,192.168.137.1
dhcp-option=6,192.168.137.1
EOF

cat > /etc/hostapd/hostapd.conf <<EOF
interface=wlan0
driver=nl80211
ssid=${AP_SSID}
hw_mode=g
channel=${AP_CHAN}
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
cat > /etc/iptables.ipv4.nat <<EOF
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
COMMIT
*nat
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A POSTROUTING -o eth0 -j MASQUERADE
COMMIT

# Enable services
systemctl restart dhcpcd
systemctl start dnsmasq
systemctl unmask hostapd
systemctl enable hostapd
systemctl start hostapd

read -p "Configuration complete. Press ENTER to reboot... " REPLY
shutdown -r now
