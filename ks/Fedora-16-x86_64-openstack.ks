# Build a basic Fedora 16 AMI
lang en_US.UTF-8
keyboard us-acentos
timezone --utc Europe/Paris
auth  --useshadow  --passalgo=md5
#selinux --enforced
#selinux --permissive
selinux --disabled
firewall --enabled --http --ftp --ssh
bootloader --timeout=1 --location=mbr --driveorder=sda
network --bootproto=dhcp --device=eth0 --onboot=on
services --enabled=network,sshd,rsyslog
# Root password (Welcome01). Change as appropriate.
# If you comment the following line, the password will be empty
rootpw --iscrypted $1$Mjpoh12a$ialax0v3C/EENUCVxSMut0

# By default the root password is emptied

#
# Define how large (in MB) you want your rootfs to be
#
part biosboot --fstype=biosboot --size=1 --ondisk sda
part / --size 10000 --fstype ext4 --ondisk sda
#
# For a full blown Fedora distribution, the following disks may be configured,
# but it will take 30GB of actual disk.
# In that case, just comment the last line above and uncomment the lines below:
#part / --asprimary --fstype="ext4" --size=15000 --ondisk=sda
#part swap --asprimary --fstype="ext4" --size=4000 --ondisk=sda
#part /home --asprimary --fstype="ext4" --size=15000 --ondisk=sda

#
# Repositories
repo --name=fedora --mirrorlist=http://mirrors.fedoraproject.org/mirrorlist?repo=fedora-16&arch=$basearch

#
#
# Add all the packages after the base packages
#
%packages --nobase
@core
system-config-securitylevel-tui
audit
pciutils
bash
coreutils
kernel
#grub
grub2

e2fsprogs
passwd
policycoreutils
chkconfig
rootfiles
yum
vim-minimal
acpid
openssh-clients
openssh-server
curl
links
less
sudo

#Allow for dhcp access
dhclient
iputils

-firstboot
-biosdevname

# package to setup cloudy bits for us
cloud-init

# For hack below
patch

%end

# more ec2-ify
%post --erroronfail

# create ec2-user
/usr/sbin/useradd ec2-user
/bin/echo -e 'ec2-user\tALL=(ALL)\tNOPASSWD: ALL' >> /etc/sudoers

# Standard configuration (a single partition)
cat << _EOL > /etc/fstab
LABEL=_/     /         ext4    defaults        1 1
proc         /proc     proc    defaults        0 0
sysfs        /sys      sysfs   defaults        0 0
devpts       /dev/pts  devpts  gid=5,mode=620  0 0
tmpfs        /dev/shm  tmpfs   defaults        0 0
_EOL

# If you chose the large disk configuration, comment the lines above and uncomment the lines below
#cat << _EOL > /etc/fstab
#LABEL=_/     /         ext4    defaults        1 1
#LABEL=_/home /home     ext4    defaults        1 2
##swap       swap      swap defaults 0 0
#proc         /proc     proc    defaults        0 0
#sysfs        /sys      sysfs   defaults        0 0
#devpts       /dev/pts  devpts  gid=5,mode=620  0 0
#tmpfs        /dev/shm  tmpfs   defaults        0 0
#_EOL

# the firewall rules get saved as .old  without this we end up not being able 
# ssh in as iptables blocks access

rename .old "" /etc/sysconfig/*old

# setup systemd to boot to the right runlevel
rm /etc/systemd/system/default.target
ln -s /lib/systemd/system/multi-user.target /etc/systemd/system/default.target

%end

