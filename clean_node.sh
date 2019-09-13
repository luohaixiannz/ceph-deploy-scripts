#!/bin/sh

function recover_netcard_bond_config
{
	back_path="/etc/sysconfig/eth-config-backup-dir";
	backup_pre="backup-ifcfg"; 
	network_path="/etc/sysconfig/network-scripts";
	eth_list=`ip addr |grep -Eo eth[0-9]+ |uniq |tr  '\n' ' '`;
	restart_or_not=0;
	for eth in $eth_list
	do
		if [ -e "$back_path/$backup_pre-$eth" ];then
			rm -rf $network_path/ifcfg-$eth;
			mv -f $back_path/$backup_pre-$eth $network_path/ifcfg-$eth;
			restart_or_not=1;
		fi
	done

	del_bond_list=`ls $back_path/del-* 2>/dev/null |grep -Eo 'bond.*' |tr '\n' ' '`;
	for eth in $del_bond_list
	do
		if [ -e "$back_path/del-$eth" ];then
			rm -rf $network_path/ifcfg-$eth;
			rm -rf $back_path/del-$eth;
			restart_or_not=1;
		fi
	done

	if [ "$restart_or_not" = "1" ];then
		service ovp-cluster stop;
		service cman stop;
		pkill -9 ovpcfs;
		pkill -9 corosync;

		service network restart;

		service cman start;
		service ovp-cluster start;
	fi
}

called_by_others=$1;
if [ "$called_by_others" != "yes" ];then
        if ! . ./verify.sh "confirm_exec_script" "Are you sure you want to delete anything about ceph in this node";then
                echo "cancel exec script";
                exit -1; 
        fi  
fi

osdnames=`ls /var/lib/ceph/osd/ |grep -Eo ceph-[0-9]+ |sed 's/ceph-/osd./' |tr '\n' ','`;
if [ "$osdnames" != "" ];then
	. ./clean_osd_and_releated.sh "$osdnames" "yes";
fi

/etc/init.d/monit stop;

sleep 5;

exist_osd_vg=`vgs osd 2>/dev/null`;
if [ "$exist_osd_vg" != "" ];then
	if ! . ./change_journal_bcache.sh "clean_osd_cache";then
		echo "clean_osd_cache failed";
	fi
fi

exist_ceph_vg=`vgs ceph 2>/dev/null`;
if [ "$exist_ceph_vg" != "" ];then
	if [ -e "/dev/ceph/journal" ];then
		fuser -k /dev/ceph/journal;
		umount -f /dev/ceph/journal;
		lvremove -f /dev/ceph/journal;
		vgremove -f ceph;
	fi
fi

hostname=`hostname 2>/dev/null`;
ceph osd crush remove $hostname;
. ./remove_monitor.sh "yes";
/etc/init.d/monit stop;

perl perl_request.pm storage_disable_node $hostname;
pkill -9 ceph-osd;
rm -rf /etc/ceph/*;
rm -rf /var/lib/ceph/*/*;
rm -rf /etc/ovp/local/esan_info;
rm -rf /etc/ovp/local/esan_stat.json;
rm -rf /etc/bcacheuuid_map_osduuid;

recover_netcard_bond_config;
