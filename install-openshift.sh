#!/bin/bash

## see: https://youtu.be/aqXSbDZggK4

## Default variables to use
export INTERACTIVE=${INTERACTIVE:="true"}
export PVS=${PVS:="true"}
export DOMAIN=${DOMAIN:="subdomain.domain.com"}

export USERNAME=${USERNAME:="root"}
export PASSWORD=${PASSWORD:="SomeRootPassword"}
export ADMIN_USERNAME=${ADMIN_USERNAME:="regularadminuser"}
export ADMIN_PASSWORD=${ADMIN_PASSWORD:="SomeAdminPassword"}

export VERSION=${VERSION:="3.11"}
export SCRIPT_REPO=${SCRIPT_REPO:="https://raw.githubusercontent.com/okd-community-install/installcentos/master"}
export IP=${IP:="127.0.0.1"}
export API_PORT=${API_PORT:="8443"}

export LOGGING=${LOGGING:="false"}
export METRICS=${METRICS:="True"}

export LETSENCRYPT=${LETSENCRYPT:="false"}
export CLOUDFLARE=${CLOUDFLARE:="false"}
export CF_MAIL=${CF_MAIL:="example@email.com"}
export CF_KEY=${CF_KEY:="xxxxxx"}
export MAIL=${MAIL:="example@email.com"}

# If you created cert before
export DEPLOY_PREPEARED_LETSENCRYPT=${DEPLOY_PREPEARED_LETSENCRYPT:="False"}
export PREPEARED_LETSENCRYPT_CERTFILE=${PREPEARED_LETSENCRYPT_CERTFILE:="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"}
export PREPEARED_LETSENCRYPT_KEYFILE=${PREPEARED_LETSENCRYPT_KEYFILE:="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"}
export PREPEARED_LETSENCRYPT_CAFILE=${PREPEARED_LETSENCRYPT_CAFILE:="/etc/letsencrypt/live/${DOMAIN}/chain.pem"}

## Make the script interactive to set the variables
if [ "$INTERACTIVE" = "true" ]; then
	read -rp "Wildcard Domain to use: ($DOMAIN): " choice;
	if [ "$choice" != "" ] ; then
		export DOMAIN="$choice";
	fi

	read -rp "OpenShift root Username: ($USERNAME): " choice;
	if [ "$choice" != "" ] ; then
		export USERNAME="$choice";
	fi

	read -rp "OpenShift root Password: ($PASSWORD): " choice;
	if [ "$choice" != "" ] ; then
		export PASSWORD="$choice";
	fi

	read -rp "OpenShift admin Username: ($ADMIN_USERNAME): " choice;
	if [ "$choice" != "" ] ; then
		export ADMIN_USERNAME="$choice";
	fi

	read -rp "OpenShift admin Password: ($ADMIN_PASSWORD): " choice;
	if [ "$choice" != "" ] ; then
		export ADMIN_PASSWORD="$choice";
	fi

	read -rp "OpenShift Version: ($VERSION): " choice;
	if [ "$choice" != "" ] ; then
		export VERSION="$choice";
	fi
	read -rp "Single node cluster host IP: ($IP): " choice;
	if [ "$choice" != "" ] ; then
		export IP="$choice";
	fi

	read -rp "API Port: ($API_PORT): " choice;
	if [ "$choice" != "" ] ; then
		export API_PORT="$choice";
	fi

	read -rp "LOGGING: ($LOGGING): " choice;
	if [ "$choice" != "" ] ; then
		export LOGGING="$choice";
	fi

	read -rp "METRICS: ($METRICS): " choice;
	if [ "$choice" != "" ] ; then
		export METRICS="$choice";
	fi

	read -rp "DEPLOY_PREPEARED_LETSENCRYPT: ($DEPLOY_PREPEARED_LETSENCRYPT): " choice;
	if [ "$choice" != "" ] ; then
		export DEPLOY_PREPEARED_LETSENCRYPT="$choice";
	fi

	if [ "$DEPLOY_PREPEARED_LETSENCRYPT" = "true" ]; then

		read -rp "PREPEARED_LETSENCRYPT_CERTFILE: ($PREPEARED_LETSENCRYPT_CERTFILE): " choice;
		if [ "$choice" != "" ] ; then
			export PREPEARED_LETSENCRYPT_CERTFILE="$choice";
		fi

		read -rp "PREPEARED_LETSENCRYPT_KEYFILE: ($PREPEARED_LETSENCRYPT_KEYFILE): " choice;
		if [ "$choice" != "" ] ; then
			export PREPEARED_LETSENCRYPT_KEYFILE="$choice";
		fi

		read -rp "PREPEARED_LETSENCRYPT_CAFILE: ($PREPEARED_LETSENCRYPT_CAFILE): " choice;
		if [ "$choice" != "" ] ; then
			export PREPEARED_LETSENCRYPT_CAFILE="$choice";
		fi


		echo

	fi

	echo

