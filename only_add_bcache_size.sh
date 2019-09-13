#!/bin/sh
function config_osd_cache_lv {
	osd_cache_dev_path=$1;
	exist_osd_vg=`vgs osd 2>/dev/null`;
	if [ "$exist_osd_vg" = "" ];then
		if vgcreate osd $osd_cache_dev_path;then
			osd_cache_dev_size=`lsblk $osd_cache_dev_path -o size |grep -Eo '[0-9\.]+.'`;
			unit=${osd_cache_dev_size: -1};
			osd_cache_dev_size=`echo $osd_cache_dev_size 0.1 |awk '{print $1-$2}'`;
			if ! lvcreate osd -n cache -L ${osd_cache_dev_size}${unit};then
				echo "create cache lv error";
				return 2;
			fi
		else
			echo "create osd vg error";
			return 2;
		fi
	else
		if ! (pvcreate $osd_cache_dev_path && vgextend osd $osd_cache_dev_path \
		   && lvextend /dev/osd/cache $osd_cache_dev_path);then
			echo "lvextend $osd_cache_dev_path error";
			return 2;
		fi
	fi
}

osd_cache_devs=$1;
called_by_others=$2;
tmp_called_by_others=$called_by_others;
if [ "$called_by_others" != "yes" ];then
        if ! . ./verify.sh "confirm_exec_script" "Are you sure you want to use $osd_cache_devs to add bcache size";then
                echo "cancel exec script";
                exit -1;
        fi
fi

if ! . ./verify.sh "verify_ceph_cluster";then
        echo "this node not in the ceph cluster or the ceph cluster is abnornal";
        exit -1; 
fi

if [ "$osd_cache_devs" = "" ];then
        echo "please input the osd_cache dev path,eg:./only_add_bcache_size /dev/sde";
        exit -1;
fi

if ! . ./verify.sh "check_ssd_devs" "$osd_cache_devs";then
        exit -1;
fi

. ./clean_disks.sh $osd_cache_devs "yes";
osd_cache_devs=`echo $osd_cache_devs |sed 's/,/ /g'`;
for dev in $osd_cache_devs
do
        echo "start to add $dev to osd cache";
        config_osd_cache_lv $dev;
        if [ "$?" = "2" ];then
                echo "add $dev to osd cache failed";
        else
                echo "add $dev to osd cache success";
        fi
done
if [ "$tmp_called_by_others" != "yes" ];then
	perl update_esan_info.pm;
fi
