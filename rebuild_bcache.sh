#!/bin/sh

osd_cache_devs=$1;
called_by_others=$2;
if [ "$called_by_others" != "yes" ];then
        if ! . ./verify.sh "confirm_exec_script" "Are you sure you want to use $osd_cache_devs to rebuild bcache";then
                echo "cancel exec script";
                exit -1;
        fi
fi

if ! . ./verify.sh "verify_ceph_cluster";then
        echo "this node not in the ceph cluster or the ceph cluster is abnornal";
        exit -1;
fi

if [ "$osd_cache_devs" = "" ];then
        echo "please input the osd cache dev path,eg:./rebuild_bcache /dev/sde";
        exit -1;
fi

if ! . ./verify.sh "check_osd_cache_devs" "$osd_cache_devs";then
        exit -1;
fi

if ! . ./verify.sh "check_ssd_devs" "$osd_cache_devs";then
        exit -1;
fi

osdids="";
. ./change_journal_bcache.sh "get_osdids";
echo $osdids;
/etc/init.d/monit stop;
ceph osd set noout;
/etc/init.d/ceph stop osd;
for osd_id in $osdids
do
	if ! . ./change_journal_bcache.sh "clean_osd_bcache" "$osd_id";then
		exit -1;
	fi
	sleep 5;
done

echo "start to clean old osd cache";
exist_osd_vg=`vgs osd 2>/dev/null`;
if [ "$exist_osd_vg" != "" ];then
        if ! . ./change_journal_bcache.sh "clean_osd_cache";then
                echo "clean_osd_cache failed";
		exit -1;
        fi  
fi
echo "clean old osd cache finish";

echo "start to rebuild bcache";
. ./only_add_bcache_size.sh "$osd_cache_devs" "yes";
exist_osd_vg=`vgs osd 2>/dev/null`;
if [ "$exist_osd_vg" = "" ];then
	echo "build osd cache failed";
	exit -1;	
fi
echo "finish rebuild osd cache";
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
perl update_esan_info.pm;
