#!/bin/busybox ash

#
# Minimal busybox init script for an initramfs
#
# Loosely based on the script at:
# http://jootamam.net/howto-initramfs-image.htm
#

#
# Set up initial mounts
#
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev/

#
# Install busybox symlinks
#
/bin/busybox --install -s > /dev/null 2>&1

echo "Starting init script with cmdline options: $@"

#
# Move modules to the right place
#
if [ -d /lib/modules/drivers ]; then
	mkdir /lib/modules/$(uname -r)
	mv /lib/modules/net /lib/modules/$(uname -r)/
	mv /lib/modules/drivers /lib/modules/$(uname -r)/
fi
depmod -a

#
# Function for initializing USB composite gadget
# Based on the sample configuration at:
# https://wiki.tizen.org/wiki/USB/Linux_USB_Layers/Configfs_Composite_Gadget/Usage_eq._to_g_multi.ko
#
start_usb() {
	vendor=0x1d6b
	product=0x0106
	file0=$1
	omap_dieid=$2

	echo "Starting USB gadgets..."

	#modprobe libcomposite

	mount -t configfs none /sys/kernel/config
	mkdir /sys/kernel/config/usb_gadget/g1
	old_pwd=$(pwd)
	cd /sys/kernel/config/usb_gadget/g1

	echo $product > idProduct
	echo $vendor > idVendor
	mkdir strings/0x409
	echo $omap_dieid > strings/0x409/serialnumber
	echo "Network Improv" > strings/0x409/manufacturer
	echo "Multi Gadget" > strings/0x409/product

	mkdir configs/c.1
	echo 120 > configs/c.1/MaxPower
	mkdir configs/c.1/strings/0x409
	echo "Conf 1" > configs/c.1/strings/0x409/configuration

	mkdir configs/c.2
	echo 120 > configs/c.2/MaxPower
	mkdir configs/c.2/strings/0x409
	echo "Conf 2" > configs/c.2/strings/0x409/configuration

	mkdir functions/mass_storage.0
	echo $file0 > functions/mass_storage.0/lun.0/file

	mkdir functions/acm.0
	mkdir functions/ecm.0
	#mkdir functions/rndis.0

	#ln -s functions/rndis.0 configs/c.1
	ln -s functions/acm.0 configs/c.1
	ln -s functions/mass_storage.0 configs/c.1

	ln -s functions/ecm.0 configs/c.2
	ln -s functions/acm.0 configs/c.2
	ln -s functions/mass_storage.0 configs/c.2

	echo musb-hdrc.0.auto > /sys/kernel/config/usb_gadget/g1/UDC
	cd $old_pwd
}

#
# Try not to touch the external MMC card
#
if ls /dev/mmcblk1 > /dev/null 2>&1; then
	emmc=/dev/mmcblk1
	rootfs=/dev/mmcblk1p2
else
	emmc=/dev/mmcblk0
	rootfs=/dev/mmcblk0p2
fi

#
# Signal we're in install mode with the LEDs
#
blink_leds() {
	echo 30 > /sys/class/leds/pca963x\:red/brightness
	sleep 1
	echo 0 > /sys/class/leds/pca963x\:red/brightness

	echo 30 > /sys/class/leds/pca963x\:green/brightness
	sleep 1
	echo 0 > /sys/class/leds/pca963x\:green/brightness

	sleep 1
}

if echo $@ | grep really_install > /dev/null 2>&1; then

	omap_dieid=""

	# Check the unique die ID so install knows which device to use
	for arg in $(cat /proc/cmdline); do
		if echo $arg | grep omap_dieid= > /dev/null; then
			omap_dieid=$(echo $arg | sed -e s/omap_dieid=//)
		fi
		shift
	done

	start_usb $emmc $omap_dieid

	echo "Waiting in mass storage mode to install, console at ttyACM..."
	/sbin/getty -n -l /bin/sh /dev/ttyGS0 115200 &
	while [ 1 ]; do
		blink_leds
	done
else
	echo "Loading modules..."
	modprobe cfg80211
	modprobe mwifiex
	modprobe mwifiex_sdio

	start_usb ""

	echo "Mounting $rootfs as new root..."
	mount $rootfs /mnt

	#echo "Unconfiguring USB gadgets..."
	#echo "" > /sys/kernel/config/usb_gadget/g1/UDC

	echo "Unmounting temporary file systems..."
	umount /proc
	umount /sys/kernel/config
	umount /sys
	umount /dev

	echo "Starting /sbin/init on $rootfs..."
	exec switch_root /mnt /sbin/init $@
fi
