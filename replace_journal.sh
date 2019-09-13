#!/bin/sh
osd_names=$1;
called_by_others=$2;
if [ "$called_by_others" != "yes" ];then
        if ! . ./verify.sh "confirm_exec_script" "Are you sure you want to replace journal for $osd_names";then
                echo "cancel exec script";
                exit -1;
        fi
fi
if ! . ./verify.sh "verify_ceph_cluster";then
        echo "this node not in the ceph cluster or the ceph cluster is abnornal";
        exit -1;
fi
if ! . ./verify.sh "verify_journal_lv";then
        echo "journal lv is Unavailable, maybe you can use rebuild_journal to solve this problem";
        exit -1;
fi
if [ "$osd_names" = "" ];then
        echo "please input the osd names,eg:./replace_journal osd.5";
        exit -1;
fi
if ! . ./verify.sh "check_osd_belong_local" "$osd_names";then
        exit -1;
fi

osd_names=`echo $osd_names |sed 's/,/ /'`;
osdids=`echo $osd_names |awk -F '.' '{print $2}'`;
echo $osdids;
/etc/init.d/monit stop;
ceph osd set noout;
for osdid in $osdids
do
	/etc/init.d/ceph stop osd.$osdid;
	ceph-osd -i $osdid --flush-journal;
	
	echo "start to allocate journal for $osdid";
	if . ./change_journal_bcache.sh "config_file_journal_for_osd" "$osdid";then
		echo "allocate journal for $osdid success";
	else
		echo "failed to allocate journal for $osdid";
	fi
	/etc/init.d/ceph start osd.$osdid
done
ceph osd unset noout;
/etc/init.d/monit start;
