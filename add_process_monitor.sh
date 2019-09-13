#!/bin/sh
add_name=$1;
add_pidfile=$2;
add_start_cmd=$3;
add_stop_cmd=$4;

if [ "$add_name" = "" ] || [ "$add_pidfile" = "" ] || [ "$add_start_cmd" = "" ] || [ "$add_stop_cmd" = "" ];then
	echo "name or pidfile or start_cmd or stop_cmd is null";
fi
echo "add monitor process:$add_name";
. ./delete_process_monitor.sh "$add_name" "$add_start_cmd" "$add_stop_cmd";
mon_file="/etc/monit.conf";
echo  "" >> $mon_file;
echo  "check process $add_name with pidfile $add_pidfile" >> $mon_file;
echo  "    start program = \"$add_start_cmd\"" >> $mon_file;
echo  "    stop program = \"$add_stop_cmd\"" >> $mon_file;