fi

echo "******"
echo "* Your domain is $DOMAIN "
echo "* Your IP is $IP "
echo "* Your root username is $USERNAME "
echo "* Your root password is $PASSWORD "
echo "* OpenShift version: $VERSION "
echo "******"

# install updates
yum update -y

#install epel
yum -y install epel-release

# install the following base packages
yum install -y  wget git vim tmux zile nano net-tools docker-1.13.1\
				bind-utils iptables-services ansible pyOpenSSL \
				bridge-utils bash-completion certbot \
				kexec-tools sos psacct openssl-devel \
				httpd-tools NetworkManager \
				python-cryptography python2-pip python-devel  python-passlib \
				java-1.8.0-openjdk-headless "@Development Tools"

# Disable the EPEL repository globally so that is not accidentally used during later steps of the installation
sed -i -e "s/^enabled=1/enabled=0/" /etc/yum.repos.d/epel.repo

systemctl | grep "NetworkManager.*running"
if [ $? -eq 1 ]; then
	systemctl start NetworkManager
	systemctl enable NetworkManager
fi

[ ! -d openshift-ansible ] && git clone https://github.com/openshift/openshift-ansible.git -b release-${VERSION} --depth=1

# replacing sync.yml with "--insecure" flag to success curl of api server with self-signed certs
rm -f ./openshift-ansible/playbooks/common/openshift-cluster/roles/openshift_node_group/tasks/sync.yml
cp sync.yml ./openshift-ansible/playbooks/common/openshift-cluster/roles/openshift_node_group/tasks/sync.yml

cat <<EOD > /etc/hosts
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
${IP}		$(hostname) console console.${DOMAIN}
EOD

if [ -z $DISK ]; then
	echo "Not setting the Docker storage."
else
	cp /etc/sysconfig/docker-storage-setup /etc/sysconfig/docker-storage-setup.bk

	echo DEVS=$DISK > /etc/sysconfig/docker-storage-setup
	echo VG=DOCKER >> /etc/sysconfig/docker-storage-setup
	echo SETUP_LVM_THIN_POOL=yes >> /etc/sysconfig/docker-storage-setup
	echo DATA_SIZE="100%FREE" >> /etc/sysconfig/docker-storage-setup

	systemctl stop docker

	rm -rf /var/lib/docker
	wipefs --all $DISK
	docker-storage-setup
fi

systemctl restart docker
systemctl enable docker

if [ ! -f ~/.ssh/id_rsa ]; then
	ssh-keygen -q -f ~/.ssh/id_rsa -N ""
	cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
	ssh -o StrictHostKeyChecking=no root@$IP "pwd" < /dev/null
fi

memory=$(cat /proc/meminfo | grep MemTotal | sed "s/MemTotal:[ ]*\([0-9]*\) kB/\1/")

if [ "$memory" -lt "4194304" ]; then
	export METRICS="False"
fi

if [ "$memory" -lt "16777216" ]; then
	export LOGGING="False"
fi

curl -o inventory.download $SCRIPT_REPO/inventory.ini
envsubst < inventory.download > inventory.ini

