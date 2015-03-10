#!/bin/sh
append DRIVERS "mac80211"

lookup_phy() {
	[ -n "$phy" ] && {
		[ -d /sys/class/ieee80211/$phy ] && return
	}

	local devpath
	config_get devpath "$device" path
	[ -n "$devpath" ] && {
		for _phy in /sys/devices/$devpath/ieee80211/phy*; do
			[ -e "$_phy" ] && {
				phy="${_phy##*/}"
				return
			}
		done
	}

	local macaddr="$(config_get "$device" macaddr | tr 'A-Z' 'a-z')"
	[ -n "$macaddr" ] && {
		for _phy in /sys/class/ieee80211/*; do
			[ -e "$_phy" ] || continue

			[ "$macaddr" = "$(cat ${_phy}/macaddress)" ] || continue
			phy="${_phy##*/}"
			return
		done
	}
	phy=
	return
}

find_mac80211_phy() {
	local device="$1"

	config_get phy "$device" phy
	lookup_phy
	[ -n "$phy" -a -d "/sys/class/ieee80211/$phy" ] || {
		echo "PHY for wifi device $1 not found"
		return 1
	}
	config_set "$device" phy "$phy"

	config_get macaddr "$device" macaddr
	[ -z "$macaddr" ] && {
		config_set "$device" macaddr "$(cat /sys/class/ieee80211/${phy}/macaddress)"
	}

	return 0
}

check_mac80211_device() {
	config_get phy "$1" phy
	[ -z "$phy" ] && {
		find_mac80211_phy "$1" >/dev/null || return 0
		config_get phy "$1" phy
	}
	[ "$phy" = "$dev" ] && found=1
}

detect_mac80211() {

	#Network Environment Variables
	BARCODE="12345678"
	PUBLAN_SSID="ShareFi"
	PRIVLAN_SSID="ShareFiSecure"
	PRIV5LAN_SSID="ShareFiSecure5G"
	WWAN_SSID="2WIRE230"
	WWAN_KEY="w1r3l3ss"
	RADIUS_SERVER="104.236.29.125"
	RADIUS_SECRET="asdf1234"
	RADIUS_NASID="1234"

	devidx=0
	config_load wireless
	while :; do
		config_get type "radio$devidx" type
		[ -n "$type" ] || break
		devidx=$(($devidx + 1))
	done

	for _dev in /sys/class/ieee80211/*; do
		[ -e "$_dev" ] || continue

		dev="${_dev##*/}"

		found=0
		config_foreach check_mac80211_device wifi-device
		[ "$found" -gt 0 ] && continue

		mode_band="g"
		channel="11"
		htmode=""
		ht_capab=""

		iw phy "$dev" info | grep -q 'Capabilities:' && htmode=HT20
		iw phy "$dev" info | grep -q '2412 MHz' || { mode_band="a"; channel="36"; }

		vht_cap=$(iw phy "$dev" info | grep -c 'VHT Capabilities')
		[ "$vht_cap" -gt 0 ] && {
			mode_band="a";
			channel="36"
			htmode="VHT80"
		}

		[ -n $htmode ] && append ht_capab "option htmode '$htmode'" "$N"

		if [ -x /usr/bin/readlink -a -h /sys/class/ieee80211/${dev} ]; then
			path="$(readlink -f /sys/class/ieee80211/${dev}/device)"
		else
			path=""
		fi
		if [ -n "$path" ]; then
			path="${path##/sys/devices/}"
			dev_id="option path	'$path'"
		else
			dev_id="option macaddr '$(cat /sys/class/ieee80211/${dev}/macaddress)'"
		fi

		if [ $channel -eq 36 ]; then
			cat <<EOF
config wifi-device  'radio$devidx'
	option type     'mac80211'
	option channel  '${channel}'
	option hwmode	'11${mode_band}'
	$dev_id
	$ht_capab
	option txpower '30'
	option country 'US'

config wifi-iface
	option device 'radio$devidx'
	option network	'priv5lan'
	option mode 'ap'
	option ssid '$PRIV5LAN_SSID$BARCODE'
	option encryption 'wpa2'
	option auth_server '$RADIUS_SERVER'
	option auth_port '1812'
	option auth_secret '$RADIUS_SECRET'
	option acct_server '$RADIUS_SERVER'
	option acct_port '1813'
	option acct_secret '$RADIUS_SECRET'
	option nasid '$RADIUS_NASID'
	option retry_interval '10'

EOF
	elif [ $channel -eq 11 ]; then
		cat <<EOF
config wifi-device  'radio$devidx'
	option type     'mac80211'
	option channel  '${channel}'
	option hwmode	'11${mode_band}'
	$dev_id
	$ht_capab
	option txpower '30'
	option country 'US'

config wifi-iface
	option device 'radio$devidx'
	option network	'wwan'
	option mode 'sta'
	option ssid '$WWAN_SSID'
	option encryption 'psk-mixed'
	option key '$WWAN_KEY'

config wifi-iface
	option device 'radio$devidx'
	option network	'publan'
	option mode 'ap'
	option ssid '$PUBLAN_SSID'
	option encryption 'none'

config wifi-iface
	option device 'radio$devidx'
	option network	'privlan'
	option mode 'ap'
	option ssid '$PRIVLAN_SSID$BARCODE'
	option encryption 'wpa2'
	option auth_server '$RADIUS_SERVER'
	option auth_port '1812'
	option auth_secret '$RADIUS_SECRET'
	option acct_server '$RADIUS_SERVER'
	option acct_port '1813'
	option acct_secret '$RADIUS_SECRET'
	option nasid '$RADIUS_NASID'
	option retry_interval '10'

EOF
	fi

	devidx=$(($devidx + 1))
	done
}

