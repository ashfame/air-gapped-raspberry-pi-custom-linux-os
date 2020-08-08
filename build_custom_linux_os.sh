#!/usr/bin/env bash

# Set current working directory as that of the script
cd "$(dirname "$0")"

# Function to pause the script in between so that user can confirm or read values from screen & enter them as input
pause() {
	local arg=""

	if [ -z "$1" ]; then
		arg=""
	else
		arg=$1
	fi

	read -s -n 1 -p "$arg"
}

# Function to clean up and leave the state of the directory exactly how it was before script ran
cleanup() {
	linebreak
	pause "Going to cleanup. Press any key to continue.."

	# Delete picore directory
	[ -d picore ] && rm -r picore
}

# statuscode() {
# 	if [ $1 -e 0 ]; then
# 		printf "\nSuccess!!\n"
# 	else
# 		printf "\nError!!\n"
# 	fi
# }

linebreak() {
	printf "\n\n"
}

# Lets create a folder in which we will download stuff
if [ ! -d picore ]; then
	mkdir picore
fi
cd picore

# Download picore archive, extract & verify md5sum
# Reuse zip file its already downloaded
[ -f piCore-11.0.zip ] && echo "Reusing already downloaded piCore-11.0.zip file" || wget http://tinycorelinux.net/11.x/armv7/releases/RPi/piCore-11.0.zip
unzip -o piCore-11.0.zip # overwrite existing files during unzip
printf "MD5 verification of IMG file:"
md5sum -c piCore-11.0.img.md5.txt

####################################################
# Expand second partition to accomodate extensions #
####################################################
linebreak
pause "Going to expand second partition. Press any key to continue.."
# create destination image about 350MB (will trim once the build finishes based on how much space it occupies)
dd if=/dev/zero of=1.img bs=1K count=$((350*1024))
# loop mount the file as a device
devicePath=`losetup --show --find --partscan 1.img`
# copy original image over it
dd if=piCore-11.0.img of=$devicePath
# this is how it looks now
fdisk -l $devicePath
# expand partition 2 to the end of the file:
sudo parted -s $devicePath resizepart 2 100%
# this needs to be done before expanding the filesystem to inform the kernel the MBR changed:
e2fsck -f "${devicePath}p2"
# finally, we expand the filesystem:
resize2fs -p "${devicePath}p2"
# this is how it looks
fdisk -l 1.img
# release loop device
losetup -d $devicePath
# replace the img file we working with
rm piCore-11.0.img && mv 1.img piCore-11.0.img

# Get block start for specifying in the mount commands
linebreak
fdisk -l piCore-11.0.img
printf "\nEnter block start value of 1st partition: "
read blockstart1
printf "Enter block start value of 2nd partition: "
read blockstart2

# Create mounting points
printf "\nCreating mounting points..\n"
if [ ! -d mountpoint1 ]; then
	mkdir mountpoint1
fi
if [ ! -d mountpoint2 ]; then
	mkdir mountpoint2
fi

# Mount first partition
printf "Mounting 1st partition\n"
mount -o loop,offset=$((512*blockstart1)) piCore-11.0.img mountpoint1
test $? -eq 0 || ( echo "Error mounting 1st partition!!" && exit 1 )

# Modify bootcodes
# Simply copy contents, concatentate string (additional bootcodes) and overwrite the file
bootcodes=`cat mountpoint1/cmdline.txt`
bootcodes3=`cat mountpoint1/cmdline3.txt`
# Add norestore,noswap bootcode
addbootcodes="norestore noswap nozswap nodhcp waitusb=5 fbcon=map:10 fbcon=font:ProFont6x11 logo.nologo"
bootcodes="${bootcodes} ${addbootcodes}"
bootcodes3="${bootcodes3} ${addbootcodes}"
echo $bootcodes > mountpoint1/cmdline.txt
echo $bootcodes3 > mountpoint1/cmdline3.txt
printf "Bootcodes:\n"
printf "cmdline.txt:\n"
cat mountpoint1/cmdline.txt
printf "cmdline3.txt:\n"
cat mountpoint1/cmdline3.txt

