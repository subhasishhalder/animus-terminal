#
# Copyright (C) 2013-2015 The Android-x86 Open Source Project
#
# License: GNU Public License v2 or later
#

function set_property()
{
	setprop "$1" "$2"
	[ -n "$DEBUG" ] && echo "$1"="$2" >> /dev/x86.prop
}

function set_prop_if_empty()
{
	[ -z "$(getprop $1)" ] && set_property "$1" "$2"
}


function init_misc()
{
	# device information
	setprop ro.product.manufacturer "$(cat $DMIPATH/sys_vendor)"
	setprop ro.product.model "$PRODUCT"

	# a hack for USB modem
	lsusb | grep 1a8d:1000 && eject

	# in case no cpu governor driver autoloads
	[ -d /sys/devices/system/cpu/cpu0/cpufreq ] || modprobe acpi-cpufreq
}

function init_hal_audio()
{
	case "$PRODUCT" in
		VirtualBox*|Bochs*)
			[ -d /proc/asound/card0 ] || modprobe snd-sb16 isapnp=0 irq=5
			;;
		*)
			;;
	esac

	if grep -qi "IntelHDMI" /proc/asound/card0/id; then
		[ -d /proc/asound/card1 ] || set_property ro.hardware.audio.primary hdmi
	fi
}

function init_hal_wifi()
{
# BCM WiFi driver conflict start.
#	Broadcom BCM4311 (PCI IDs 14e4:4311, 14e4:4312)
#	Broadcom BCM4312 (PCI ID 14e4:4315)
#	Broadcom BCM4313 (PCI ID 14e4:4727)
#	Broadcom BCM4321 (PCI IDs 14e4:4328, 14e4:4329, 14e4:432a)
#	Broadcom BCM4322 (PCI IDs 14e4:432b, 14e4:432c, 14e4:432d)
#	Broadcom BCM43224 (PCI IDs 14e4:0576, 14e4:4353)
#	Broadcom BCM43225 (PCI ID 14e4:4357)
#	Broadcom BCM43227 (PCI ID 14e4:4358)
#	Broadcom BCM43228 (PCI ID 14e4:4359)
#	Broadcom BCM43142 (PCI ID 14e4:4365)
#	Broadcom BCM4331 (PCI ID 14e4:4331)
#	Broadcom BCM4352 (PCI ID 14e4:43b1)
#	Broadcom BCM4360 (PCI IDs 14e4:43a0, 14e4:4360)

BCMAID=`lspci | grep "14e4" | awk '{print $4}'`

case "${BCMAID##*:}" in
	4311 | 4312 | \
		4315 | \
		4727 | \
		4328 | 4329 | 432a | \
		432b | 432c | 432d | \
		0576 | 4353 | \
		4357 | 4358 | 4359 | \
		4365 | \
		4331 | \
		43b1 | \
		43a0 | 4360 )

		rmmod b43
		rmmod b44
		rmmod b43legacy
		rmmod ssb
		rmmod bcma
		rmmod brcm80211
		rmmod wl

		modprobe wl
		;;
	*)
		;;
esac
# BCM WiFi driver conflict end.

# BCM SDIO WiFi driver config file start.
BCMSDIO=`dmesg | grep brcmfmac | grep txt`
if [ "$BCMSDIO" != "" ]; then 
    BCMNAME=`echo $BCMSDIO | awk '{print $9}'`
    mount -t efivarfs none /sys/firmware/efi/efivars
    cp /sys/firmware/efi/efivars/nvram-74b00bd9-805a-4d61-b51f-43268123d113 /lib/firmware/$BCMNAME
    set_property phoenixos.brcmfmac 1
fi
# BCM SDIO WiFi driver config file end.
}

