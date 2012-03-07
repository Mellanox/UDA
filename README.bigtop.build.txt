

================================================
BUILDING HADOOP RPMS (WITH UDA) USING BIGTOP
================================================
Created By: Avner BenHanoch
Date: March 6, 2012
================================================


================================================
*************** build machine ******************
================================================
########DOWNLOAD AND INSTALL COMPONENTS #########
# download and extract bigtop:
	wget -O bigtop-0.2.0-incubating.tar.gz http://apache.spd.co.il//incubator/bigtop/stable/bigtop-0.2.0-incubating.tar.gz
	tar xf bigtop-0.2.0-incubating.tar.gz
	
# Now, we want to perform "make  -C bigtop-0.2.0-incubating/ hadoop-rpm", This will requires the following:
	sudo yum install -y fuse-devel lzo-devel

# lzo-devel will probably requires you to download and install (rpm -ivh) the following:
	wget ftp://ftp.pbone.net/mirror/atrpms.net/el6-x86_64/atrpms/testing/libminilzo2-2.03-6.el6.x86_64.rpm
	wget ftp://ftp.pbone.net/mirror/atrpms.net/el6-x86_64/atrpms/testing/liblzo2_2-2.03-6.el6.x86_64.rpm
	rpm -ivh lib*.rpm

# In addition, bigtop requires forrest 0.8, that in turn requires JAVA 5
# NOTICE: bigtop requires forrest 0.8 - don't use the latest forest!
# download and extract:
	wget http://archive.apache.org/dist/forrest/0.8/apache-forrest-0.8.tar.gz
	tar xf apache-forrest-0.8.tar.gz
	
# NOTICE: forest 0.8 requires JAVA 5 - don't use the latest java (however, you should have JAVA 6 in addition)!
# download, execute (extract), and install:  
-- http://download.oracle.com/otn/java/jdk/1.5.0_22/jdk-1_5_0_22-linux-amd64-rpm.bin #(requires sign in to Oracle)
#then, issue:
	./jdk-1_5_0_22-linux-amd64-rpm.bin
	sudo rpm -ivh jdk-1_5_0_22-linux-amd64-rpm

	
########## CREATE HADOOP RPMS #########
#point to hadoop 1.0.0 (or whatever you want)
	cd /volt/avnerb/workspace/bigtop/bigtop-0.2.0-incubating/  # this is in Avner's env
	vim bigtop.mk
	change:
		HADOOP_BASE_VERSION=0.20.205.0
		HADOOP_PKG_VERSION=0.20.205.0
	to somtheting like:
		HADOOP_BASE_VERSION=1.0.0
		HADOOP_PKG_VERSION=1.0.0
	
# build the RPMs
	export JAVA5_HOME=/usr/java/jdk1.5.0_22/  # this is in Avner's machine
	export JAVA_HOME=/usr/lib64/java/jdk1.6.0_25  # this is in Avner's machine
	export FORREST_HOME=/volt/avnerb/workspace/bigtop/apache-forrest-0.8 #  this is in Avner's machine

	cd /volt/avnerb/workspace/bigtop/bigtop-0.2.0-incubating/  # this is in Avner's env
	make bigtop-utils-rpm
	make hadoop-rpm

================================================
**** customize hadoop's rpms to contain UDA ****
================================================
#go to the dl (download) location
	cd /volt/avnerb/workspace/bigtop/bigtop-0.2.0-incubating/dl
	
untar hadoop-1.0.0.tar.gz 
	tar xf hadoop-1.0.0.tar.gz # it is better to do it in a temp dir

patch the extracted files tree, by putting UDA files in the following places:
	hadoop-1.0.0\lib\native\Linux-amd64-64\
		libhadoopUda.so 
	hadoop-1.0.0\src\mapred\org\apache\hadoop\mapred\
		UdaPlugin.java 
		UdaBridge.java 
		TaskTracker.java
		ReduceTask.java
	hadoop-1.0.0\src\core\org\apache\hadoop\net\
		DNS.java 
	(I also put the following; however, it is possible that this may not be really needed)
	# notice 1.0.0.jar and not 1.0.1.jar 
	hadoop-1.0.0\
		hadoop-core-1.0.0.jar 
	
create hadoop-1.0.0.tar.gz again using the patched files tree
	tar cf hadoop-1.0.0.tar.gz ...

run again:
	make hadoop-rpm
 
