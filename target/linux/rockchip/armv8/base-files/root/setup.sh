#!/bin/bash

# ---------------------------------------------------------
# put to /etc/uci-defaults/
# see default_postinst() in lib/functions.sh

function init_firewall() {
	zone_name=$(uci -q get firewall.@zone[1].name)
	[ "$zone_name" = "wan" ] || return 0

	uci set firewall.@zone[1].input='ACCEPT'
	uci set firewall.@zone[1].output='ACCEPT'
	uci set firewall.@zone[1].forward='ACCEPT'
	uci commit firewall
	fw3 reload
}

function init_network() {
	uci set network.globals.ula_prefix='fd00:ab:cd::/48'
	uci commit network
}

function disable_ipv6() {
	uci set 'network.lan.ipv6=off'
	uci set 'network.lan.delegate=0'
	uci set 'network.lan.force_link=0'

	uci set 'network.wan.ipv6=0'
	uci set 'network.wan.delegate=0'
	uci delete 'network.wan6'
	uci commit network

	uci set 'dhcp.lan.dhcpv6=disabled'
	uci set 'dhcp.lan.ra=disabled'
	uci commit dhcp
}

function init_lcd2usb() {
	if [ -f /usr/bin/lcd2usb_echo ]; then
		sed -i '/^exit 0.*/d' /etc/rc.local
		cat >> /etc/rc.local <<EOL
[ -f /usr/bin/lcd2usb_echo ] && (sleep 10 && /usr/bin/lcd2usb_echo)&
exit 0
EOL
		/usr/bin/lcd2usb_echo&
	fi
}

function init_system() {
	uci -q batch <<-EOF
		set system.@system[-1].hostname='$HOSTNAME'
		set system.@system[-1].ttylogin='1'
		commit system
	EOF
}

function init_samba4() {
	[ -f /etc/samba/smb.conf.template ] || return 0

	uci -q batch <<-EOF
		set samba4.@samba[0].name='$HOSTNAME'
		set samba4.@samba[0].workgroup='WORKGROUP'
		set samba4.@samba[0].description='$HOSTNAME'
		set samba4.@samba[0].homes='1'
		commit samba4
	EOF
}

function init_ttyd() {
	uci -q delete ttyd.@ttyd[0].interface
	uci commit ttyd
}

function init_luci_stat() {
	uci set luci_statistics.collectd_thermal.enable='1'
	uci set luci_statistics.collectd_thermal.Device="thermal_zone0 thermal_zone1"
	uci commit luci_statistics
}

function init_watchcat() {
	uci -q delete watchcat.@watchcat[-1]
	uci commit watchcat
	/etc/init.d/watchcat reload
}

function init_openssh() {
	local conf=/etc/ssh/sshd_config
	[ -f $conf ] || return 0

	sed "s/^#PermitRootLogin.*/PermitRootLogin yes/g" $conf -i.orig
	sed "s/^#\s*Banner/Banner/g" $conf -i
	/etc/init.d/sshd reload
}

function init_theme() {
	if [ "$PKG_UPGRADE" != 1 ]; then
		uci get luci.themes.Bootstrap >/dev/null 2>&1 && \
		uci batch <<-EOF
			set luci.main.mediaurlbase=/luci-static/bootstrap
			commit luci
		EOF
	fi
}

function init_root_home() {
	chmod 0700 /root
	mkdir -m 0700 -p /root/.ssh

	[ -x /bin/bash ] || return 0
	grep "^root.*bash" /etc/passwd >/dev/null && return 0
	sed "s/^\(root.*\/\)ash/\1bash/g" /etc/passwd -i-
}

function init_button() {
	local CONF=/etc/triggerhappy/triggers.d/example.conf
	grep "BTN_1" ${CONF} >/dev/null && return 0 
	[ -f ${CONF} ] && echo 'BTN_1 1 /sbin/reboot' >> ${CONF}
}

function clean_fstab() {
	while uci -q del fstab.@mount[-1]; do true; done
	uci commit fstab
}


# ---------------------------------------------------------
# Refer: package/network/services/odhcpd/files/odhcpd.defaults

function clean_static_host() {
	while uci -q del dhcp.@host[-1]; do true; done
}

function add_static_host() {
	uci add dhcp host
	uci set dhcp.@host[-1].mac=$1
	uci set dhcp.@host[-1].ip=$2
	uci set dhcp.@host[-1].name=$3
	uci commit dhcp
}

# ---------------------------------------------------------

HOSTNAME="FriendlyWrt"

if [ "${1,,}" = "all" ]; then
	init_network
	init_firewall
	init_lcd2usb
	init_system
	init_samba4
	init_ttyd
	init_luci_stat
	init_watchcat
	init_openssh
	init_theme
	init_root_home
	init_button
	clean_fstab
fi

