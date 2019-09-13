#!/bin/sh
osd_bcache_name="";
osd_id="";
function config_bcache {
	osd_dev_path=$1;
	if [ "osd_dev_path" = "" ];then
		echo "osd_dev_path empty!";
		return 2;
	fi
	modprobe bcache;
	osd_cache_related_bcache=`ls -l /dev/osd/cache 2>/dev/null |awk -F '/' '{print $5}' |xargs -i bcache-super-show /dev/{} 2>/dev/null|grep 'cache device'`;
	if [ "$osd_cache_related_bcache" = "" ];then
		fuser -k /dev/osd/cache;
		dd if=/dev/zero of=/dev/osd/cache oflag=direct bs=1M count=1;
		wipefs -a /dev/osd/cache;
		if ! make-bcache -C /dev/osd/cache --wipe-bcache;then
			echo "make-bcache -C /dev/osd/cache error";
			return 2;
		fi
	fi
	
	fuser -k $osd_dev_path;
	local dev=`echo $osd_dev_path |awk -F '/' '{print $3}'`;
	echo 1 >/sys/block/$dev/bcache/stop;
	wipefs -a $osd_dev_path;
	if ! make-bcache -B $osd_dev_path --wipe-bcache;then
		echo "make-bcache -B $osd_dev_path error";
		return 2;
	fi
	echo $osd_dev_path > /sys/fs/bcache/register;
	
	sleep 5;
	cset_uuid=`bcache-super-show /dev/osd/cache |grep 'cset.uuid' |awk '{print $2}'`;
	osd_bcache_name=`lsblk $osd_dev_path |grep -Eo 'bcache[0-9]*'`;
	echo $cset_uuid > /sys/block/$osd_bcache_name/bcache/attach;
	echo writeback >/sys/block/$osd_bcache_name/bcache/cache_mode;
	return 0;	
}

function config_crush_rule {
	root_bucket_name=$1;host_bucket_name=$2;osd_name=$3;rule_name=$4;osd_weight=$5;choose_type=$6;
	ceph osd crush add-bucket $root_bucket_name root;
	ceph osd crush add-bucket $host_bucket_name host;
	ceph osd crush move $host_bucket_name root=$root_bucket_name;
	ceph osd crush add $osd_name $osd_weight host=$host_bucket_name;
	ceph osd crush rule create-simple $rule_name $root_bucket_name $choose_type firstn;
}

function create_osd {
	osd_dev_path=$1;
	if [ "$osd_dev_path" = "" ];then
		echo "dev:$osd_dev_path is invalid";
		return 2;
	fi
	if_mounted_osd=`lsblk $osd_dev_path 2>/dev/null |grep /ceph/osd`;
	if [ "$if_mounted_osd" != "" ];then
		echo "this device has mounted one osd";
		return 2;
	fi
	osd_id=`ceph osd create 2>/dev/null`;
	if [ "$osd_id" = "" ];then
		echo "allocate osd id fail,create osd error";
		return 2;
	fi
	echo "osd_id:$osd_id";
	osd_name="osd.$osd_id";
	osd_dir="/var/lib/ceph/osd/ceph-$osd_id";
	mkdir -p $osd_dir;
	config_bcache "$osd_dev_path";
	if [ "$?" = "2" ] || [ "$osd_bcache_name" = "" ];then
		echo "config bcache error";
		return 2;
	fi
	osd_bcache_path="/dev/$osd_bcache_name";
	if ! mkfs.xfs -f $osd_bcache_path;then
		return 2;
	fi
	if ! mount -o noatime,nobarrier,inode64 $osd_bcache_path $osd_dir;then
		return 2;
	fi
	osd_bcache_uuid=`blkid /dev/$osd_bcache_name |awk -F '"' '{print $2}'`;
	OSD_FSTAB="/etc/ceph/fstab";
	if [ ! -e $OSD_FSTAB ];then
		echo "UUID=$osd_bcache_uuid	 $osd_dir	 xfs  noatime,nobarrier,inode64   0 0" > $OSD_FSTAB;
	else
		sed -i "/ceph-$osd_id/d" $OSD_FSTAB;
		echo "UUID=$osd_bcache_uuid	$osd_dir	xfs  noatime,nobarrier,inode64   0 0" >> $OSD_FSTAB;
	fi
	
	ceph-osd -i $osd_id --osd-data $osd_dir --mkfs --mkkey;
	if ! . ./change_journal_bcache.sh "config_file_journal_for_osd" "$osd_id";then
		echo "create journal for osd $osd_id error";
		return 2;
	fi
	local_host=`hostname`;
	ceph auth add osd.$osd_id osd 'allow *' mon 'allow profile osd' -i $osd_dir/keyring;
	config_crush_rule "default" "$local_host" "$osd_name" "replicated_ruleset" "1.000" "host";
	touch $osd_dir/sysvinit;
	/etc/init.d/ceph start $osd_name;
	chkconfig ceph on;
	
	process_name="ceph-osd.$osd_id";
	pidfile="/var/run/ceph/osd.$osd_id.pid";
	start_cmd="/etc/init.d/ceph start osd.$osd_id";
	stop_cmd="/etc/init.d/ceph stop osd.$osd_id";
	. ./add_process_monitor.sh "$process_name" "$pidfile" "$start_cmd" "$stop_cmd";
	echo "create osd $osd_id successfully";
	return 0;
}

osd_devs=$1;
called_by_others=$2;
if [ "$called_by_others" != "yes" ];then
        if ! . ./verify.sh "confirm_exec_script" "Are you sure you want to add these osds $osd_devs";then
                echo "cancel exec script";
                exit -1;
        fi
fi

if ! . ./verify.sh "verify_ceph_cluster";then
        echo "this node not in the ceph cluster or the ceph cluster is abnornal";
        exit -1;
fi

if [ "$osd_devs" = "" ];then
	echo "please input the osd dev path, eg:./add_osd /dev/sde";
	exit -1;
fi

if ! . ./verify.sh "check_devs" "$osd_devs";then
	exit -1;	
fi

osd_devs=`echo $osd_devs |sed 's/,/ /g'`;
for dev in $osd_devs
do
        echo "start to use $dev to create osd";
        create_osd $dev;
        if [ "$?" = "2" ];then
                echo "use $dev to create osd failed";
		. ./clean_osd_and_releated.sh "osd.$osd_id", "yes";
        else
                echo "use $dev to create osd success";
        fi  
done
/etc/init.d/monit restart;
/etc/init.d/ceph start osd;
. ./update_pool_pg_num.sh;
perl update_esan_info.pm;
