#!/bin/sh
function clean_osd_cache {
        cset_uuid=`bcache-super-show /dev/osd/cache 2>/dev/null |grep 'cset.uuid' |awk '{print $2}'`;
        if [ "$cset_uuid" != "" ];then
                if [ -e "/sys/fs/bcache/$cset_uuid/stop" ];then
                        echo 1 > /sys/fs/bcache/$cset_uuid/stop;
                        sleep 3;
                        try_count=0;
                        while (($try_count<300)) # sleep for bcache dev to stop
                        do
                                if [ ! -e "/sys/fs/bcache/$cset_uuid" ];then
                                        break;
                                fi
                                ((try_count=$try_count+1));
                                echo 1 > /sys/fs/bcache/$cset_uuid/stop;
                                sleep 2;
                        done
                fi
        fi
        fuser -k /dev/osd/cache;
        lvremove -f /dev/osd/cache;
        vgremove -f osd;
}

function clean_osd_bcache {
		osd_id=$1;
        osd_dir_path="/var/lib/ceph/osd/ceph-$osd_id"
        bcache_name=`mount |grep $osd_dir_path |grep -Eo 'bcache[0-9]+'`;
        bcache_slaves=`ls -l /sys/block/$bcache_name/slaves/ 2>/dev/null |grep -E 'sd|vd|hd' |awk '{print $9}' 2>/dev/null`;

        fuser -k $osd_dir_path;
		tmp_try_count=1;
		while (($tmp_try_count<5))
		do
			if umount $osd_dir_path;then
				break;
			fi
			mount_err=$(umount $osd_dir_path 2>&1);
			is_substr=$(echo $mount_err | grep "not mounted");
			if [[ "$is_substr" != "" ]];then
				break;
			fi
			echo 'umount failed';
			((tmp_try_count=$tmp_try_count+1));
		done
		if [[ $tmp_try_count -ge 5 ]];then
			return 2;
		fi
		sed -i "/ceph-$osd_id/d" /etc/ceph/fstab;
        if [ "$bcache_name" != "" ] && [ -e "/sys/block/$bcache_name" ];then
                echo 1 >/sys/block/$bcache_name/bcache/detach;
                sleep 5;
                echo 1 >/sys/block/$bcache_name/bcache/stop;
                try_count=0;
                while (($try_count<300)) # sleep for bcache dev to stop
                do
                        echo "wait for osd cache to stop:$try_count";
                        if [ ! -e "/sys/block/$bcache_name" ];then
                                break;
                        fi
                        ((try_count=$try_count+1));
                        sleep 2;
                done
        fi
        if [ "$bcache_slaves" != "" ] && [ -e "/dev/$bcache_slaves" ];then
		echo 1 >/sys/block/$bcache_slaves/bcache/stop;
                dd if=/dev/null of=/dev/$bcache_slaves bs=1M count=1 oflag=direct;
        fi
}