# Prepeared before certs deploy setup
if [ "$DEPLOY_PREPEARED_LETSENCRYPT" = true ] ;
then

	## Modify inventory.ini
	# Declare usage of Custom Certificate
	# Configure Custom Certificates for the Web Console or CLI => Doesn't Work for CLI
	# Configure a Custom Master Host Certificate
	# Configure a Custom Wildcard Certificate for the Default Router
	# Configure a Custom Certificate for the Image Registry
	## See here for more explanation: https://docs.okd.io/latest/install_config/certificate_customization.html
	cat <<EOT >> inventory.ini

	openshift_master_overwrite_named_certificates=true

	openshift_master_cluster_hostname=console-internal.${DOMAIN}
	openshift_master_cluster_public_hostname=console.${DOMAIN}

	openshift_master_named_certificates=[{"certfile": "${PREPEARED_LETSENCRYPT_CERTFILE}", "keyfile": "${PREPEARED_LETSENCRYPT_KEYFILE}", "cafile": "${PREPEARED_LETSENCRYPT_CAFILE}", "names": ["console.${DOMAIN}"]}]

	openshift_hosted_router_certificate={"certfile": "${PREPEARED_LETSENCRYPT_CERTFILE}", "keyfile": "${PREPEARED_LETSENCRYPT_KEYFILE}", "cafile": "${PREPEARED_LETSENCRYPT_CAFILE}"}

	openshift_hosted_registry_routehost=registry.apps.${DOMAIN}
	openshift_hosted_registry_routecertificates={"certfile": "${PREPEARED_LETSENCRYPT_CERTFILE}", "keyfile": "${PREPEARED_LETSENCRYPT_KEYFILE}", "cafile": "${PREPEARED_LETSENCRYPT_CAFILE}"}
	openshift_hosted_registry_routetermination=reencrypt
EOT

fi

mkdir -p /etc/rhsm/ca
openssl s_client -showcerts -servername registry.access.redhat.com -connect registry.access.redhat.com:443 </dev/null 2>/dev/null | openssl x509 -text > /etc/rhsm/ca/redhat-uep.pem


mkdir -p /etc/origin/master/
touch /etc/origin/master/htpasswd

ansible-playbook -i inventory.ini openshift-ansible/playbooks/prerequisites.yml
ansible-playbook -i inventory.ini openshift-ansible/playbooks/deploy_cluster.yml

htpasswd -b /etc/origin/master/htpasswd ${USERNAME} ${PASSWORD}
oc adm policy add-cluster-role-to-user cluster-admin ${USERNAME}

htpasswd -b /etc/origin/master/htpasswd ${ADMIN_USERNAME} ${ADMIN_PASSWORD}
oc adm policy add-cluster-role-to-user cluster-admin ${ADMIN_USERNAME}

if [ "$PVS" = "true" ]; then

	for i in `seq 1 300`;
	do
		DIRNAME="vol$i"
		mkdir -p /mnt/data/$DIRNAME
		chcon -Rt svirt_sandbox_file_t /mnt/data/$DIRNAME
		chmod 777 /mnt/data/$DIRNAME

		sed "s/name: vol/name: vol$i/g" vol.yaml > oc_vol.yaml
		sed -i "s/path: \/mnt\/data\/vol/path: \/mnt\/data\/vol$i/g" oc_vol.yaml
		oc create -f oc_vol.yaml
		echo "created volume $i"
	done
	rm oc_vol.yaml
fi

echo "******"
echo "* Your console is https://console.$DOMAIN:$API_PORT"
echo "* Your root username is $USERNAME "
echo "* Your root password is $PASSWORD "
echo "*"
echo "* Login using:"
echo "*"
echo "$ oc login -u ${USERNAME} -p ${PASSWORD} https://console.$DOMAIN:$API_PORT/ --insecure-skip-tls-verify"
echo "******"

oc login -u ${USERNAME} -p ${PASSWORD} https://console.$DOMAIN:$API_PORT/ --insecure-skip-tls-verify
