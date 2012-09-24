#!/bin/sh

echo_blue ()
{
    echo -e "\e[00;34m$1\e[00m"
}

echo_red ()
{
    echo -e "\e[00;31m$1\e[00m"
}

echo_blue "The script recieves as a parameter directory to which it checks out trunk and runs a job with coverity test"
echo_blue "The directory should be on NFS: /.autodirect or your home dir"
echo_blue "Once it is finished you should run script gen_coverage.sh on one of the slaves to get the output"
echo_blue "You should export MY_HADOOP_HOME for working/configured hadoop location"


if [[ $@ = *-usage* ]]
then
	exit 0;
fi

# check lcov exists
rpm -q --quiet lcov 
if [ $? != 0 ]; then
	echo_red "Please install lcov"
	echo_red "if running on RH, try run the following:"
	echo_blue "	sudo yum install gd gd-devel"
	echo_blue "	wget dag.wieers.com/redhat/el6/en/x86_64/extras/RPMS/perl-GD-2.45-1.el6.rfx.x86_64.rpm"
	echo_blue "	sudo rpm -ivh perl-GD-2.45-1.el6.rfx.x86_64.rpm"
	echo_blue "	wget ftp://ftp.univie.ac.at/systems/linux/fedora/epel/6/i386/lcov-1.7-1.el6.noarch.rpm"
	echo_blue "	sudo rpm -ivh lcov-1.7-1.el6.noarch.rpm"
	exit 1
fi


if [ -z "$MY_HADOOP_HOME" ]
then
	echo_red "please export MY_HADOOP_HOME for working/configured hadoop location!"
	exit 1
fi


if [ ! -z $1 ] 
then
	home_dir=$1
else
	echo_red "Please pass a directory on NFS"
	exit 1;
fi


# functions
prepare_uda() {
	echo_blue "check out trunk"
	cd $home_dir
	svn co https://sirius.voltaire.com/repos/enterprise/uda/trunk
	cd trunk/src/Merger
	#diff -rupNa reducer_old.cc reducer.cc > for_coverage.patch  #patch creation
	echo_blue "applying patch"
	patch -p0 < ../../scripts/for_coverage.patch | tee /tmp/output.txt
	patch_result=`grep "FAILED" /tmp/output.txt`
	if [ ! -z $patch_result ] 
	then
		echo_red "patch failed!!!"
		exit 1
	fi
	cd ..
	echo_blue "building rpm"
	../build/buildrpm.sh
	set +e
	make clean > /dev/null
	set -e
	./autogen.sh
	CPPFLAGS="--coverage -O0 -g" LIBS="-lgcov" ./configure
	../build/makerpm.sh	
}

install_uda() {
	#removing old rpm
	if rpm -qa | grep -q libuda;
	then
		echo "libuda installed";
		sudo rpm -e libuda;
	fi
	$MY_HADOOP_HOME/bin/slaves.sh sudo rpm -e libuda; 
	currentRpm=`ls -t ~/rpmbuild/RPMS/x86_64/ | grep -m 1 ""`
	echo_blue "installing RPM: $currentRpm"
	#installing new rpm
	sudo rpm -ivh ~/rpmbuild/RPMS/x86_64/$currentRpm
	$MY_HADOOP_HOME/bin/slaves.sh  sudo rpm -ivh ~/rpmbuild/RPMS/x86_64/$currentRpm;
}


run_uda() {
	echo_blue "Running test.."
	cd $MY_HADOOP_HOME
	#runterasort.sh can be replaced by another, more complexed script
	#assuming that all environment variables needed for runterasort.sh are exported
    y | $home_dir/trunk/scripts/runterasort.sh
	#in order to recieve a report, hadoop must be stopped
	echo_blue "stopping hadoop"
	$MY_HADOOP_HOME/bin/stop-all.sh
}

remove_uda() {
	echo_blue "removing rpm"
	sudo rpm -e libuda
	$MY_HADOOP_HOME/bin/slaves.sh sudo rpm -e libuda; 
}

prepare_uda
install_uda
run_uda
remove_uda
