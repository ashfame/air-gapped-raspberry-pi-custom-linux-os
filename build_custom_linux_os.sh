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
[ -f piCore-11.0.zip ] && echo "Reusing already downloaded piCore-11.0.zip file" || wget http://tinycorelinux.net/11.x/armv6/releases/RPi/piCore-11.0.zip
unzip -o piCore-11.0.zip # overwrite existing files during unzip
printf "MD5 verification of IMG file:"
md5sum -c piCore-11.0.img.md5.txt
pause "Press any key to continue.."

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
# Add norestore,noswap bootcode
bootcodes="${bootcodes} norestore noswap nozswap nodhcp"
echo $bootcodes > mountpoint1/cmdline.txt
printf "Bootcodes:\n"
cat mountpoint1/cmdline.txt

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

# Copy fetchExt.sh under tce/optional for fetching packages
# If its missing, throw error message and halt script
cd ..
[ -f fetchExt.sh ] && cp fetchExt.sh picore/mountpoint2/tce/optional || ( echo "fetchExt.sh is missing" && exit 1 )
cd picore

# Download extensions
printf "\nReady to fetch extensions. "
pause "Press any key to continue.."
linebreak
cd mountpoint2/tce/optional
rm *tcz* # remove all existing extensions, we will explicitly specify what we are going to need
chmod +x fetchExt.sh
./fetchExt.sh flwm_topside
./fetchExt.sh Xorg

pause "Extensions downloaded. Review Log.txt if you wish. Afterwards press any key to continue.."
linebreak

# Clean fetchExt.sh files
rm -f Log.txt Extension.list fetchExt.sh

# Add extensions to onboot.lst for auto-loading
cd ..
# But first clear existing entries in it
echo "Xorg.tcz" > onboot.lst # overwrite, not append, effectively clearing the file before writing to it
echo "flwm_topside.tcz" >> onboot.lst

# Unmount second partition
cd ../../
umount mountpoint2

# Check out modified IMG file
printf "MD5 verification of modified IMG file (should fail):"
md5sum -c piCore-11.0.img.md5.txt
pause "Press any key to continue.."

# Copy out the modified IMG file
cp piCore-11.0.img ../piCore-airgap-11.0.img
cd ..

# Cleanup before exit
cleanup

linebreak
printf "All done!!\n"

# Clean exit
exit 0