function config_bcache_for_osd {
        osdid=$1;
        osd_dev_path=$2;
        echo "enter function config_bcache osdid:$osdid, osd_dev_path:$osd_dev_path";
        if [ $osdid = "" ] || [ "$osd_dev_path" = "" ];then
                echo "osdid or osd_dev_path is null";
                return 2;
        fi
		bcache_slaves=`echo $osd_dev_path |awk -F/ '{print $3}'`;
        cache_path="/dev/osd/cache";
        modprobe bcache;
        osd_cache_related_bcache=`ls -l /dev/osd/cache 2>/dev/null |awk -F/ '{print $5}' |xargs -i bcache-super-show /dev/{} 2>/dev/null|grep 'cache device'`;
        if [ "$osd_cache_related_bcache" = "" ];then
                fuser -k $cache_path;
                dd if=/dev/zero of=$cache_path oflag=direct bs=1M count=1;
                wipefs -a /dev/osd/cache;
                make-bcache -C $cache_path --wipe-bcache;
                echo $cache_path > /sys/fs/bcache/register;
        fi

        fuser -k $osd_dev_path;
        echo 1 >/sys/block/$bcache_slaves/bcache/stop;
		#dd if=/dev/zero of=$osd_dev_path oflag=direct bs=1M count=1;
        try_count=1
        while (($try_count<5))
        do
                if make-bcache -B $osd_dev_path --wipe-bcache;then
                        break
                fi
                sleep 5
                ((try_count=$try_count+1));
        done
        echo "$osd_dev_path" >/sys/fs/bcache/register;
        sleep 2;
        cset_uuid=`bcache-super-show /dev/osd/cache 2>/dev/null |grep 'cset.uuid' |awk '{print $2}'`;
        osd_bcache_name=`lsblk $osd_dev_path 2>/dev/null |grep -Eo 'bcache[0-9]*'`;
        echo "$cset_uuid" >/sys/block/$osd_bcache_name/bcache/attach;
        echo "writeback" >/sys/block/$osd_bcache_name/bcache/cache_mode;

        osd_dev_path="/dev/$osd_bcache_name";
        echo $osd_dev_path;
        osd_dir_path="/var/lib/ceph/osd/ceph-$osdid";
        mkdir -p $osd_dir_path;
        mount -o noatime,nobarrier,inode64 $osd_dev_path $osd_dir_path;
        osd_bcache_uuid=`blkid /dev/$osd_bcache_name 2>/dev/null |awk -F '"' '{print $2}'`;
        echo $osd_bcache_uuid;
        OSD_FSTAB="/etc/ceph/fstab";
        if [ ! -e "$OSD_FSTAB" ];then
                echo "UUID=$osd_bcache_uuid      $osd_dir_path   xfs  noatime,nobarrier,inode64   0 0" > $OSD_FSTAB;
        else
                sed -i "/ceph-$osd_id/d" $OSD_FSTAB;
                echo "UUID=$osd_bcache_uuid      $osd_dir_path   xfs  noatime,nobarrier,inode64   0 0" >> $OSD_FSTAB;
        fi
}

function config_file_journal_for_osd {
	osdid=$1;
	osdname=osd.$osdid;
	if [ $osdid = "" ];then
        	return 2;
	fi
	journal_mount_path="/var/lib/ceph/journal";
	avail_journal_space=`df $journal_mount_path 2>/dev/null |grep $journal_mount_path |awk '{print $3}'`;
	echo "avail_journal_space:$avail_journal_space";
	need_journal_space=`cat /etc/ceph/ceph.conf |grep "osd journal size" |awk -F '=' '{print $2}'`;
	((need_journal_space=$need_journal_space*1024));
	if [ $avail_journal_space -lt $need_journal_space ];then
        	echo "there is no enough journal space for $osdname";
        	return 2;
	fi
	journal_path="/var/lib/ceph/journal/journal-$osdid";
	rm -rf $journal_path;
	mkdir -p $journal_path;
	journal_path=$journal_path/journal;
	touch $journal_path;

	osd_dir="/var/lib/ceph/osd/ceph-$osdid";
	rm -rf $osd_dir/journal;
	ln -s $journal_path $osd_dir/journal;
	if ! ceph-osd -i $osdid --mkjournal;then
        	echo "remake journal failed";
        	return 2;
	fi	
}

function get_osdids {
	osds_info=`perl perl_request.pm get_osd_map_serial 2>/dev/null`;
	osdids="";	
	for osd_info in $osds_info
	do
		osdid=`echo $osd_info |awk -F= '{print $1}' |awk -F '.' '{print $2}'`;
		osdids="$osdids $osdid";
	done
}

function find_osd_dev_path {
	osdname=$1;
	serial=`perl perl_request.pm get_osd_map_serial 2>/dev/null |grep -Eo "$osdname=\S+" |awk -F= '{print $2}'`;
	if [ "$serial" != "" ];then
		osd_dev_path=`ls -al /dev/disk/by-id/ 2>/dev/null |grep $serial |grep -Eo '(sd|hd|vd)\w+' |sed -n '1p'`;
		if [ "$osd_dev_path" != "" ];then
			osd_dev_path="/dev/$osd_dev_path";
		fi
	fi
}

request=$1;
case $request in
	"clean_osd_cache")
		clean_osd_cache;
		return $?;
	;;
	"clean_osd_bcache")
		clean_osd_bcache "$2";
		return $?;
	;;
	"config_bcache_for_osd")
		config_bcache_for_osd "$2" "$3" "$4";
		return $?;
	;;
	"config_file_journal_for_osd")
		config_file_journal_for_osd "$2";
		return $?;
	;;
	"get_osdids")
		get_osdids;
		return $?;
	;;
	"find_osd_dev_path")
		find_osd_dev_path "$2";
		return $?;
	;;
	*)
		echo "unknow request:$request";
		return 2;
	;;
esac