function init_hal_bluetooth()
{
	for r in /sys/class/rfkill/*; do
		type=$(cat $r/type)
		[ "$type" = "wlan" -o "$type" = "bluetooth" ] && echo 1 > $r/state
	done

	case "$PRODUCT" in
		T10*TA|HP*Omni*)
			BTUART_PORT=/dev/ttyS1
			set_property hal.bluetooth.uart.proto bcm
			;;
		MacBookPro8*)
			rmmod b43
			modprobe b43 btcoex=0
			modprobe btusb
			;;
		*)
			for bt in $(busybox lsusb -v | awk ' /Class:.E0/ { print $9 } '); do
				chown 1002.1002 $bt && chmod 660 $bt
			done
			;;
	esac

	if [ -n "$BTUART_PORT" ]; then
		set_property hal.bluetooth.uart $BTUART_PORT
		chown bluetooth.bluetooth $BTUART_PORT
		start btattach
	fi

	# rtl8723bs bluetooth
	if dmesg -t | grep -qE '8723bs.*BT'; then
		TTYSTRING=`dmesg -t | grep -E 'tty.*MMIO' | awk '{print $2}' | head -1`
		if [ -n "$TTYSTRING" ]; then
			echo "RTL8723BS BT uses $TTYSTRING for Bluetooth."
			ln -sf $TTYSTRING /dev/rtk_h5
			start rtk_hciattach
		fi
	fi
}

function init_hal_camera()
{
	return
}

function init_hal_gps()
{
	# TODO
	return
}

function set_drm_mode()
{
	case "$PRODUCT" in
		ET1602*)
			drm_mode=1366x768
			;;
		VMware*)
			[ -n "$video" ] && drm_mode=$video
			;;
		*)
			;;
	esac

	[ -n "$drm_mode" ] && set_property debug.drm.mode.force $drm_mode
}

function init_uvesafb()
{
	case "$PRODUCT" in
		ET2002*)
			UVESA_MODE=${UVESA_MODE:-1600x900}
			;;
		*)
			;;
	esac

	modprobe uvesafb mode_option=${UVESA_MODE:-1024x768}-32 ${UVESA_OPTION:-mtrr=3 scroll=redraw}
}

function init_hal_gralloc()
{
	case "$(cat /proc/fb | head -1)" in
		*virtiodrmfb)
		    if [ "$HWACCEL" != "0" ]; then
				set_property ro.hardware.hwcomposer drm
				set_property ro.hardware.gralloc gbm
		    fi
		        set_prop_if_empty sleep.state none
			;;
		0*inteldrmfb|0*radeondrmfb|0*nouveaufb|0*svgadrmfb|0*amdgpudrmfb)
		    if [ "$HWACCEL" != "0" ]; then
				set_property ro.hardware.gralloc drm
				set_drm_mode
		    fi
			;;
		"")
			init_uvesafb
			;&
		0*)
			;;
	esac

	[ -n "$DEBUG" ] && set_property debug.egl.trace error
}

function init_hal_hwcomposer()
{
	# TODO
	return
}

function init_hal_lights()
{
	chown 1000.1000 /sys/class/backlight/*/brightness
}

function init_hal_power()
{
	for p in /sys/class/rtc/*; do
		echo disabled > $p/device/power/wakeup
	done

	# TODO
	case "$PRODUCT" in
		HP*Omni*|OEMB|Surface*3|T10*TA)
			set_prop_if_empty sleep.state none
			;;
		*)
			;;
	esac
}

function init_hal_sensors()
{
	# if we have sensor module for our hardware, use it
	ro_hardware=$(getprop ro.hardware)
	[ -f /system/lib/hw/sensors.${ro_hardware}.so ] && return 0

	local hal_sensors=kbd
	local has_sensors=true
	case "$(cat $DMIPATH/uevent)" in
		*Lucid-MWE*)
			set_property ro.ignore_atkbd 1
			hal_sensors=hdaps
			;;
		*ICONIA*W5*)
			hal_sensors=w500
			;;
		*S10-3t*)
			hal_sensors=s103t
			;;
		*Inagua*)
			#setkeycodes 0x62 29
			#setkeycodes 0x74 56
			set_property ro.ignore_atkbd 1
			set_property hal.sensors.kbd.type 2
			;;
		*TEGA*|*2010:svnIntel:*)
			set_property ro.ignore_atkbd 1
			set_property hal.sensors.kbd.type 1
			io_switch 0x0 0x1
			setkeycodes 0x6d 125
			;;
		*DLI*)
			set_property ro.ignore_atkbd 1
			set_property hal.sensors.kbd.type 1
			setkeycodes 0x64 1
			setkeycodes 0x65 172
			setkeycodes 0x66 120
			setkeycodes 0x67 116
			setkeycodes 0x68 114
			setkeycodes 0x69 115
			setkeycodes 0x6c 114
			setkeycodes 0x6d 115
			;;
		*tx2*)
			setkeycodes 0xb1 138
			setkeycodes 0x8a 152
			set_property hal.sensors.kbd.type 6
			set_property poweroff.doubleclick 0
			set_property qemu.hw.mainkeys 1
			;;
		*MS-N0E1*)
			set_property ro.ignore_atkbd 1
			set_property poweroff.doubleclick 0
			setkeycodes 0xa5 125
			setkeycodes 0xa7 1
			setkeycodes 0xe3 142
			;;
		*Aspire1*25*)
			modprobe lis3lv02d_i2c
			echo -n "enabled" > /sys/class/thermal/thermal_zone0/mode
			;;
		*ThinkPad*Tablet*)
			modprobe hdaps
			hal_sensors=hdaps
			;;
		*i7Stylus*|*S10T*)
			set_property hal.sensors.iio.accel.matrix 1,0,0,0,-1,0,0,0,-1
			[ -z "$(getprop sleep.state)" ] && set_property sleep.state none
			;;
		*ST70416-6*)
			set_property hal.sensors.iio.accel.matrix 0,-1,0,-1,0,0,0,0,-1
			;;
		*ONDATablet*)
			set_property hal.sensors.iio.accel.matrix 0,1,0,1,0,0,0,0,-1
			;;
		*)
			has_sensors=false
			;;
	esac

	# has iio sensor-hub?
	if [ -n "`ls /sys/bus/iio/devices/iio:device* 2> /dev/null`" ]; then
		busybox chown -R 1000.1000 /sys/bus/iio/devices/iio:device*/
		lsmod | grep -q hid_sensor_accel_3d && hal_sensors=hsb || hal_sensors=iio
	elif lsmod | grep -q lis3lv02d_i2c; then
		hal_sensors=hdaps
	fi

	# TODO close Surface Pro 4 sensor until bugfix
	case "$(cat $DMIPATH/uevent)" in
		*SurfacePro4*)
			hal_sensors=kbd
			;;
		*)
			;;
	esac

	set_property ro.hardware.sensors $hal_sensors
	[ "$hal_sensors" != "kbd" ] && has_sensors=true
	set_property config.override_forced_orient $has_sensors
}

