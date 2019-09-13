#!/bin/sh
name=$1;
start_cmd=$2;
stop_cmd=$3; 
if [ "$name" = "" ] || [ "$start_cmd" = "" ] || [ "$stop_cmd" = "" ];then
	echo "name or start_cmd or stop_cmd is null";
	return 2;
fi  
start_cmd=`echo $start_cmd |sed 's#/#\\\/#g'`;
stop_cmd=`echo $stop_cmd |sed 's#/#\\\/#g'`;
mon_file="/etc/monit.conf";
sed -i -e "/$name/d" -e "/$start_cmd/d" -e "/$stop_cmd/d" $mon_file;
sed -i '/^$/d' $mon_file;
