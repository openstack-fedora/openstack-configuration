
#### ========================================================== ####
##                        OpenStack alone                         ##
#### ========================================================== ####

##
# Documentation
#
midori http://fedoraproject.org/wiki/Getting_started_with_OpenStack_on_Fedora_17

##
# OpenStack version
#
midori http://wiki.openstack.org/Releases

# The default version of OpenStack is:
# - Essex (2012.1.x) on Fedora 17
# - Folsom (2012.2.x) on Fedora 18
# As the most recent versions of OpenStack are packaged for Fedora/RedHat/CentOS,
# one can add the following Yum repository to upgrade OpenStack, for instance
# from Essex to Folsom on a Fedora 17, or to install directly the latest version.
curl http://repos.fedorapeople.org/repos/openstack/openstack-folsom/fedora-openstack-folsom.repo \
	-o /etc/yum.repos.d/fedora-openstack-folsom.repo

##
# Release version of OpenStack:
#
# For a remote repository:
yum info openstack-nova-compute | grep -e Version -e Release
# Standard Fedora 17 repositories:
echo Version     : 2012.1.3
echo Release     : 1.fc17
#
# Fedora OpenStack preview repository:
echo Version     : 2012.2
echo Release     : 1.fc18
#
# From the RPM database:
rpm -qv openstack-nova-compute
# Standard Fedora 17 repositories:
echo openstack-nova-compute-2012.1.3-1.fc17.noarch
# Fedora OpenStack preview repository:
echo openstack-nova-compute-2012.2-1.fc18.noarch
#
# From OpenStack itself:
nova-manage version
# Standard Fedora 17 repositories:
echo 2012.1.3 (2012.1.3-LOCALBRANCH:LOCALREVISION)
# Fedora OpenStack preview repository:
echo 2012.2 (2012.2-LOCALBRANCH:LOCALREVISION)


##
# Packages and dependencies
# Nova (compute), Glance (images), Keystone (identity), Swift (object store), Horizon (dashboard)
yum -y install openstack-utils openstack-nova openstack-glance openstack-keystone \
	openstack-swift openstack-dashboard openstack-swift-proxy openstack-swift-account \
	openstack-swift-container openstack-swift-object
# QPID (AMQP message bus), memcached, NBD (Network Block Device) module
yum -y install qpid-cpp-server-daemon qpid-cpp-server memcached nbd
# Python bindings
yum -y install python-django-openstack-auth python-django-horizon \
	python-keystone python-keystone-auth-token python-keystoneclient \
	python-nova-adminclient python-quantumclient
# Some documentation
yum -y install openstack-keystone-doc openstack-swift-doc openstack-cinder-doc \
	python-keystoneclient-doc
# New Folsom components: Quantum (network), Tempo, Cinder (replacement for Nova volumes)
yum -y install openstack-quantum openstack-tempo openstack-cinder \
	openstack-quantum-linuxbridge openstack-quantum-openvswitch \
	python-cinder python-cinderclient
# Ruby bindings
yum -y install rubygem-openstack rubygem-openstack-compute
# Image creation
yum -y install appliance-tools appliance-tools-minimizer \
	febootstrap rubygem-boxgrinder-build

# Eucalyptus
yum -y install euca2ools

# DeltaCloud
yum -y install deltacloud-core-eucalyptus

##
# MySQL databases
mkdir -p ~/etc
cat > ~/etc/clean_os_db.sql << _EOF
drop database if exists nova;
drop database if exists glance;
drop database if exists cinder;
drop database if exists keystone;
grant usage on *.* to 'nova'@'%'; drop user 'nova'@'%';
grant usage on *.* to 'nova'@'localhost'; drop user 'nova'@'localhost';
grant usage on *.* to 'glance'@'%'; drop user 'glance'@'%';
grant usage on *.* to 'glance'@'localhost'; drop user 'glance'@'localhost';
grant usage on *.* to 'cinder'@'%'; drop user 'cinder'@'%';
grant usage on *.* to 'cinder'@'localhost'; drop user 'cinder'@'localhost';
grant usage on *.* to 'keystone'@'%'; drop user 'keystone'@'%';
grant usage on *.* to 'keystone'@'localhost'; drop user 'keystone'@'localhost';
flush privileges;
_EOF
mysql -u root -p mysql < ~/etc/clean_os_db.sql
cat > ~/etc/create_os_users.sql << _EOF
grant usage on *.* to 'nova'@'%'; grant usage on *.* to 'nova'@'localhost';
grant usage on *.* to 'glance'@'%'; grant usage on *.* to 'glance'@'localhost';
grant usage on *.* to 'cinder'@'%'; grant usage on *.* to 'cinder'@'localhost';
grant usage on *.* to 'keystone'@'%'; grant usage on *.* to 'keystone'@'localhost';
flush privileges;
_EOF


