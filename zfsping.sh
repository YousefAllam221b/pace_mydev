cd /pace
touch /tmp/zfsping
iscsimapping='/pacedata/iscsimapping';
runningpools='/pacedata/pools/runningpools';
myhost=`hostname -s`
hostnam=`cat /TopStordata/hostname`
poollist='/pacedata/pools/'${myhost}'poollist';
cachestate=0;
cd /pacedata/pools/
allpools=`cat /pacedata/pools/$(ls /pacedata/pools/ | grep poollist)`
cp ${iscsimapping} ${iscsimapping}new;
declare -a pools=(`/sbin/zpool list -H | awk '{print $1}'`)
declare -a idledisk=();
declare -a hostdisk=();
declare -a alldevdisk=();
cd /pace
sh iscsirefresh.sh   &>/dev/null &
sh listingtargets.sh  &>/dev/null
if [ -z $pools ]; then
 ./initdisks.sh
fi
sleep 1
runninghosts=`cat $iscsimapping | grep -v notconnected | awk '{print $1}'`
for pool in "${pools[@]}"; do
 singledisk=`/sbin/zpool list -Hv $pool | wc -l`
 if [ $singledisk -gt 3 ]; then
  /sbin/zpool status $pool | grep "was /dev" &>/dev/null
  if [ $? -eq 0 ]; then
   faildisk=`/sbin/zpool status $pool | grep "was /dev" | awk -F'-id/' '{print $2}' | awk -F'-part' '{print $1}'`;
   /sbin/zpool detach $pool $faildisk &>/dev/null;
   /sbin/zpool set cachefile=/pacedata/pools/${pool}.cache $pool;
   cachestate=1;
  fi 
  /sbin/zpool status $pool | grep "was /dev/s" ;
  if [ $? -eq 0 ]; then
   faildisk=`/sbin/zpool status $pool | grep "was /dev/s" | awk -F'was ' '{print $2}'`;
   /sbin/zpool detach $pool $faildisk &>/dev/null;
   /sbin/zpool set cachefile=/pacedata/pools/${pool}.cache $pool ;
   cachestate=1;
  fi 
  /sbin/zpool status $pool | grep OFFLINE &>/dev/null
  if [ $? -eq 0 ]; then
   faildisk=`/sbin/zpool status $pool | grep OFFLINE | awk '{print $1}'`;
   /sbin/zpool detach $pool $faildisk &>/dev/null;
   /sbin/zpool set cachefile=/pacedata/pools/${pool}.cache $pool;
   cachestate=1;
  fi
  /sbin/zpool status $pool | grep UNAVAIL &>/dev/null
  if [ $? -eq 0 ]; then
   faildisk=`/sbin/zpool status $pool | grep UNAVAIL | awk '{print $1}'`;
   /sbin/zpool detach $pool $faildisk &>/dev/null;
   /sbin/zpool set cachefile=/pacedata/pools/${pool}.cache $pool;
   cachestate=1;
  fi 
 fi
done
while read -r  hostline ; do
 host=`echo $hostline | awk '{print $1}'`
 echo $hostline | grep "notconnected" &>/dev/null
 if [ $? -eq 0 ]; then
  hostdiskid=`echo $host | awk '{print $3}'`
  for pool2 in "${pools[@]}"; do
   /sbin/zpool list -Hv $pool2 | grep "$hostdiskid" &>/dev/null
   if [ $? -eq 0 ]; then 
    /sbin/zpool offline $pool2 "$hostdiskid" &>/dev/null;
    /sbin/zpool set cachefile=/pacedata/pools/${pool2}.cache $pool2;
   cachestate=1;
   fi
  done
  cat ${iscsimapping}new | grep -w "$host" | grep "notconnected" &>/dev/null
  if [ $? -ne 0 ]; then 
#   echo disconnecting $host disks
   declare -a hostdiskids=(`cat ${iscsimapping}new | grep -w "$host" | awk '{print $3}'`);
   for hostdiskid in "${hostdiskids[@]}"; do
    for pool2 in "${pools[@]}"; do
     /sbin/zpool list -Hv $pool2 | grep "$hostdiskid" &>/dev/null
     if [ $? -eq 0 ]; then 
      /sbin/zpool offline $pool2 "$hostdiskid" &>/dev/null;
      /sbin/zpool set cachefile=/pacedata/pools/${pool2}.cache $pool2;
      cachestate=1;
     fi
    done
   done;
  fi
 fi
done < ${iscsimapping}
 
needlist=1;
for pool in "${pools[@]}"; do
 runningdisk=`/sbin/zpool list -Hv $pool | grep -v "$pool" | grep -v mirror | awk '{print $1}'`
 single=`/sbin/zpool list -Hv $pool | grep -v "$pool" | grep -v mirror | wc -l`
# echo single count=$single
 if [ "$single" -eq 1 ]; then
  if [ "$needlist" -eq 1 ] ; then 
#   echo here1
   needlist=2;
   expopool=`/sbin/zpool import 2>/dev/null`
   while read -r  hostline ; do
    diskid=`echo $hostline | awk '{print $3}'`
    host=`echo $hostline | awk '{print $1}'`
