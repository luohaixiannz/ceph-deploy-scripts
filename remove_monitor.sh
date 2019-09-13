#!/bin/sh
called_by_others=$1;
if [ "$called_by_others" != "yes" ];then
        if ! . ./verify.sh "confirm_exec_script" "Are you sure you want to remove the monitor";then
                echo "cancel exec script";
                exit -1; 
        fi  
fi
if ! . ./verify.sh "verify_ceph_cluster";then
        echo "this node not in the ceph cluster or the ceph cluster is abnornal";
        exit -1; 
fi
if ! . ./verify.sh "check_mon_is_exist" "exist";then
        echo "this node not exist mon, no need to remove monitor";
	if [ "$called_by_others" != "yes" ];then
        	exit -1;
	else
		return;
	fi
fi
/etc/init.d/monit stop;
localhost=`hostname`;
echo $localhost;
ceph mon remove $localhost;
/etc/init.d/ceph -a stop mon.$localhost;
pkill -9 ceph-mon;
rm -rf /var/lib/ceph/mon/ceph-$localhost;
process_name="$ceph-mon.$localhost";
start_cmd="/etc/init.d/ceph start mon.$local_host";
stop_cmd="/etc/init.d/ceph stop mon.$local_host";
. ./delete_process_monitor.sh "$process_name" "$start_cmd" "$stop_cmd";
. ./update_moninfo_to_conf.sh "yes";
perl perl_request.pm update_mon_to_storage; 
perl update_esan_info.pm; 