##
#
su -

##
# Nova set up
openstack-db --service nova --init # Enter the MySQL root password
nova-manage db sync

##
# Glance set up
openstack-db --service glance --init

##
# Cinder (from Folsom) set up
openstack-db --service cinder --init
cinder-manage db sync

##
# QPID
systemctl start qpidd.service && systemctl enable qpidd.service
# systemctl disable qpidd.service

##
# libvirtd
systemctl start libvirtd.service && systemctl enable libvirtd.service
# systemctl disable libvirtd.service

##
# Glance services
for svc in api registry; do systemctl start openstack-glance-$svc.service; done
for svc in api registry; do systemctl enable openstack-glance-$svc.service; done
for svc in api registry; do systemctl status openstack-glance-$svc.service; done
# for svc in api registry; do systemctl disable openstack-glance-$svc.service; done

##
# Cinder volumes (from Folsom)
#
VOL_DIR=/data/virtualisation/volumes
CINDER_VOL_FILE=$VOL_DIR/cinder-volumes.img
mkdir -p $VOL_DIR
truncate --size=20G $CINDER_VOL_FILE

# 1. Temporary solution (not persistent through reboots).
losetup --show -f $CINDER_VOL_FILE
CINDER_VOL_DEVICE=$(losetup -a | grep "$CINDER_VOL_FILE" | cut -d':' -f1)
# losetup -a # To see all the loopback devices
# losetup -d /dev/loop1 # To remove some extra loopback devices
# Because the volume service is dependent on the volume group being available,
# it is not started by default. So, the losetup command has to be re-issued
# after every reboot.

# 2. Permanent solution.
# If you intend to make them persist automatically, then enable the service to start
# in the standard manner, but ensure that the losetup is run early in the boot process,
# or instead, use an implicitly persistent block device/partition. For instance:
LOOP_EXEC_DIR=/usr/libexec/cinder
LOOP_SVC=cinder-demo-disk-image.service
LOOP_EXEC=voladm
GH_SYSD_BASE_URL=https://raw.github.com/denisarnaud/openstack-configuration/master
GH_SYSD_LOOP_SVC_URL=$GH_SYSD_BASE_URL/systemd/$LOOP_SVC
GH_SYSD_LOOP_EXEC_URL=$GH_SYSD_BASE_URL/bin/$LOOP_EXEC
mkdir -p $LOOP_EXEC_DIR
curl $GH_SYSD_LOOP_SVC_URL -o /usr/lib/systemd/system/$LOOP_SVC
curl $GH_SYSD_LOOP_EXEC_URL -o $LOOP_EXEC_DIR/$LOOP_EXEC
chmod -R a+rx $LOOP_EXEC_DIR
systemctl start $LOOP_SVC && systemctl enable $LOOP_SVC
# ln -sf /usr/lib/systemd/system/$LOOP_SVC /etc/systemd/system/multi-user.target.wants/
# systemctl disable $LOOP_SVC
# By construction (hard-coded in the systemd script):
CINDER_VOL_DEVICE=/dev/loop0

# Create the cinder-volumes Volume Group (VG) for the volume service:
vgcreate cinder-volumes $CINDER_VOL_DEVICE

# The Cinder service can now be started:
systemctl start openstack-cinder-volume.service && systemctl enable openstack-cinder-volume.service
#systemctl disable openstack-cinder-volume.service


##
# Nova volume services (deprecated from Folsom: replace by Cinder)
# dd if=/dev/zero of=/var/lib/nova/nova-volumes.img bs=1M seek=20k count=0
# vgcreate nova-volumes $(losetup --show -f /var/lib/nova/nova-volumes.img)

