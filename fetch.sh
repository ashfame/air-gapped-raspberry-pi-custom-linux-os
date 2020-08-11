#!/bin/bash
# Script written by Ashfame (Ashish Kumar) https://ashfame.com

# Repository to download from
ADDR="http://repo.tinycorelinux.net"

# Tinycore version
TC="11.x"

# Processor architecture, current options are  x86  x86_64  armv6  armv7
ARCH="armv7"

# Kernel version to download the appropriate extensions for it. Run "uname -r" on your piCore based linux OS to see kernel version
KERNEL="4.19.81-piCore-v7"

function download {
	# ext name
	ext="$1"

	# ensure extension is non-empty
	if [[ -z $ext ]]
	then
		return
	fi

	# ensure extension has a suffix .tcz
	if [[ $ext != *.tcz ]]
	then
		echo "adding suffix to $ext"
		ext=$ext".tcz"
	fi

	# replace KERNEL placeholder in extension name, if present
	if [[ $ext == *KERNEL* ]]
	then
		ext=${ext/KERNEL/$KERNEL}
	fi

	echo "[$ext] Downloading.."

	URL="$ADDR/$TC/$ARCH/tcz/$ext"

	# bail if we already have this extension downloaded
	if [[ -f $ext ]]
	then
		echo "Already exists, going to check dependencies tree now."
	else
		# download the extension
		wget -q $URL > /dev/null 2>&1

		# @TODO: show message if we couldn't download the extension or some error happened
		if [ "$?" != "0" ]
		then
			echo "Err: Could not download $ext"
		fi

		# download md5 of extension
		wget -q $URL".md5.txt" > /dev/null 2>&1

		# verify md5sum of extension
		md5sum -c $ext".md5.txt"
		if [ "$?" != "0" ]
		then
			echo "Err: MD5 checksum failed"
		fi
	fi

	# download dependencies
	wget -q -O dep.txt "$URL.dep" 2>&1

	if [ "$?" == 0 ]
	then
		echo "Downloading dependencies.."
		cp dep.txt $ext".dep"
		for ext in `cat dep.txt`
		do
			echo "Attempting to download $ext"
			download $ext
		done
	fi
}

if [[ -z $1 ]]
then
	echo "Err: No extension name given."
	exit 1
fi

# first invocation
download $1

# set file permissions, numeric values for tc:staff used here, since these users may not exist on the host system where this script is executed
echo ""
echo "Warning:"
echo "Script will now attempt to set file permissions on the downloaded files."
echo "If you are not running this as root user or with sudo, this will fail."
echo "Simply run the following command as root user or with sudo to do it yourself:"
echo "sudo chown 1001:50 *.tcz*"
read -p "Press any key to continue.."
chown 1001:50 *.tcz*

# cleanup
rm dep.txt

# clean exit
exit 0
