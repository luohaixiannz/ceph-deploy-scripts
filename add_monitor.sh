#!/bin/sh
called_by_others=$1;
if [ "$called_by_others" != "yes" ];then
        if ! . ./verify.sh "confirm_exec_script" "Are you sure you want to add the monitor";then
                echo "cancel exec script";
                exit -1; 
        fi  
fi
if ! . ./verify.sh "verify_ceph_cluster";then
        echo "this node not in the ceph cluster or the ceph cluster is abnornal";
        exit -1; 
fi
if ! . ./verify.sh "check_mon_is_exist" "not exist";then
        echo "this node exist mon, no need to add monitor";
        exit -1; 
fi
public_network_ip=`cat /etc/ceph/ceph.conf |grep 'public network' |awk -F= '{print $2}' |awk -F/ '{print $1}'`;
if [ "$public_network_ip" = "" ];then
	echo "please add 'public network' to ceph.conf";
        exit -1; 
fi
local_host=`hostname`;
mon_stat=`ceph mon stat`;
is_exist=`echo $mon_stat |grep 'mon host' |grep $public_network_ip`;
if [ "$is_exist" != "" ];then
	echo "there is a mon in this host";
	exit -1;
fi
pkill ceph-mon;
rm -rf /var/lib/ceph/mon/ceph-$local_host;
mkdir -p /var/lib/ceph/mon/ceph-$local_host;
ceph auth get mon. -o /etc/ceph/ceph.mon.keyring;
ceph mon getmap -o /etc/ceph/monmap;
ceph-mon -i $local_host --mkfs --monmap /etc/ceph/monmap --keyring /etc/ceph/ceph.mon.keyring;
touch /var/lib/ceph/mon/ceph-$local_host/done;
touch /var/lib/ceph/mon/ceph-$local_host/sysvinit;

ceph-mon -i $local_host --public-addr $public_network_ip;
fuser -k /var/lib/ceph/mon/ceph-$local_host/store.db/LOCK;
/etc/init.d/ceph start mon.$local_host;
ceph -s;

process_name="ceph-mon.$local_host";
pidfile="/var/run/ceph/mon.$local_host.pid";
start_cmd="/etc/init.d/ceph start mon.$local_host";
stop_cmd="/etc/init.d/ceph stop mon.$local_host";
. ./add_process_monitor.sh "$process_name" "$pidfile" "$start_cmd" "$stop_cmd";
. ./update_moninfo_to_conf.sh "yes";
/etc/init.d/monit restart;
perl perl_request.pm update_mon_to_storage;
perl update_esan_info.pm;
