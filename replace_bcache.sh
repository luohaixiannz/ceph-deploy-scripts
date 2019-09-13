#!/bin/sh
osd_names=$1;
called_by_others=$2;
if [ "$called_by_others" != "yes" ];then
        if ! . ./verify.sh "confirm_exec_script" "Are you sure you want to replace bcache for $osd_names";then
                echo "cancel exec script";
                exit -1; 
        fi  
fi
if ! . ./verify.sh "verify_ceph_cluster";then
        echo "this node not in the ceph cluster or the ceph cluster is abnornal";
        exit -1; 
fi
if ! . ./verify.sh "verify_osd_cache_lv";then
        echo "cache lv is Unavailable, maybe you can use rebuild_bcache to solve this problem";
        exit -1; 
fi
if [ "$osd_names" = "" ];then
        echo "please input the osd names,eg:./replace_bcache osd.5";
        exit -1; 
fi
if ! . ./verify.sh "check_osd_belong_local" "$osd_names";then
        exit -1; 
fi
osd_names=`echo $osd_names |sed 's/,/ /g'`;
osdids="";
for osd_name in osd_names
do
	id=`echo $osd_names |awk -F '.' '{print $2}'`;
	osdids="$osdids $id";
done
/etc/init.d/monit stop;
ceph osd set noout;
for osd_id in $osdids
do
	/etc/init.d/ceph stop osd.$osd_id;
	if ! . ./change_journal_bcache.sh "clean_osd_bcache" "$osd_id";then
		echo "clean osd.$osd_id bcache failed";
	fi	
done

for osdid in $osdids
do
        echo "osd.$osdid start to attach to osd cache";
	osd_dev_path="";
        . ./change_journal_bcache.sh "find_osd_dev_path" "osd.$osdid";
        if [ "$osd_dev_path" = "" ];then
                echo "can't find the osd.$osdid disk";
                continue;
        fi
        if ! . ./change_journal_bcache.sh "config_bcache_for_osd" "$osdid" "$osd_dev_path";then
                echo "osd.$osdid attach to osd cache failed";
        else
                echo "osd.$osdid attach to osd cache success";
        fi
done
/etc/init.d/ceph start osd
ceph osd unset noout;
/etc/init.d/monit start;
