#!/bin/sh

function del_bcache {
	bcache_name=$1;
	echo 1 >/sys/block/$bcache_name/bcache/detach;
	sleep 5;
	echo 1 >/sys/block/$bcache_name/bcache/stop;
}

function clean_disk {
	disk_path=$1;
	bcache_name=`lsblk $disk_path 2>/dev/null |grep -Eo 'bcache[0-9]+'`;
	if [ "$bcache_name" != "" ];then
		del_bcache "$bcache_name";
	fi
	disk=`echo $disk_path |awk -F/ '{print $3}'`;
	if [ "$disk" = "" ];then
		echo "can't get the disk";
		return 2;
	fi
	if [ -e "/sys/block/$disk/bcache/" ];then
		echo 1 >/sys/block/$disk/bcache/detach;
		sleep 5;
		echo 1 >/sys/block/$disk/bcache/stop;
	fi
	fuser -k $disk_path;
	umount $disk_path;
	#if ! mkfs.ext4 -F $disk_path;then
	#	return 2;
	#fi
	dd if=/dev/zero of=$disk_path oflag=direct bs=1M count=10;
	wipefs -a $disk_path;
}

dev_disks=$1;
called_by_others=$2;
if [ "$called_by_others" != "yes" ];then
	if ! . ./verify.sh "confirm_exec_script" "Are you sure you want to clean these disks $dev_disks";then
		echo "cancel exec script";
		exit -1;
	fi
fi
if [ "$dev_disks" = "" ];then
	echo "please input disk,eg: ./clean_disks /dev/sde";
	exit -1;
fi

dev_disks=`echo $dev_disks |sed 's/,/ /g'`;

for dev_disk in $dev_disks
do
	clean_disk "$dev_disk";
	if [ "$?" = "2" ];then
		echo "clean $dev_disk failed";
	else
		echo "clean $dev_disk success";
	fi
done
