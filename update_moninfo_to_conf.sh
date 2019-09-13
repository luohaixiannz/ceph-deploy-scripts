#!/bin/sh
called_by_others=$1;
if [ "$called_by_others" != "yes" ];then
        if ! . ./verify.sh "confirm_exec_script" "Are you sure you want to update mon info to the ceph.conf";then
                echo "cancel exec script";
                exit -1; 
        fi  
fi
if ! . ./verify.sh "verify_ceph_cluster";then
        echo "this node not in the ceph cluster or the ceph cluster is abnornal";
        exit -1; 
fi

conf_path="/etc/ceph/ceph.conf";
mon_stat=`ceph mon stat 2>/dev/null |awk -F{ '{print $2}' |awk -F} '{print $1}' |sed 's/,/ /g'`;
if [ "$mon_stat" = "" ];then
	echo "can't get mon stat";
	exit -1;
fi
new_mon_initial_members="";
new_mon_host="";
for mon in $mon_stat
do
	node_to_ip=`echo $mon |awk -F: '{print $1}'`;
	node=`echo $node_to_ip |awk -F= '{print $1}'`;
	ip=`echo $node_to_ip |awk -F= '{print $2}'`;

	if [ "$new_mon_initial_members" = "" ];then
		new_mon_initial_members="$node";
	else
		new_mon_initial_members="$new_mon_initial_members,$node";
	fi

	if [ "$new_mon_host" = "" ];then
		new_mon_host="$ip";
	else
		new_mon_host="$new_mon_host,$ip";
	fi
done
if [ "$new_mon_initial_members" = "" ] || [ "$new_mon_host" = "" ];then
	echo "new_mon_initial_members or new_mon_host is null";
	exit -1;
fi
sed -i "s/mon initial members.*/mon initial members = $new_mon_initial_members/" $conf_path;
sed -i "s/mon host.*/mon host = $new_mon_host/" $conf_path;
echo "update mon info to the ceph.conf success"
