#!/bin/sh
journal_path="/dev/ceph/journal";
journal_mount="/var/lib/ceph/journal";
function config_filebase_journal_on_lv {
	lvcreate -l 95%VG -n journal ceph;
	sleep 2;
	if ! mkfs.xfs -f $journal_path;then
		return 2;	
	fi
	mkdir -p $journal_mount;
	if ! mount -o noatime,nobarrier,inode64 $journal_path $journal_mount;then
		return 2;
	fi
	journal_fs_uuid=`blkid $journal_path |awk -F'"' '{print $2}'`;
	echo UUID=$journal_fs_uuid	 $journal_mount	 xfs  noatime,nobarrier,inode64   0 0 >> /etc/ceph/fstab;
}

function grow_journal_fs {
	if lvextend -l +95%FREE $journal_path && xfs_growfs $journal_mount;then
		return 0;
	fi
	return 2;
}

function config_journal_volume_group {
	dev_path=$1;
	ceph_vg_exist=`vgs ceph 2>/dev/null`;
	if [ "$ceph_vg_exist" = "" ];then
		rm -rf /dev/ceph;
		if pvcreate -f $dev_path && vgcreate ceph $dev_path;then
			config_filebase_journal_on_lv;
			if [ "$?" = "2" ];then
				return 2;
			fi
		else
			return 2;
		fi
	else
		if vgextend ceph $dev_path;then
			grow_journal_fs;
			if [ "$?" = "2" ];then
				return 2;
			fi
		else
			return 2;
		fi
	fi
	return 0;
}
journal_devs=$1;
called_by_others=$2;
tmp_called_by_others=$called_by_others;
if [ "$called_by_others" != "yes" ];then
        if ! . ./verify.sh "confirm_exec_script" "Are you sure you want to use $journal_devs to add journal size";then
                echo "cancel exec script";
                exit -1; 
        fi  
fi

if ! . ./verify.sh "verify_ceph_cluster";then
        echo "this node not in the ceph cluster or the ceph cluster is abnornal";
        exit -1; 
fi

if [ "$journal_devs" = "" ];then
        echo "please input the journal dev path,eg:./only_add_journal_size /dev/sde";
        exit -1; 
fi

if ! . ./verify.sh "check_ssd_devs" "$journal_devs";then
        exit -1; 
fi

. ./clean_disks.sh $journal_devs "yes";
journal_devs=`echo $journal_devs |sed 's/,/ /g'`;
for dev in $journal_devs
do
        echo "start to add $dev to journal";
        config_journal_volume_group $dev;
        if [ "$?" = "2" ];then
                echo "add $dev to journal failed";
        else
                echo "add $dev to journal success";
        fi  
done
if [ "$tmp_called_by_others" != "yes" ];then
	perl update_esan_info.pm;
fi
