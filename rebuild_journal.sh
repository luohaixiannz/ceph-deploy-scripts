#!/bin/sh
journal_devs=$1;
called_by_others=$2;
if [ "$called_by_others" != "yes" ];then
        if ! . ./verify.sh "confirm_exec_script" "Are you sure you want to use $journal_devs to rebuild journal";then
                echo "cancel exec script";
                exit -1; 
        fi  
fi

if ! . ./verify.sh "verify_ceph_cluster";then
        echo "this node not in the ceph cluster or the ceph cluster is abnornal";
        exit -1; 
fi

if [ "$journal_devs" = "" ];then
        echo "please input the journal dev path,eg:./rebuild_journal /dev/sde";
        exit -1;
fi

if ! . ./verify.sh "check_journal_devs" "$journal_devs";then
        exit -1;    
fi

if ! . ./verify.sh "check_ssd_devs" "$journal_devs";then
        exit -1;
fi

osdids=`ls /var/lib/ceph/osd |grep -E 'ceph-' |awk -F '-' '{print $2}'`;
echo $osdids;
/etc/init.d/monit stop;
ceph osd set noout;
/etc/init.d/ceph stop osd;
for osdid in $osdids
do
	ceph-osd -i $osdid --flush-journal;
	rm -rf /var/lib/ceph/osd/ceph-$osdid/journal;
done
echo "start to clean old journal";
sleep 5;
exist_ceph_vg=`vgs 2>/dev/null |grep -E 'ceph'`;
if [ "$exist_ceph_vg" != "" ];then
	if [ -e /dev/ceph/journal ];then
		fuser -k /dev/ceph/journal;
		umount -f /dev/ceph/journal;
		lvremove -f /dev/ceph/journal;
		sed -i "/\/var\/lib\/ceph\/journal/d" /etc/ceph/fstab;
	fi
	vgremove -f ceph;
fi
echo "clean old journal finish";
echo "start to rebuild journal";
. ./only_add_journal_size.sh "$journal_devs" "yes";
exist_journal_lv=`lvs 2>/dev/null |grep -E 'journal'`;
if [ "$exist_journal_lv" = "" ];then
	echo "build journal failed";
	exit -1;	
fi
echo "finish rebuild journal";
for osdid in $osdids
do
	echo "start to allocate journal for $osdid";
	if . ./change_journal_bcache.sh "config_file_journal_for_osd" "$osdid";then
		echo "allocate journal for $osdid success";
	else
		echo "failed to allocate journal for $osdid";
	fi
done
/etc/init.d/ceph start osd
ceph osd unset noout;
/etc/init.d/monit start;
perl update_esan_info.pm;
