Uri=$1
HANAUSR=$2
HANAPWD=$3
HANASID=$4
HANANUMBER=$5

# Install PowerShell
wget https://github.com/PowerShell/PowerShell/releases/download/v6.0.0-beta.5/powershell-6.0.0_beta.5-1.suse.42.1.x86_64.rpm
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
sudo zypper info libuuid-devel
sudo rpm -Uvh --nodeps ./powershell-6.0.0_beta.5-1.suse.42.1.x86_64.rpm

#install hana prereqs
sudo zypper install -y glibc-2.22-51.6
sudo zypper install -y systemd-228-142.1
sudo zypper install -y unrar
sudo zypper install -y sapconf
sudo zypper install -y saptune
sudo mkdir /etc/systemd/login.conf.d
sudo mkdir /hana
sudo mkdir /hana/data
sudo mkdir /hana/log
sudo mkdir /hana/shared
sudo mkdir /hana/backup
sudo mkdir /usr/sap


# Install .NET Core and AzCopy
sudo zypper install -y libunwind
sudo zypper install -y libicu
curl -sSL -o dotnet.tar.gz https://go.microsoft.com/fwlink/?linkid=848824
sudo mkdir -p /opt/dotnet && sudo tar zxf dotnet.tar.gz -C /opt/dotnet
sudo ln -s /opt/dotnet/dotnet /usr/bin

wget -O azcopy.tar.gz https://aka.ms/downloadazcopyprlinux
tar -xf azcopy.tar.gz
sudo ./install.sh

# Install DSC for Linux
wget https://github.com/Microsoft/omi/releases/download/v1.1.0-0/omi-1.1.0.ssl_100.x64.rpm
wget https://github.com/Microsoft/PowerShell-DSC-for-Linux/releases/download/v1.1.1-294/dsc-1.1.1-294.ssl_100.x64.rpm

sudo rpm -Uvh omi-1.1.0.ssl_100.x64.rpm dsc-1.1.1-294.ssl_100.x64.rpm

#do more SAP configuration
tuned-adm profile sap-hana
systemctl start tuned
systemctl enable tuned
saptune solution apply HANA
saptune daemon start
echo 'GRUB_CMDLINE_LINUX_DEFAULT="transparent_hugepage=never numa_balancing=disable intel_idle.max_cstate=1 processor.max_cstate=1"' >>/etc/default/grub
grub2-mkconfig -o /boot/grub2/grub.cfg
echo 1 > /root/boot-requested

# Register Node for Azure Automation DSC Management
echo $Uri >> /tmp/url.txt

cp -f /etc/waagent.conf /etc/waagent.conf.orig
sedcmd="s/ResourceDisk.EnableSwap=n/ResourceDisk.EnableSwap=y/g"
sedcmd2="s/ResourceDisk.SwapSizeMB = 16384/ResourceDisk.SwapSizeMB = 16384/g"
cat /etc/waagent.conf | sed $sedcmd | sed $sedcmd2 > /etc/waagent.conf.new
cp -f /etc/waagent.conf.new /etc/waagent.conf

