#!/bin/sh
function confirm_exec_script {
	description=$1;
	echo "${description} (yes/no)?";
	while ((1==1))
	do
        	read ret;
        	if [ "$ret" = "yes" ];then
                	return 0;
        	elif [ "$ret" = "no" ];then
                	return 2;
        	else
                	echo "please input yes or no";
        	fi  
	done
}

function verify_ceph_cluster {
	ceph_state=`ceph -s |grep health |awk -F ' ' '{print $2}'`;
	if [ "$ceph_state" = "HEALTH_WARN" ] || [ "$ceph_state" = "HEALTH_OK" ];then
		return 0;
	else
		return 2;
	fi
}

function check_osd_belong_local {
	vfy_osdnames=$1;
	vfy_osdnames=`echo $vfy_osdnames |sed 's/,/ /g'`;
	for vfy_osdname in $vfy_osdnames
	do
		vfy_osdid=`echo $vfy_osdname |grep -Eo 'osd.[0-9]+' |awk -F '.' '{print $2}'`;
		if [ "$vfy_osdid" = "" ];then
			echo "$vfy_osdname is not an osd";
			return 2;
		fi
		vfy_local_host=`hostname`;
		vfy_osd_host=`ceph osd find $vfy_osdid 2>/dev/null |grep '"host"' |awk -F '"' '{print $4}'`;
		if [ "$vfy_local_host" != "$vfy_osd_host" ];then
			if [ ! -e "/var/lib/ceph/osd/ceph-$vfy_osdid" ];then
				echo "$vfy_osdname is not belong the local node";
				return 2;
			fi
		fi
	done
}

function check_mon_is_exist {
	expect=$1;
	local_host=`hostname`;
	result="not exist";
	if [ -e "/var/lib/ceph/mon/ceph-$local_host/done" ];then
		result="exist";
	fi
	if [ "$expect" != "$result" ];then
		echo "$expect, $result";	
		return 2;
	fi
}

function check_devs {
	vfy_devs=$1;
	vfy_devs=`echo $vfy_devs |sed 's/,/ /g'`;
	for vfy_dev in $vfy_devs
	do
		is_mounted=`mount 2>/dev/null |grep $vfy_dev`;
		is_partition=`lsblk $vfy_dev 2>/dev/null |wc -l`;
		if [ "$is_mounted" != "" ] || [ "$is_partition" != "2" ];then
			echo "this disk $dev had already mounted or has partition";
			return 2;
		fi
	done	
}

function check_is_ssd {
	vfy_dev_path=$1;
	vfy_dev=`echo $vfy_dev_path |awk -F/ '{print $3}'`;
	is_ssd=`cat /sys/block/$vfy_dev/queue/rotational 2>/dev/null`;
	if [ "$is_ssd" = "0" ];then
		return 0;
	else
		echo "$vfy_dev_path is not a ssd disk";
		return 2;
	fi
}

function check_ssd_devs {
	check_devs $1;
	if [ "$?" = "2" ];then
		return 2;
	fi
	vfy_ssd_devs=$1;
	vfy_ssd_devs=`echo $vfy_ssd_devs |sed 's/,/ /g'`;
	for ssd_dev in $vfy_ssd_devs
	do
		check_is_ssd "$ssd_dev";
		if [ "$?" = "2" ];then
			return 2;
		fi
	done
}

function check_journal_devs {
	vfy_journal_devs=$1;
	vfy_journal_devs=`echo $vfy_journal_devs |sed 's/,/ /g'`;
	for j_dev in $vfy_journal_devs
	do
		pv_type=`pvs 2>/dev/null |grep $j_dev |awk -F ' ' '{print $2}'`;
		if [ "$pv_type" != "ceph" ];then
			check_devs "$j_dev";
			if [ "$?" = "2" ];then
				return 2;
			fi
			check_is_ssd "$j_dev";
			if [ "$?" = "2" ];then
				return 2;
			fi
		fi
	done
}

function check_osd_cache_devs {
	vfy_osd_cache_devs=$1;
	vfy_osd_cache_devs=`echo $vfy_osd_cache_devs |sed 's/,/ /g'`;
	for c_dev in $vfy_osd_cache_devs
	do
		pv_type=`pvs 2>/dev/null |grep $c_dev |awk -F ' ' '{print $2}'`;
		if [ "$pv_type" != "osd" ];then
			check_devs "$c_dev";
			if [ "$?" = "2" ];then
				return 2;
			fi
			check_is_ssd "$c_dev";
			if [ "$?" = "2" ];then
				return 2;
			fi
		fi
	done
}

function verify_journal_lv {
	journal_lv=`ls /dev/ceph/journal 2>/dev/null`;
	is_journal_mounted=`mount |grep '/var/lib/ceph/journal'`;
	if [ "$journal_lv" = "" ] || [ "$is_journal_mounted" = "" ];then
		echo "journal lv is null or not mount journal";
		return 2;
	fi
}

function verify_osd_cache_lv {
	osd_cache_lv=`ls /dev/osd/cache 2>/dev/null`;
	if [ "$osd_cache_lv" = "" ];then
		echo "cache lv is null";
		return 2;
	fi
}
request=$1;
case $request in
	"confirm_exec_script")
		confirm_exec_script "$2";
		return $?;
	;;
	"verify_ceph_cluster")
		verify_ceph_cluster;
		return $?;
	;;
	"check_osd_belong_local")
		check_osd_belong_local "$2";
		return $?;
	;;
	"check_mon_is_exist")
		check_mon_is_exist "$2";
		return $?;
	;;
	"check_devs")
		check_devs "$2";
		return $?;
	;;
	"check_ssd_devs")
		check_ssd_devs "$2";
		return $?;
	;;
	"check_journal_devs")
		check_journal_devs "$2";
		return $?;
	;;
	"check_osd_cache_devs")
		check_osd_cache_devs "$2";
		return $?;
	;;
	"verify_journal_lv")
		verify_journal_lv;
		return $?;
	;;
	"verify_osd_cache_lv")
		verify_osd_cache_lv;
		return $?;
	;;
	*)
		echo "unknow request:$request";
		return 2;
	;;
esac
