#!/bin/sh
osdids="";
. ./change_journal_bcache.sh "get_osdids";
for osdid in $osdids
do
	osd_dev_path="";
	. ./change_journal_bcache.sh "find_osd_dev_path" "osd.$osdid";
	echo "$osd_dev_path <=> osd.$osdid";
done

lines=`pvs 2>/dev/null |awk 'END{print NR}'`;
count=2;
while (($count<=$lines))
do
	type=`pvs 2>/dev/null |sed -n "$count, 1p" | awk '{print $2}'`;
	if [ "$type" = "ceph" ] || [ "$type" = "osd" ];then
		disk_path=`pvs 2>/dev/null |sed -n "$count, 1p" | awk '{print $1}'`;
		if [ "$disk_path" != "" ];then
			if [ "$type" = "ceph" ];then
				echo "$disk_path <=> journal disk";
			else
				echo "$disk_path <=> osd cache disk";
			fi
		fi
	fi
	((count=$count+1));
done
