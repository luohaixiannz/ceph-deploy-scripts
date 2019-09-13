disk_path=$1;
count=$2;
max_count=30000;
if [ "$disk_path" = "" ] || [ "$count" = "" ];then
        echo "please input disk,eg: ./disk_show_light /dev/sde 100";
	exit -1;
fi
if [ $count -gt $max_count ];then
	echo "the input $count should < 30000";
	exit -1;
fi
dd if=$disk_path of=/dev/null iflag=direct bs=1M count=$count;
