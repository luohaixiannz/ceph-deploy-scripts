#!/bin/sh
function clean_osd_and_releated {
	osd_name=$1;
	osd_id=`echo $osd_name |awk -F '.' '{print $2}'`;
	if [ "$osd_id" = "" ];then
		echo "$osd_name is not a illegal osd name";
		return 2;
	fi
	
	process_name="ceph-osd.$osd_id";
	start_cmd="/etc/init.d/ceph start osd.$osd_id";
	stop_cmd="/etc/init.d/ceph stop osd.$osd_id";
	. ./delete_process_monitor.sh "$process_name" "$start_cmd" "$stop_cmd";
	if [ "$?" = "2" ];then
		return 2;
	fi

	service ceph stop $osd_name;
	ceph osd out $osd_name;
	sleep 10;
	ceph osd crush remove $osd_name;
	ceph osd rm $osd_name;
	ceph auth del $osd_name;
	ceph osd tree;
	
	osd_dir_path="/var/lib/ceph/osd/ceph-$osd_id";
	bcache_name=`mount |grep $osd_dir_path |grep -Eo 'bcache[0-9]+'`;
	bcache_slaves=`ls -l /sys/block/$bcache_name/slaves/ |grep -E 'sd|vd|hd' | awk '{print $9}'`;
	bcache_slaves=`echo $bcache_slaves |sed 's/\n/ /g'`;
	
	fuser -k $osd_dir_path;
	umount $osd_dir_path;
	osd_uuid=`ls -l /dev/disk/by-uuid/ 2>/dev/null |grep $bcache_slaves |awk -F " " '{print $9}'`;
	sed -i "/ceph-$osd_id/d" /etc/ceph/fstab;
	
	if [ "$bcache_name" != "" ] && [ -d "/sys/block/$bcache_name" ];then
		echo "enter clean bcache";
		echo 1 >/sys/block/$bcache_name/bcache/detach;
		sleep 5;
		echo 1 >/sys/block/$bcache_name/bcache/stop;
 
		try_count=0;
		while((try_count < 300)) #wait for 300 times until bcache device is stop
		do
			echo "wait bcache $bcache_name stop:$try_count";
			if [ ! -f "/sys/block/$bcache_name" ];then
				break;
			fi
        		try_count++;
			sleep 2;
		done
	fi

	if [ "$bcache_slaves" != "" ] && [ -f "/dev/$bcache_slaves" ];then
		echo 1 >/sys/block/$bcache_slaves/bcache/stop;
		dd if=/dev/zero of=/dev/$bcache_slaves bs=1M count=1 oflag=direct;	
	fi

	rm -rf $osd_dir_path;
	osd_journal="/var/lib/ceph/journal/journal-$osd_id";
	rm -rf $osd_journal;
	return 0;
}

osd_names=$1;
called_by_others=$2;
if [ "$called_by_others" != "yes" ];then
	if ! . ./verify.sh "confirm_exec_script" "Are you sure you want to clean these osds $osd_names";then
		echo "cancel exec script";
		exit -1;
	fi
fi
if ! . ./verify.sh "verify_ceph_cluster";then
	echo "this node not in the ceph cluster or the ceph cluster is abnornal";
	exit -1;
fi
if [ "$osd_names" = "" ];then
	echo "please input the osd name,eg:./clean_osd_and_releated osd.0";
	exit -1;
fi
if ! . ./verify.sh "check_osd_belong_local" "$osd_names";then
	exit -1;
fi
/etc/init.d/monit stop;
ceph osd set nobackfill
ceph osd set norebalance
ceph osd set norecover
osd_names=`echo $osd_names |sed 's/,/ /g'`;
for osd_name in $osd_names
do
	echo "start to clean $osd_name";
	clean_osd_and_releated $osd_name;
	if [ "$?" = "2" ];then
		echo "clean $osd_name failed";
	else
		echo "clean $osd_name success";
		perl perl_request.pm del_osd_info_from_esan_info $osd_name;
	fi
done
ceph osd unset nobackfill
ceph osd unset norebalance
ceph osd unset norecover
/etc/init.d/ceph start osd;
/etc/init.d/monit restart;
. ./update_pool_pg_num.sh;