# Download overlay
wget https://github.com/goodtft/LCD-show/raw/master/usr/tft35a-overlay.dtb
cp mountpoint1/overlays/tft35a-overlay.dtb mountpoint1/overlays/tft35a.dtbo

# Change config.txt
echo "" >> mountpoint1/config.txt # ensure new line
echo "# For enabling camera to work" >> mountpoint1/config.txt
echo "start_x=1" >> mountpoint1/config.txt
echo "# For enabling touchscreen" >> mountpoint1/config.txt
echo "hdmi_force_hotplug=1" >> mountpoint1/config.txt
echo "dtparam=i2c_arm=on" >> mountpoint1/config.txt
echo "dtoverlay=tft35a:rotate=90" >> mountpoint1/config.txt

linebreak
pause "Press any key to continue.."

# Unmount first partition
umount mountpoint1

# Mount second partition
linebreak
printf "Mounting 2nd partition\n"
mount -o loop,offset=$((512*blockstart2)) piCore-11.0.img mountpoint2
test $? -eq 0 || ( echo "Error mounting 2nd partition!!" && exit 1 )

pause "Press any key to continue.."

# Create copy2fs.flg file under tce directory
touch mountpoint2/tce/copy2fs.flg

# Remove mydata.tgz since we won't be restoring any persistent data
rm mountpoint2/tce/mydata.tgz

# Copy Extensions fetching script(s) under tce/optional for fetching packages
# If its missing, throw error message and halt script
cd ..
[ -f fetchExt.sh ] && cp fetchExt.sh picore/mountpoint2/tce/optional || ( echo "fetchExt.sh is missing" && exit 1 )
cd picore

#######################
# Download extensions #
#######################
printf "\nReady to fetch extensions. "
pause "Press any key to continue.."
linebreak
cd mountpoint2/tce/optional
rm *tcz* # remove all existing extensions, we will explicitly specify what we are going to need
chmod +x fetchExt.sh
./fetchExt.sh flwm_topside
./fetchExt.sh Xorg
./fetchExt.sh wbar
./fetchExt.sh v4l2-utils
./fetchExt.sh aterm
./fetchExt.sh firefox
pause "Extensions downloaded. Review Log.txt if you wish. Afterwards press any key to continue.."
linebreak

# Clean fetchExt.sh files
rm -f Log.txt Extension.list fetchExt.sh

cd ../../../../

#########################
# Add custom extensions #
#########################
# Add vaultapp extension
wget https://woodpckr.com/vaultapp.tcz
chown 1001:50 vaultapp.tcz
cp vaultapp.tcz picore/mountpoint2/tce/optional/
# Add OS customizations extension
mksquashfs includes airgap.tcz
chown 1001:50 airgap.tcz
cp airgap.tcz picore/mountpoint2/tce/optional/

# Add extensions to onboot.lst for auto-loading
cd picore
# But first clear existing entries in it
echo "Xorg.tcz" > mountpoint2/tce/onboot.lst # overwrite, not append, effectively clearing the file before writing to it
echo "flwm_topside.tcz" >> mountpoint2/tce/onboot.lst
echo "wbar.tcz" >> mountpoint2/tce/onboot.lst
echo "vaultapp.tcz" >> mountpoint2/tce/onboot.lst
echo "v4l2-utils.tcz" >> mountpoint2/tce/onboot.lst
echo "aterm.tcz" >> mountpoint2/tce/onboot.lst
echo "firefox.tcz" >> mountpoint2/tce/onboot.lst
echo "airgap.tcz" >> mountpoint2/tce/onboot.lst

# Unmount second partition
umount mountpoint2

# Copy out the modified IMG file
mv piCore-11.0.img ../airgap.img
cd ..

# Cleanup before exit
cleanup

linebreak
printf "All done!!\n"

# Clean exit
exit 0