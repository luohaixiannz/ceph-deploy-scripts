#!/bin/sh
function pg_calc {
	osd_count=$1;
	pool_count=$2;
	rep_size=$3;
	pg_num=512;
	if [ $osd_count -gt 0 ] && [ $osd_count -lt 5 ];then
		pg_num=128;
	
	elif [ $osd_count -ge 5 ] && [ $osd_count -le 10 ];then
		pg_num=512;
	else
		((per_pool_pg=$osd_count*100/$rep_size));
		i=0;
		while(($i<=20))
		do
			tmp=$((2**$i));
			if [ $tmp -gt $per_pool_pg ];then
				pg_num=$tmp;
				break;
			fi
			((i=$i+1));
		done
	fi
}

function change_pool_pg_num {
	pool_name=$1;
	new_pg_num=$2;
	if [ "$pool_name" = "" ]  || [ "$new_pg_num" = "" ];then
		echo "pool_name or new_pg_num is null";
		return 2;
	fi

	old_pg_num=`ceph osd pool get $pool_name pg_num 2>/dev/null |awk -F ' ' '{print $2}'`;
	if [ "$old_pg_num" != "" ] && [ $old_pg_num -ge $new_pg_num ];then #don't allow to decrease
		return 2;
	fi

	ceph osd pool set $pool_name pg_num $new_pg_num;
	stat=`ceph pg stat 2>/dev/null |grep creating`;
	count=0;
	while [ "$stat" != "" ] #await until pg createing over
	do
		sleep 2;
		((count=$count+1));
		if [ $count -gt 3600 ];then
			break;
		fi
		stat=`ceph pg stat 2>/dev/null |grep creating`;
	done
	sleep 3;
	if ! ceph osd pool set $pool_name pgp_num $new_pg_num;then
		echo "set pool pg failed";
		return 2;
	fi
}

if ! . ./verify.sh "verify_ceph_cluster";then
        echo "this node not in the ceph cluster or the ceph cluster is abnornal";
        exit -1; 
fi
replicated_size=`ceph --show-config |grep osd_pool_default_size| grep -Eo [0-9]+`;
pool_num=`rados lspools |wc -l`;
osd_count=`ceph osd ls |wc -l`;
pg_num=0;
pg_calc $osd_count $pool_num $replicated_size;
echo "change pool pg_num:$pg_num";
change_pool_pg_num "esan_pool" $pg_num;