cp -f /etc/systemd/login.conf.d/sap.conf /etc/systemd/login.conf.d/sap.conf.orig
sedcmd="s/[login]`n
UserTasksMax=infinity`n/[login]`n
UserTasksMax=infinity`n/g"
cat /etc/systemd/login.conf.d/sap.conf | sed $sedcmd > //etc/systemd/login.conf.d/sap.conf.new
cp -f /etc/systemd/login.conf.d/sap.conf.new /etc/systemd/login.conf.d/sap.conf


echo "[login]`n
UserTasksMax=infinity`n" >> "/etc/systemd/login.conf.d/sap.conf"


echo "logicalvols start" >> /tmp/parameter.txt
pvcreate /dev/sd[cdefg]
vgcreate hanavg /dev/sd[fg]
lvcreate -l 80%FREE -n datalv hanavg
lvcreate -l 20%FREE -n loglv hanavg
mkfs.xfs /dev/hanavg/datalv
mkfs.xfs /dev/hanavg/loglv
echo "logicalvols start" >> /tmp/parameter.txt

filecount=`vgdisplay | grep hanavg | wc -l`
if [ $filecount -gt 0 ]
then
    exit 0
else
    exit 1
fi


#!/bin/bash
echo "logicalvols2 start" >> /tmp/parameter.txt
vgcreate sharedvg /dev/sdc 
vgcreate usrsapvg /dev/sdd
vgcreate backupvg /dev/sde  
 
lvcreate -l 100%FREE -n sharedlv sharedvg 
lvcreate -l 100%FREE -n backuplv backupvg 
lvcreate -l 100%FREE -n usrsaplv usrsapvg 
mkfs -t xfs /dev/sharedvg/sharedlv 
mkfs -t xfs /dev/backupvg/backuplv 
mkfs -t xfs /dev/usrsapvg/usrsaplv
echo "logicalvols2 end" >> /tmp/parameter.txt

#!/bin/bash
filecount=`vgdisplay | grep -E "sharedvg|backupvg|usrsapvg" | wc -l`
if [ $filecount -gt 2 ]
then
    filecount=`lvdisplay | grep -E "LV Name" | wc -l`
    if [ $filecount -gt 4 ]
    then
        exit 0
    else
        exit 1
    fi
else
    exit 1
fi

cp /etc/fstab /etc/fstab.orig
cat <<EOF >>/etc/fstab
/dev/sharedvg/sharedlv /hana/shared xfs defaults 1 0 
/dev/backupvg/backuplv /hana/backup xfs defaults 1 0 
/dev/usrsapvg/usrsaplv /usr/sap xfs defaults 1 0 
/dev/hanavg/datalv /hana/data xfs nofail 0 0  
/dev/hanavg/loglv /hana/log xfs nofail 0 0  
EOF

#!/bin/bash
echo "mounthanashared start" >> /tmp/parameter.txt
mount -t xfs /dev/sharedvg/sharedlv /hana/shared
mount -t xfs /dev/backupvg/backuplv /hana/backup 
mount -t xfs /dev/usrsapvg/usrsaplv /usr/sap
mount -t xfs /dev/hanavg/datalv /hana/data
mount -t xfs /dev/hanavg/loglv /hana/log 
mkdir /hana/data/sapbits
echo "mounthanashared end" >> /tmp/parameter.txt
exit 0

#!/bin/bash
filecount=`mount | grep -E "hana|sap" | wc -l`
if [ $filecount -gt 4 ]
then
    exit 0
else
    exit 1
fi

if [ ! -d "/hana/data/sapbits" ]; then
 mkdir "/hana/data/sapbits"
fi

if [ ! -d "$Uri/SapBits/md5sums" ]; then
 mkdir "$Uri/SapBits/md5sums"
fi

#!/bin/bash
cd /hana/data/sapbits
/usr/bin/wget --quiet $Uri/SapBits/51052325_part1.exe
/usr/bin/wget --quiet $Uri/SapBits/51052325_part2.rar
/usr/bin/wget --quiet $Uri/SapBits/51052325_part3.rar
/usr/bin/wget --quiet $Uri/SapBits/51052325_part4.rar
/usr/bin/wget --quiet $Uri/SapBits/hdbinst.cfg

date >> /tmp/testdate
cd /hana/data/sapbits
rarfilecount=`ls -1 | grep "rar" | wc -l`
if [ $rarfilecount -lt 3 ]
then
    exit 1
else
    ckfilecount=`ls -1 | grep md5sums.checked | wc -l`
    if [ $ckfilecount -gt 0 ]
    then
        exit 0
    fi
    mdstat=`md5sum --status -c md5sums`
    if [ $mdstat -gt 0 ]
    then
        exit 1
    else
	cp md5sums md5sums.checked    
        exit 0
    fi	
fi

#!/bin/bash
cd /hana/data/sapbits
unrar -inul x 51052325_part1.exe

cd /hana/data/sapbits
sbfilecount=`ls -1 | grep 51052325 | grep -v part| wc -l`
if [ $sbfilecount -gt 0 ]
then
    ssfilecount=`find /hana/data/sapbits/51052325 | wc -l`
    if [ $ssfilecount -gt 5365 ]
    then
        exit 0
    else
        exit 1
    fi
else
    exit 1
fi

#!/bin/bash
cd /hana/data/sapbits
myhost=`hostname`
sedcmd="s/REPLACE-WITH-HOSTNAME/$myhost/g"
sedcmd2="s/\/hana\/shared\/sapbits\/51052325/\/hana\/data\/sapbits\/51052325/g"
sedcmd3="s/root_user=root/root_user=$HANAUSR/g"
sedcmd4="s/root_password=AweS0me@PW/root_password=$HANAPWD/g"
sedcmd5="s/sid=H10/sid=$HANASID/g"
sedcmd5="s/number=00/number=$HANANUMBER/g"
cat hdbinst.cfg | sed $sedcmd | sed $sedcmd2 | sed $sedcmd3 | sed $sedcmd4 | $sedcmd5 > hdbinst-local.cfg
exit 0

#!/bin/bash
cd /hana/data/sapbits
filecount=`ls -1 | grep hdbinst-local.cfg  | wc -l`
if [ $filecount -gt 0 ]
then
    filecount=`grep -s hostname= /hana/data/sapbits/hdbinst-local.cfg | wc -l`
    if [ $filecount -gt 0 ]
    then
        exit 0
    else
        exit 1
    fi
else
    exit 1
fi

sudo zypper se -t pattern
sudo zypper in -t pattern sap-hana

#!/bin/bash
cd /hana/data/sapbits/51052325/DATA_UNITS/HDB_LCM_LINUX_X86_64
/hana/data/sapbits/51052325/DATA_UNITS/HDB_LCM_LINUX_X86_64/hdblcm -b --configfile /hana/data/sapbits/hdbinst-local.cfg

#!/bin/bash
filecount=`cat /etc/passwd | grep sapadm | wc -l`
if [ $filecount -gt 0 ]
then
    exit 0
else
    exit 1
fi
