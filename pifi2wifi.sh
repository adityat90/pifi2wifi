#!/bin/bash -e

#Created for 2015-05-05-raspbian-wheezy.img
#Reference:
#http://www.maketecheasier.com/set-up-raspberry-pi-as-wireless-access-point/
#http://www.daveconroy.com/turn-your-raspberry-pi-into-a-wifi-hotspot-with-edimax-nano-usb-ew-7811un-rtl8188cus-chipset/

#Install raspbian and boot pi with ethernet and two rtl8188cus wifi cards

#REMOVE JUNK AND UPDATE

#sudo apt-get purge wolfram-engine
#sudo apt-get update
#sudo apt-get upgrade
#sudo apt-get dist-upgrade
#sudo raspi-config
#echo Set the timezone and GPU memory to 16.
#sudo rpi-update 
#sudo reboot

#ADD EDUROAM (REQUIRES VALID LOGIN)

#Modified for general use case

MWIFI_SSID=$1;
MWIFI_PASSWORD=$2;
MAP_WIFI_SSID=$3;
MAP_WIFI_PASSWORD=$4;

# echo $MWIFI_SSID $MWIFI_PASSWORD $MAP_WIFI_SSID $MAP_WIFI_PASSWORD; 

sudo mv /etc/wpa_supplicant/wpa_supplicant.conf /etc/wpa_supplicant/wpa_supplicant.conf.bak
sudo rm -rf /etc/wpa_supplicant/wpa_supplicant.conf
cat <<EOF | sudo tee /etc/wpa_supplicant/wpa_supplicant.conf > /dev/null
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
network={
ssid="$MWIFI_SSID"
psk="$MWIFI_PASSWORD"
proto=RSN
key_mgmt=WPA-PSK
pairwise=CCMP
group=CCMP
auth_alg=OPEN
}
EOF
sudo chmod 600 /etc/wpa_supplicant/wpa_supplicant.conf

#CONFIGURE THE TWO WIFI NETWORKS (LEAVING WIRED FOR DEBUGGING)

sudo mv /etc/network/interfaces /etc/network/interfaces.bak
sudo rm -rf /etc/network/interfaces
cat <<EOF | sudo tee /etc/network/interfaces > /dev/null
auto lo
iface lo inet loopback

auto eth0
allow-hotplug eth0
iface eth0 inet manual

#auto wlan0
allow-hotplug wlan0
#iface wlan0 inet manual
#wpa-conf /etc/wpa_supplicant/wpa_supplicant.conf
iface wlan0 inet static
address 192.168.42.1
netmask 255.255.255.0

auto wlan1
allow-hotplug wlan1
iface wlan1 inet manual
wpa-conf /etc/wpa_supplicant/wpa_supplicant.conf

pre-up iptables-restore < /etc/iptables.ipv4.nat

EOF

#INSTALL THE DHCP SERVER AND CONFIGURE IT

sudo apt-get install isc-dhcp-server || true

sudo cp /etc/dhcp/dhcpd.conf /etc/dhcp/dhcpd.conf.bak
sudo sed -i: 's/^option domain-name/#option domain-name/g' /etc/dhcp/dhcpd.conf
sudo sed -i: 's/^#authoritative;/authoritative;/g' /etc/dhcp/dhcpd.conf

sudo rm -rf /etc/dhcp/dhcpd.conf
cat <<EOF | sudo tee -a /etc/dhcp/dhcpd.conf > /dev/null
subnet 192.168.42.0 netmask 255.255.255.0 {
range 192.168.42.10 192.168.42.50;
option broadcast-address 192.168.42.255;
option routers 192.168.42.1;
default-lease-time 600;
max-lease-time 7200;
option domain-name "local";
option domain-name-servers 8.8.8.8, 8.8.4.4;
}
EOF

sudo sed -i: 's/^INTERFACES=""/INTERFACES="wlan0"/g' /etc/default/isc-dhcp-server

#INSTALL HOSTAPD AND REPLACE WITH ALTERNATIVE FOR rtl8188cus

sudo apt-get install hostapd

# wget http://www.daveconroy.com/wp3/wp-content/uploads/2013/07/hostapd.zip
unzip hostapd.zip 
sudo mv /usr/sbin/hostapd /usr/sbin/hostapd.bak
sudo mv hostapd /usr/sbin/hostapd.edimax 
sudo ln -sf /usr/sbin/hostapd.edimax /usr/sbin/hostapd 
sudo chown root:root /usr/sbin/hostapd 
sudo chmod 755 /usr/sbin/hostapd

sudo rm -rf /etc/hostapd/hostapd.conf
cat <<EOF | sudo tee -a /etc/hostapd/hostapd.conf > /dev/null
interface=wlan0
#driver=nl80211
driver=rtl871xdrv
ssid=$MAP_WIFI_SSID
hw_mode=g
channel=6
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=1
wpa_passphrase=$MAP_WIFI_PASSWORD
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP CCMP
rsn_pairwise=TKIP CCMP
wpa_ptk_rekey=600
#ieee80211n=0
ieee8021x=0
eap_server=0
EOF

sudo sed -i: 's|^#DAEMON_CONF=""|DAEMON_CONF="/etc/hostapd/hostapd.conf"|g' /etc/default/hostapd

#ENABLE FORWARDING AND CONFIGURE IPTABLES

sudo sed -i: 's/^#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g' /etc/sysctl.conf
sudo sh -c "echo 1 > /proc/sys/net/ipv4/ip_forward"
sudo iptables -t nat -A POSTROUTING -o wlan1 -j MASQUERADE
sudo iptables -A FORWARD -i wlan1 -o wlan0 -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A FORWARD -i wlan0 -o wlan1 -j ACCEPT
sudo sh -c "iptables-save > /etc/iptables.ipv4.nat"

echo Restarting now.

sudo reboot now