================================================
************** target machine ******************
================================================
#PREPARATION 
make sure your NIS don't have the following users/groups (rellevant only if your node uses NIS)
	ypcat passwd | egrep -w 'hadoop|mapred|hdfs'
	ypcat group  | egrep -w 'hadoop|mapred|hdfs'
	(if you have such user/group in the NIS, then rpm installation may succeed; however, errors are expected at runtime, unless rpm installation has permission to modify these NIS entities)

####### INSTALLATION ######## 
	cd /volt/avnerb/workspace/bigtop/bigtop-0.2.0-incubating/output/hadoop/
	sudo rpm -ivh  hadoop-1.0.0-1.x86_64.rpm hadoop-conf-pseudo-1.0.0-1.x86_64.rpm hadoop-datanode-1.0.0-1.x86_64.rpm \
					hadoop-doc-1.0.0-1.x86_64.rpm hadoop-fuse-1.0.0-1.x86_64.rpm hadoop-jobtracker-1.0.0-1.x86_64.rpm \
					hadoop-libhdfs-1.0.0-1.x86_64.rpm hadoop-namenode-1.0.0-1.x86_64.rpm hadoop-native-1.0.0-1.x86_64.rpm \
					hadoop-pipes-1.0.0-1.x86_64.rpm hadoop-sbin-1.0.0-1.x86_64.rpm hadoop-secondarynamenode-1.0.0-1.x86_64.rpm \
					hadoop-tasktracker-1.0.0-1.x86_64.rpm ../bigtop-utils/bigtop-utils-0.2.0.incubating-1.noarch.rpm

	# notice, the user below (hadoop) must matches HADOOP_IDENT_STRING in /etc/default/hadoop (also, I think it should belong to hadoop group)
	sudo adduser hadoop -g hadoop -d /usr/lib/hadoop -c "Hadoop local user"

######## RUN SERVICES ######## 
# prepare the filesystem
	sudo -u hdfs hadoop namenode -format
	sudo -u hdfs hadoop fs -mkdir /user/hadoop
	sudo -u hdfs hadoop fs -chown hadoop /user/hadoop

# DO RUN SERVICES 
#- on 1 node as pseudo cluster (recall that we installed hadoop-conf-pseudo-*.rpm; this took care for conf files)
	for i in hadoop-namenode hadoop-datanode hadoop-jobtracker hadoop-tasktracker ; do sudo service $i start ; done

####### EXECUTE MAPRED JOB !!! ######## 
# run mapred job on the cluster
	hadoop jar /usr/lib/hadoop/hadoop-examples.jar pi 10 1000

	
================================================
************ multi node cluster ****************
================================================

####### TURN ON/OFF HADOOP SERVICES (on each node) ######## 
set which services will be up and which will be down after reboot

to list available hadoop services:
	# chkconfig | grep hadoop

to turn on/off a service (example):
	# sudo chkconfig hadoop-tasktracker <on|off>

(you should decide which service is on and which service is off, based on master/slave role of the node)


####### CONFIGURATION (on each node) ######## 
1st - notice that hadoop configuration uses the alternatives scheme!!!

To add a new custom configuration, run the following commands :
	# sudo cp -r /etc/hadoop/conf.empty /etc/hadoop/conf.my

   This will create a new configuration directory, "/etc/hadoop/conf.my", that serves as a starting point for a new configuration.  
   Edit the configuration files in "/etc/hadoop/conf.my" until you have the configuration you want.

To activate your new configuration:
	# sudo alternatives --install /etc/hadoop/conf hadoop /etc/hadoop/conf.my 90

You can verify your new configuration is active by runnning the following:
	# alternatives --display hadoop
	hadoop - status is auto.
	 link currently points to /etc/hadoop/conf.my
	/etc/hadoop/conf.empty - priority 10
	/etc/hadoop/conf.pseudo - priority 30
	/etc/hadoop/conf.my - priority 90
	Current best version is /etc/hadoop/conf.my.

Then, restart all Hadoop services, for example:
	# sudo /etc/init.d/hadoop-namenode restart


================================================
************ disclaimer ****************
================================================
Notice, that I only reached pseudo cluster mode in which all worked smoothly for me!
I wrote the information on multi node cluster, because I play with it a bit
However, I moved to other task before I have time to play enough with multi node cluster + I didn't run cluster using UDA (but I saw UDA components are installed on my machine)


================================================
********** recomended bibliography *************
================================================
man hadoop (after installing hadoop-1.0.0-1.x86_64.rpm)
https://cwiki.apache.org/BIGTOP/how-to-install-hadoop-distribution-from-bigtop.html
https://github.com/cloudera/bigtop/wiki

