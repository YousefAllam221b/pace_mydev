#!/bin/sh
export ETCDCTL_API=3
cd /TopStor/
echo $@ > /root/removetargetdisks
thehost=`echo $@ | awk '{ print $1 }'`;
hostname=`hostname -s`
echo $thehost | grep $hostname
if [ $? -ne 0 ];
then
 initiator=`targetcli ls | grep $thehost | grep 1994 | awk -F'o- ' '{print $2}' | awk '{print $1}'`
 targetcli iscsi/iqn.2016-03.com.$hostname:t1/tpg1/acls/ delete $initiator
else
 targetcli clearconfig confirm=true
fi