function create_pointercal()
{
	if [ ! -e /data/misc/tscal/pointercal ]; then
		mkdir -p /data/misc/tscal
		touch /data/misc/tscal/pointercal
		chown 1000.1000 /data/misc/tscal /data/misc/tscal/*
		chmod 775 /data/misc/tscal
		chmod 664 /data/misc/tscal/pointercal
	fi
}

function init_tscal()
{
	case "$PRODUCT" in
		ST70416-6*)
			modprobe gslx680_ts_acpi
			;&
		T91|T101|ET2002|74499FU|945GSE-ITE8712|CF-19[CDYFGKLP]*)
			create_pointercal
			return
			;;
		*)
			;;
	esac

	for usbts in $(lsusb | awk '{ print $6 }'); do
		case "$usbts" in
			0596:0001|0eef:0001)
				create_pointercal
				return
				;;
			*)
				;;
		esac
	done
}

function init_ril()
{
	case "$(cat $DMIPATH/uevent)" in
		*TEGA*|*2010:svnIntel:*|*Lucid-MWE*)
			set_property rild.libpath /system/lib/libhuaweigeneric-ril.so
			set_property rild.libargs "-d /dev/ttyUSB2 -v /dev/ttyUSB1"
			set_property ro.radio.noril no
			;;
		*)
			set_property ro.radio.noril yes
			;;
	esac
}

function init_cpu_governor()
{
	governor=$(getprop cpu.governor)

	[ $governor ] && {
		for cpu in $(ls -d /sys/devices/system/cpu/cpu?); do
			echo $governor > $cpu/cpufreq/scaling_governor || return 1
		done
	}
}

function phoenixos_compat()
{
    PHOENIX_LOG=/data/system/phoenixos.log
    PHOENIX_LOG1=/data/system/phoenixos1.log
    PHOENIX_TEMP=/data/system/tmp
    PHOENIX_DISK=`cat /data/system/phoenixlog.addr`
    PHOENIX_COMPAT_BIN=/system/xbin/phoenix_compat

    if [ -f /data/system/phoenixlog.dir ]; then 
        PHOENIX_DIR=`cat /data/system/phoenixlog.dir`
    else
        PHOENIX_DIR=PhoenixOS
    fi

    if [ $1 = "cmdline" ]; then
        sed -i '5s/^.*$/boot: cmdline/' $PHOENIX_LOG
    else
        if [ $1 = "android" ]; then
            sed -i '5s/^.*$/boot: android/' $PHOENIX_LOG
        else
            sed -i '5s/^.*$/boot: phoenixos/' $PHOENIX_LOG
        fi

        $PHOENIX_COMPAT_BIN $1
        cp -f $PHOENIX_LOG1 $PHOENIX_LOG
    fi

    mount $PHOENIX_DISK $PHOENIX_TEMP
    cp -f $PHOENIX_LOG $PHOENIX_TEMP/$PHOENIX_DIR
    umount $PHOENIX_TEMP
}

function do_init()
{
    phoenixos_compat cmdline

	init_misc
	init_hal_audio
	init_hal_wifi
	init_hal_bluetooth
	init_hal_camera
	init_hal_gps
	init_hal_gralloc
	init_hal_hwcomposer
	init_hal_lights
	init_hal_power
	init_hal_sensors
	init_tscal
	init_ril
	post_init
}

function do_netconsole()
{
	modprobe netconsole netconsole="@/,@$(getprop dhcp.eth0.gateway)/"
}

function do_bootanim()
{
    phoenixos_compat android

    [ -n "$(getprop phoenixos.brcmfmac)" ] && rmmod brcmfmac && modprobe brcmfmac
}

function do_bootcomplete()
{
    phoenixos_compat phoenixos

	init_cpu_governor

	[ -z "$(getprop persist.sys.root_access)" ] && setprop persist.sys.root_access 3

	lsmod | grep -Ehq "brcmfmac|rtl8723be" && setprop wlan.no-unload-driver 1

	case "$PRODUCT" in
		1866???|1867???|1869???) # ThinkPad X41 Tablet
			start tablet-mode
			start wacom-input
			setkeycodes 0x6d 115
			setkeycodes 0x6e 114
			setkeycodes 0x69 28
			setkeycodes 0x6b 158
			setkeycodes 0x68 172
			setkeycodes 0x6c 127
			setkeycodes 0x67 217
			;;
		6363???|6364???|6366???) # ThinkPad X60 Tablet
			;&
		7762???|7763???|7767???) # ThinkPad X61 Tablet
			start tablet-mode
			start wacom-input
			setkeycodes 0x6d 115
			setkeycodes 0x6e 114
			setkeycodes 0x69 28
			setkeycodes 0x6b 158
			setkeycodes 0x68 172
			setkeycodes 0x6c 127
			setkeycodes 0x67 217
			;;
		7448???|7449???|7450???|7453???) # ThinkPad X200 Tablet
			start tablet-mode
			start wacom-input
			setkeycodes 0xe012 158
			setkeycodes 0x66 172
			setkeycodes 0x6b 127
			;;
		*)
			;;
	esac

#	[ -d /proc/asound/card0 ] || modprobe snd-dummy
	for c in $(grep '\[.*\]' /proc/asound/cards | awk '{print $1}'); do
		f=/system/etc/alsa/$(cat /proc/asound/card$c/id).state
		if [ -e $f ]; then
			alsa_ctl -f $f restore $c
			alsa_amixer -c $c set Speaker 65%
		else
			alsa_ctl init $c
			alsa_amixer -c $c set Master on
			alsa_amixer -c $c set Master 100%
			alsa_amixer -c $c set Headphone on
			alsa_amixer -c $c set Headphone 100%
			alsa_amixer -c $c set Speaker 100%
			alsa_amixer -c $c set Capture 100%
			alsa_amixer -c $c set Capture cap
			alsa_amixer -c $c set PCM 100 unmute
			alsa_amixer -c $c set SPO unmute
			alsa_amixer -c $c set 'Mic Boost' 3
			alsa_amixer -c $c set 'Internal Mic Boost' 3
          alsa_amixer sget 'Input Source'
          alsa_amixer sset 'Input Source' 'Front Mic'
          alsa_amixer sget 'Auto-Mute Mode'
          alsa_amixer sset 'Auto-Mute Mode' 'Disabled'
          alsa_amixer sget 'Front Mic boost'
          alsa_amixer sset 'Front Mic Boost' '3'

		fi
	done

	case "$(cat $DMIPATH/uevent)" in
		*S10T*)
			alsa_amixer -c 0 set Speaker 95%
			;;
		*)
			;;
	esac

	post_bootcomplete
}

PATH=/sbin:/system/bin:/system/xbin

DMIPATH=/sys/class/dmi/id
BOARD=$(cat $DMIPATH/board_name)
PRODUCT=$(cat $DMIPATH/product_name)

# import cmdline variables
for c in `cat /proc/cmdline`; do
	case $c in
		BOOT_IMAGE=*|iso-scan/*|*.*=*)
			;;
		*=*)
			eval $c
			if [ -z "$1" ]; then
				case $c in
					DEBUG=*)
						[ -n "$DEBUG" ] && set_property debug.logcat 1
						;;
				esac
			fi
			;;
	esac
done

[ -n "$DEBUG" ] && set -x || exec &> /dev/null

# import the vendor specific script
hw_sh=/vendor/etc/init.sh
[ -e $hw_sh ] && source $hw_sh

case "$1" in
	netconsole)
		[ -n "$DEBUG" ] && do_netconsole
        phoenixos_compat
		;;
	bootcomplete)
		do_bootcomplete
		;;
	bootanim)
		do_bootanim
		;;
	init|"")
		do_init
		;;
esac

return 0