#    echo host,diskid= $host, $diskid
    echo $hostline | grep "notconnected" &>/dev/null
    if [ $? -ne 0 ]; then
#     echo here1_2
     echo $allpools | grep "$diskid" &>/dev/null
     if [ $? -ne 0 ]; then
#      echo not in a runningpool 
      echo $myhost | grep "$host" &>/dev/null
      if [ $? -eq 0 ]; then
#          echo local disk
       hostdisk=("${hostdisk[@]}" "$host,$diskid");
#       echo hostdisk=${hostdisk[@]};
      else
#        echo foreign disk
       idledisk=("${idledisk[@]}" "$host,$diskid");
#       echo idledisk=${idledisk[@]};
      fi
#      echo idledisk=${idledisk[@]}
#      echo hostdisk=${hostdisk[@]}
     fi
    else
     echo $runninghosts | grep $host &>/dev/null
     if [ $? -eq 0 ]; then
       /sbin/iscsiadm -m session --rescan &>/dev/null
     fi
    fi
   done < $iscsimapping
  fi
#  echo here2
  /sbin/zpool clear $pool &>/dev/null
  singlehost=`cat $iscsimapping | grep "$runningdisk" `;
  echo $singlehost | grep "$myhost" &>/dev/null
  if [ $? -eq 0 ]; then
#   echo here3
   i=$((${#idledisk[@]}-1))
#   echo i = $i
   if [ $i -ge 0 ]; then
    newdisk=`echo ${idledisk[$i]} | awk -F',' '{print $2}'`
#    echo /sbn/zpool attach -f $pool $runningdisk $newdisk ;
    zpool labelclear /dev/disk/by-id/$newdisk
    /sbin/zpool attach -f $pool $runningdisk $newdisk ;
    if [ $? -eq 0 ]; then 
     /sbin/zpool set cachefile=/pacedata/pools/${pool}.cache $pool;
      cachestate=1;
     unset idledisk[$i];
    fi
   fi
  else
#   echo here5
   i=$((${#hostdisk[@]}-1));
#   echo i=$i
   if [ $i -ge 0 ]; then
    newdisk=`echo ${hostdisk[$i]} | awk -F',' '{print $2}'`
    zpool labelclear /dev/disk/by-id/$newdisk
    /sbin/zpool attach -f $pool $runningdisk $newdisk ;
#    echo /sbin/zpool attach -f $pool $runningdisk $newdisk ;
    if [ $? -eq 0 ]; then 
     /sbin/zpool set cachefile=/pacedata/pools/${pool}.cache $pool ;
      cachestate=1;
     unset hostdisk[$i];
    fi
   fi
  fi
 fi 
done
/sbin/zpool list -Hv | awk '{print $1}' > ${poollist}local
diff ${poollist} ${poollist}local  &>/dev/null
if [ $? -ne 0 ]; then 
 cp ${poollist}local $poollist
 cachestate=1;
fi
if [ $cachestate -ne 0 ]; then
 cachestate=0;
 while read -r  hostline ; do
  host=`echo $hostline | awk '{print $1}'`
  echo $hostline | grep "notconnected"  &>/dev/null
  if [ $? -ne 0 ]; then
   echo $hostline | grep "$myhost" &>/dev/null
   if [ $? -ne 0 ]; then
    scp -r -o ConnectTimeout=5 /pacedata/pools $host:/pacedata;
   fi
  fi
 done < ${iscsimapping}
fi
tomount=`zpool import 2>/dev/null | grep "pool:" `
emptypools=`cat $runningpools | wc -l `
echo $tomount | grep "pool:" &>/dev/null
if [ $? -eq 0 ]  || [ $emptypools -lt 2 ]; then
 tomount=`echo $tomount | awk '{print $2}'`
 cat $runningpools | grep $tomount &>/dev/null
 if [ $? -ne 0 ]; then
  zpool import $tomount 
  poollist=`zpool list -Hv`
  cat $runningpools | grep "$myhost" | grep "$poollist" | grep "$hostnam" 
  if [ $? -ne 0 ]; then
   echo $myhost' '$poollist' '$hostnam >> $runningpools 
  fi
  systemctl start nfs
  collectl -D /etc/collectl.conf
  rm -rf /var/www/html/des20/Data/Getstatspid &>/dev/null
  chgrp apache /var/www/html/des20/Data/*
  chmod g+r /var/www/html/des20/Data/*
 fi 
fi
mypool=`cat $runningpools | grep "$myhost" | awk '{print $2}'`;
cat $runningpools | grep "$mypool" | grep -v "$myhost"  &>/dev/null
if [ $? -ne 0 ]; then
 runpools=`zpool list | grep "$mypool"`
 echo $runpools | grep $mypool &>/dev/null
 if [ $? -ne 0 ]; then
  zpool import $mypool
  newline=$myhost' '`zpool list -Hv $mypool`' '$hostnam
  sed -i "/$mypool/c/$newline" $runningpools 
  systemctl start nfs
  collectl -D /etc/collectl.conf
  rm -rf /var/www/html/des20/Data/Getstatspid &>/dev/null
  chgrp apache /var/www/html/des20/Data/*
  chmod g+r /var/www/html/des20/Data/*
 fi
fi