##
# If installing OpenStack without hardware acceleration (e.g., from within a VM)
#openstack-config --set /etc/nova/nova.conf DEFAULT libvirt_type qemu
#setsebool -P virt_use_execmem on # This may take a while

##
# Nova services
for svc in api objectstore compute network volume scheduler cert; do systemctl start openstack-nova-$svc.service; done
for svc in api objectstore compute network volume scheduler cert; do systemctl enable openstack-nova-$svc.service; done
for svc in api objectstore compute network volume scheduler cert; do systemctl status openstack-nova-$svc.service; done
# for svc in api objectstore compute network volume scheduler cert; do systemctl disable openstack-nova-$svc.service; done

##
# Keystone

# Keystone PKI support
midori http://docs.openstack.org/developer/keystone/configuration.html
keystone-manage pki_setup # Only available from Folsom version
chmod g+rx,o+rx /etc/keystone/ssl /etc/keystone/ssl/certs /etc/keystone/ssl/private
chmod g+r,o+r /etc/keystone/ssl/certs/*.* /etc/keystone/ssl/private/*.*

# Keystone database support
openstack-db --service keystone --init

# Keystone configuration file
mkdir -p ~/etc
cat > ~/etc/keystonerc << _EOF
export ADMIN_TOKEN=$(openssl rand -hex 10)
export OS_USERNAME=admin
export OS_PASSWORD=verybadpass
export OS_TENANT_NAME=admin
export OS_AUTH_URL=http://127.0.0.1:5000/v2.0/
export SERVICE_ENDPOINT=http://127.0.0.1:35357/v2.0/
export SERVICE_TOKEN=\$ADMIN_TOKEN
_EOF
cd
ln -s etc/keystonerc
. ~/etc/keystonerc
openstack-config --set /etc/keystone/keystone.conf DEFAULT admin_token $ADMIN_TOKEN

# Keystone service
systemctl start openstack-keystone.service && systemctl enable openstack-keystone.service
# systemctl disable openstack-keystone.service

# Keystone sample data
ADMIN_PASSWORD=$OS_PASSWORD SERVICE_PASSWORD=servicepass openstack-keystone-sample-data

# Test keystone
keystone user-list
keystone role-list
keystone tenant-list
# If the output is made of 'printt' only, apply the patch:
# pushd /usr/lib/python2.7/site-packages
# wget https://github.com/denisarnaud/openstack-configuration/raw/master/keystoneclient-fix-printt.patch
# wget https://github.com/denisarnaud/openstack-configuration/raw/master/novaclient-fix-printt.patch 
# patch -p1 --dry-run < keystoneclient-fix-printt.patch
# patch -p1 < keystoneclient-fix-printt.patch
# patch -p1 --dry-run < novaclient-fix-printt.patch
# patch -p1 < novaclient-fix-printt.patch
# popd
# midori https://bugs.launchpad.net/keystone/+bug/996638
# Then, the process must be restarted from the beginning (wiping out the database)

# Check that the user roles have been set properly
ROLE_ADMIN_ID=$(keystone role-list | awk '/ admin / {print $2}')
ROLE_KS_ADMIN_ID=$(keystone role-list | awk '/ KeystoneAdmin / {print $2}')
ROLE_KSSVC_ADMIN_ID=$(keystone role-list | awk '/ KeystoneServiceAdmin / {print $2}')
ADMIN_USER_ID=$(keystone user-list | awk '/ admin / {print $2}')
ADMIN_TENANT_ID=$(keystone tenant-list | awk '/ admin / {print $2}')
GLANCE_USER_ID=$(keystone user-list | awk '/ glance / {print $2}')
SERVICE_TENANT_ID=$(keystone tenant-list | awk '/ service / {print $2}')
echo "[Roles] ROLE_ADMIN_ID=${ROLE_ADMIN_ID}, ROLE_KS_ADMIN_ID=${ROLE_KS_ADMIN_ID}, ROLE_KSSVC_ADMIN_ID=${ROLE_KSSVC_ADMIN_ID}"
echo "[Users] ADMIN_USER_ID=${ADMIN_USER_ID}, GLANCE_USER_ID=${GLANCE_USER_ID}"
echo "[Tenants] ADMIN_TENANT_ID=${ADMIN_TENANT_ID}, SERVICE_TENANT_ID=${SERVICE_TENANT_ID}"
#
keystone user-role-list --user-id ${ADMIN_USER_ID} --tenant-id ${ADMIN_TENANT_ID}
keystone user-role-list --user-id ${GLANCE_USER_ID} --tenant-id ${SERVICE_TENANT_ID}

# Manually add the user roles, if the above did not work properly
#keystone user-role-add --user-id ${ADMIN_USER_ID} --role-id ${ROLE_ADMIN_ID} --tenant-id ${ADMIN_TENANT_ID}
#keystone user-role-add --user-id ${ADMIN_USER_ID} --role-id ${ROLE_KS_ADMIN_ID} --tenant-id ${ADMIN_TENANT_ID}
#keystone user-role-add --user-id ${ADMIN_USER_ID} --role-id ${ROLE_KSSVC_ADMIN_ID} --tenant-id ${ADMIN_TENANT_ID}
#keystone user-role-add --user-id ${ADMIN_USER_ID} --role-id ${ROLE_ADMIN_ID} --tenant-id ${SERVICE_TENANT_ID}
#keystone user-role-add --user-id ${ADMIN_USER_ID} --role-id ${ROLE_KS_ADMIN_ID} --tenant-id ${SERVICE_TENANT_ID}
#keystone user-role-add --user-id ${ADMIN_USER_ID} --role-id ${ROLE_KSSVC_ADMIN_ID} --tenant-id ${SERVICE_TENANT_ID}
#keystone user-role-add --user-id ${GLANCE_USER_ID} --role-id ${ROLE_ADMIN_ID} --tenant-id ${SERVICE_TENANT_ID} 
#keystone user-role-add --user-id ${GLANCE_USER_ID} --role-id ${ROLE_KS_ADMIN_ID} --tenant-id ${SERVICE_TENANT_ID}
#keystone user-role-add --user-id ${GLANCE_USER_ID} --role-id ${ROLE_KSSVC_ADMIN_ID} --tenant-id ${SERVICE_TENANT_ID}

# Re-check
#keystone user-role-list --user-id ${ADMIN_USER_ID} --tenant-id ${ADMIN_TENANT_ID}
#keystone user-role-list --user-id ${GLANCE_USER_ID} --tenant-id ${SERVICE_TENANT_ID}


##
# Configure nova to use keystone
openstack-config --set /etc/nova/api-paste.ini filter:authtoken admin_tenant_name service
openstack-config --set /etc/nova/api-paste.ini filter:authtoken admin_user nova
openstack-config --set /etc/nova/api-paste.ini filter:authtoken admin_password servicepass
openstack-config --set /etc/nova/nova.conf DEFAULT auth_strategy keystone
for svc in api compute; do systemctl restart openstack-nova-$svc.service; done

# Check that nova talks with keystone
nova flavor-list

##
# Configure glance to use keystone
openstack-config --set /etc/glance/glance-api.conf paste_deploy flavor keystone
openstack-config --set /etc/glance/glance-registry.conf paste_deploy flavor keystone
openstack-config --set /etc/glance/glance-api-paste.ini filter:authtoken admin_tenant_name service
openstack-config --set /etc/glance/glance-api-paste.ini filter:authtoken admin_user glance
openstack-config --set /etc/glance/glance-api-paste.ini filter:authtoken admin_password servicepass
openstack-config --set /etc/glance/glance-registry-paste.ini filter:authtoken admin_tenant_name service
openstack-config --set /etc/glance/glance-registry-paste.ini filter:authtoken admin_user glance
openstack-config --set /etc/glance/glance-registry-paste.ini filter:authtoken admin_password servicepass
for svc in api registry; do systemctl restart openstack-glance-$svc.service; done

# Check that glance talks with keystone
glance index

##
# Nova network
nova-manage network create demonet 10.0.0.0/24 1 256 --bridge=demonetbr0

##
# (Fedora 16/17 64bits) OS image
# Get the image from the Internet
IMG_DIST_TYPE=Fedora
#IMG_DIST_REL=16
IMG_DIST_REL=17
IMG_DIST_FLV=x86_64
IMG_TARGET=openstack
IMG_DISK_TYPE=sda
#IMG_DATE=2012-02-29
IMG_DATE=2012-11-15
IMG_NAME=f${IMG_DIST_REL}-${IMG_DIST_FLV}-${IMG_TARGET}-${IMG_DISK_TYPE}.qcow2
IMG_BASE_URL=http://berrange.fedorapeople.org/images
IMG_URL=${IMG_BASE_URL}/${IMG_DATE}/${IMG_NAME}
IMG_DIR=/data/virtualisation/${IMG_DIST_TYPE}/${IMG_DIST_TYPE}-${IMG_DIST_REL}-${IMG_DIST_FLV}-qcow2
mkdir -p ${IMG_DIR}
pushd ${IMG_DIR}
echo "Downloading the '${IMG_NAME}' ISO image (~250 MB) from ${IMG_BASE_URL}; it may take some time..."
wget ${IMG_URL}
echo "The '${IMG_NAME}' ISO image has been archived into the ${IMG_DIR} directory."
popd
ls -lahF --color ${IMG_DIR}

# Tell glance about the image
glance add name=f${IMG_DIST_REL}-jeos is_public=true disk_format=qcow2 container_format=bare < ${IMG_DIR}/${IMG_NAME}

# Start the network block device (nbd) module
modprobe nbd
echo nbd | sudo tee /etc/modules-load.d/nbd.conf

# Create a key pair
mkdir -p ~/.ssh
chmod 700 ~/.ssh
nova keypair-add mykey > ~/.ssh/id_oskey_demo
chmod 600 ~/.ssh/id_oskey_demo

# Launch the VM instance (JEOS = "Just Enough OS")
GLANCE_IMG_ID=$(glance index | grep f${IMG_DIST_REL}-jeos | awk '{print $1}')
# For the flavor reference, see the result of the 'nova flavor-list' command above
nova boot myserver --flavor 2 --key_name mykey --image ${GLANCE_IMG_ID}

# Other reference documentation
midori https://fedoraproject.org/wiki/QA:Testcase_launch_an_instance_on_OpenStack

# Check that the KVM VM instance is running and that SSH works on it
virsh list
nova list # Wait that the status of myserver switches to ACTIVE (it may take time)
ssh -i ~/.ssh/id_oskey_demo ec2-user@10.0.0.2
# If there is any error, check the log file:
grep -Hin error /var/log/nova/compute.log
# Potentially, restart the nova scheduler:
systemctl restart openstack-nova-scheduler.service
# Check also the logs of the console:
nova console-log myserver
# Eventually, delete the VM
nova delete myserver

##
# Horizon dashboard
systemctl restart httpd.service && systemctl enable httpd.service
# systemctl disable httpd.service
# setsebool -P httpd_can_network_connect=on
midori http://localhost/dashboard &

##
# Swift
#
# Set the keystone Admin token in the swift proxy file
openstack-config --set /etc/swift/proxy-server.conf filter:authtoken admin_token $ADMIN_TOKEN
openstack-config --set /etc/swift/proxy-server.conf filter:authtoken auth_token $ADMIN_TOKEN

# Create the storage device for swift, these instructions use a loopback device
# but a physical device or logical volume can be used
truncate --size=20G /tmp/swiftstorage
SWIFT_DEVICE=$(losetup --show -f /tmp/swiftstorage)
mkfs.ext4 -I 1024 $SWIFT_DEVICE
mkdir -p /srv/node/partitions
mount $SWIFT_DEVICE /srv/node/partitions -t ext4 -o noatime,nodiratime,nobarrier,user_xattr

# Change the working dir so that the following commands will create
# the *.builder files on right place
cd /etc/swift

# Create the ring, with 1024 partitions (only suitable for a small test
# environment) and 1 zone
swift-ring-builder account.builder create 10 1 1
swift-ring-builder container.builder create 10 1 1
swift-ring-builder object.builder create 10 1 1

# Create a device for each of the account, container and object services
swift-ring-builder account.builder add z1-127.0.0.1:6002/partitions 100
swift-ring-builder container.builder add z1-127.0.0.1:6001/partitions 100
swift-ring-builder object.builder add z1-127.0.0.1:6000/partitions 100

# Rebalance the ring (allocates partitions to devices)
swift-ring-builder account.builder rebalance
swift-ring-builder container.builder rebalance
swift-ring-builder object.builder rebalance

# Make sure swift owns appropriate files
chown -R swift:swift /etc/swift /srv/node/partitions

# Added the swift service and endpoint to keystone
keystone  service-create --name=swift --type=object-store --description="Swift Service"
SWIFT_SERVICE_ID=$(keystone service-list | awk '/ swift / {print $2}')
echo $SWIFT_SERVICE_ID # just making sure we got a SWIFT_SERVICE_ID
keystone endpoint-create --service_id $SWIFT_SERVICE_ID \
	--publicurl "http://127.0.0.1:8080/v1/AUTH_\$(tenant_id)s" \
	--adminurl "http://127.0.0.1:8080/v1/AUTH_\$(tenant_id)s" \
	--internalurl "http://127.0.0.1:8080/v1/AUTH_\$(tenant_id)s"

# Start the services
systemctl start memcached.service && systemctl enable memcached.service
# systemctl disable memcached.service
for srv in account container object proxy; do systemctl start openstack-swift-$srv; done
for srv in account container object proxy; do systemctl enable openstack-swift-$srv; done
for srv in account container object proxy; do systemctl status openstack-swift-$srv; done
# for srv in account container object proxy; do systemctl disable openstack-swift-$srv; done

# Test the swift client and upload files
swift list
#swift upload container /path/to/file

##
# Please the following instructions from
midori https://fedoraproject.org/wiki/Getting_started_with_OpenStack_on_Fedora_17#Additional_Functionality



#### ========================================================== ####
##                        Image creation                          ##
#### ========================================================== ####
APPL_DIR=/data/virtualisation/Appliance
APPL_NAME=${IMG_DIST_TYPE}-${IMG_DIST_REL}-${IMG_DIST_FLV}-${IMG_TARGET}
KS_SCRIPT_NAME=${APPL_NAME}.ks
KS_SCRIPT_DIR=./ks
# The following command will take some time (around 20mn with an Internet bandwidth of 300KB/s),
# as it downloads an image of approximately 250MB, then install some updates and do some adjustments.
# The RAW image is installed within a newly created directory, namely ${APPL_NAME}
echo "Downloading the ISO installation media for Fedora ${IMG_DIST_REL} ${IMG_DIST_FLV},"
echo "starting that Fedora distribution within a dedicated KVM-based VM, changing the configuration to have it cloud-ready."
echo "The whole operation may take several tens of minutes..."
appliance-creator --name ${APPL_NAME} --config=${KS_SCRIPT_DIR}/${KS_SCRIPT_NAME}
echo "The configured RAW image will be available within the newly created ${APPL_DIR}/${APPL_NAME} directory."
ls -lahF --color ${APPL_NAME}
echo "Moving that image from the current directory to ${APPL_DIR}/${APPL_NAME}."
echo "Depending on whether the partitions are different and on the image size, it may take a few minutes."
mkdir -p ${APPL_DIR}
\mv -f ${APPL_NAME} ${APPL_DIR}
ls -lahF --color ${APPL_DIR}/${APPL_NAME}
echo "The raw image will now be converted into a QEMU-based one (QCOW2 format). This again may take a few minutes."
qemu-img convert -f raw -c -O qcow2 ${APPL_DIR}/${APPL_NAME}/${APPL_NAME}-${IMG_DISK_TYPE}.raw ${IMG_DIR}/${APPL_NAME}-${IMG_DISK_TYPE}.qcow2
echo "QEMU-based image created in the ${IMG_DIR} directory:"
ls -lahF --color ${IMG_DIR}/${APPL_NAME}-${IMG_DISK_TYPE}.qcow2


#### ========================================================== ####
##                        DeltaCloud                              ##
#### ========================================================== ####

##
# Dependencies
yum -y install deltacloud-core-all rubygem-deltacloud-client


#### ========================================================== ####
##                          DevStack                              ##
#### ========================================================== ####

##
# Documentation
#
midori http://devstack.org/

##
# Dependencies to rebuild OpenStack on Fedora (e.g., for DevStack)
yum install -y bridge-utils curl euca2ools git-core openssh-server psmisc pylint \
	python-netaddr python-pep8 python-pip python-unittest2 python-virtualenv \
	screen tar tcpdump unzip wget libxml2-devel python-argparse python-devel \
	python-eventlet python-greenlet python-paste-deploy python-routes python-sqlalchemy \
	python-wsgiref pyxattr python-greenlet python-lxml python-paste python-paste-deploy \
	python-paste-script python-routes python-setuptools python-sqlalchemy python-sqlite2 \
	python-webob sqlite python-dateutil MySQL-python curl dnsmasq-utils ebtables gawk \
	iptables iputils kpartx kvm libvirt-python libxml2-python m2crypto parted python-boto \
	python-carrot python-cheetah python-eventlet python-feedparser python-gflags \
	python-greenlet python-iso8601 python-kombu python-lockfile python-migrate \
	python-mox python-netaddr python-paramiko python-paste python-paste-deploy \
	python-qpid python-routes python-sqlalchemy python-suds python-tempita sqlite \
	sudo vconfig iscsi-initiator-utils lvm2 genisoimage lvm2 scsi-target-utils \
	numpy Django django-registration gcc pylint python-anyjson python-BeautifulSoup \
	python-boto python-coverage python-dateutil python-eventlet python-greenlet \
	python-httplib2 python-kombu python-migrate python-mox python-netaddr \
	python-nose python-paste python-paste-deploy python-pep8 python-routes \
	python-sphinx python-sqlalchemy python-webob pyxattr

# On the cluster controller
useradd -U -s /bin/bash -m stack
echo "stack ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
passwd stack # stack001
mkdir -p /opt/stack/logs
chown -R stack /opt/stack

# On each node
su - stack
mkdir ~/.ssh; chmod 700 ~/.ssh
echo "ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAqtNdUXbd7L6FoQCtP+NcaAhBf7vq3xxbpUvRoEdbbL30+7DekLQjgkv0v+/aXurfbtRY0shFNCFPyb9CUBX9I12+LaJf58dORXX7CA2PqzilMzjQeFKTelRQv2LxCRD6+ZM23nosW3SBFx0xQLRwJYf5rtjDA2lfK/Jget/ZTPkzGY9J/7so1vLrhiCwX33Bv53KyjnMFaLgwEYw67+LTpnv2icbrASIJr3jF2YBoB/REaBX+h01lwxZFGFFAJxOy0MhCLYrcsZPARKgYdvJMMY/D15/0ciOdAO1reN7qe7iJfIq24bX8TLoUJ7eAo8RKW8acTSu0PEZ+eyO3INqhw== denis.arnaud_fedora@m4x.org" > ~/.ssh/authorized_keys
chmod 600 .ssh/authorized_keys 

# On the cluster controller
su - stack
mkdir -p ~/dev/cloud/openstack
cd ~/dev/cloud/openstack
git clone git://github.com/openstack-dev/devstack.git devstackgit
cd ~/dev/cloud/openstack/devstackgit
cat > localrc << _EOF
HOST_IP=192.168.1.60
FLAT_INTERFACE=p10p1
FIXED_RANGE=10.4.128.0/20
FIXED_NETWORK_SIZE=4096
FLOATING_RANGE=192.168.1.128/25
MULTI_HOST=1
LOGFILE=/opt/stack/logs/stack.sh.log
ADMIN_PASSWORD=labstack
MYSQL_PASSWORD=supersecrete
RABBIT_PASSWORD=supersecrete
SERVICE_PASSWORD=supersecrete
SERVICE_TOKEN=xyzpdqlazydog
_EOF

cat > local.sh << _EOF
#!/usr/bin/env bash

for i in `seq 2 10`
	do /bin/nova-manage fixed reserve 10.4.128.$i
done
_EOF
chmod 775 local.sh


##
# Aeolus
#
midori http://www.aeolusproject.org/use_it.html
yum -y install aeolus-all


