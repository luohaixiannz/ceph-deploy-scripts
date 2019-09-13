#!/bin/sh
if ! . ./verify.sh "confirm_exec_script" "Are you sure you want to restart all ceph service";then
	echo "cancel exec script";
	exit -1; 
fi
/etc/init.d/ceph restart
/etc/init.d/monit restart
