#!/bin/sh
hosts_and_osds_info=$1;
called_by_others=$2;
if [ "$called_by_others" != "yes" ];then
        if ! . ./verify.sh "confirm_exec_script" "Are you sure you want to remove some info about $hosts_and_osds_info";then
                echo "cancel exec script";
                exit -1; 
        fi  
fi
if ! . ./verify.sh "verify_ceph_cluster";then
        echo "this node not in the ceph cluster or the ceph cluster is abnornal";
        exit -1; 
fi
if [ "$hosts_and_osds_info" = "" ];then
	echo "please input nodes or osds info, eg:./clean_ceph_osd_tree node1:osd.1";
	exit -1;
fi

hosts=`echo $hosts_and_osds_info |awk -F: '{print $1}'`;
osds=`echo $hosts_and_osds_info |awk -F: '{print $2}'`;
hosts=`echo $hosts |sed 's/,/ /g'`;
osds=`echo $osds |sed 's/,/ /g'`;

for osd in $osds
do
	ceph osd out $osd;
	ceph osd crush remove $osd;
	ceph osd rm $osd;
	ceph auth del $osd;
done

for host in $hosts
do
	ceph osd crush remove $host;
done
echo "finish clean ceph osd tree";
