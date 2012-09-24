#!/bin/sh

echo_blue ()
{
    echo -e "\e[00;34m$1\e[00m"
}

echo_red ()
{
    echo -e "\e[00;31m$1\e[00m"
}

echo_blue "The script recieves 2 parameters: "
echo_blue "The first is a number. directory in which the report will be created is called cov_NUMBER"
echo_blue "The second is the same directory which was passed to  gen_coverage_setup.sh"

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

ID=${1:-$$}

TMP_INFO_OUT=cov_tmp_$ID.info
INFO_OUT=cov_$ID.info
HTML_OUT=cov_$ID


if [ ! -z $2 ] 
then
	home_dir=$2/trunk/src/
else
	echo_red "Please pass same directory as you did to gen_coverage_setup.sh"
	exit 1;
fi


cleanup_report() {
	find . -iname "*.gcda" | xargs rm -f
	rm -fr $INFO_OUT
}

generate_report() {
	echo_blue "Generating report.."
	cd $home_dir #compile dir
	#copy gcda&gcno files from .libs directories
	for a in $(find -name .libs -type d ); do 
		mv $a/*.gcda $a/.. ;  
		mv $a/*.gcno $a/.. ;  
	done
	
	lcov -t "uda_coverage" -b $home_dir  -o $TMP_INFO_OUT -c -d . 
	lcov  --remove $TMP_INFO_OUT /usr/include/* /usr/include/c++/4.4.4/* /usr/include/c++/4.4.4/backward/* /usr/include/infiniband/* /usr/include/c++/4.4.4/bits/* \
	    /usr/include/c++/4.4.4/ext/* /usr/include/c++/4.4.4/x86_64-redhat-linux/bits/* /usr/lib64/java/jdk1.6.0_25/include/*  --output $INFO_OUT
	genhtml -o $HTML_OUT $INFO_OUT 
	echo_blue "Results are in $home_dir$HTML_OUT/"
	echo_blue "run: firefox $home_dir$HTML_OUT/index.html"
}


generate_report
cleanup_report


