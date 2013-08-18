#!/bin/bash
function usage {
	echo "this script creates .deb from .rpm. "
	echo "parameters passed:"
	echo "	1. path to rpm"
	echo "	2. path to debian direcory containing necessary files. for example /.autodirect/mtrswgwork/katyak/uda/build/debian"
	echo "	3. path to where the .deb is created"
	echo "	4. a username of a user permitted to create the .deb in the path given"
	echo "script will fail if libaio1 is not installed on the machine(not included in Ubuntu)"
}

if [ -z "$1" ]; then
	usage
	exit 1
fi

if [ -z "$2" ]; then
	usage
	exit 1
fi

if [ -z "$3" ]; then
	usage
	exit 1
fi

if [ -z "$4" ]; then
	usage
	exit 1
fi


#rpm_name="/volt/katyak/rpmbuild/RPMS/x86_64/libuda-3.1.11-0.866.el6.x86_64.rpm"
#pathToDebianDir="/.autodirect/mtrswgwork/katyak/uda/build/debian"

rpm_name=$1
path_debian_dir=$2
path_target_dir=$3
permitted_user=$4

#must make sure rpm is intalled - for queries
sudo apt-get -y install rpm debhelper
#quering the rpm:
version=`rpm -qp --queryformat %{VERSION} $rpm_name`
release=`rpm -qp --queryformat %{RELEASE} $rpm_name`
date=`date -R`
packager=`rpm -qp --queryformat %{PACKAGER} $rpm_name`
summary=`rpm -qp --queryformat %{SUMMARY} $rpm_name`
description=`rpm -qp --queryformat %{DESCRIPTION} $rpm_name`
size_rpm=`rpm -qp --queryformat %{SIZE} $rpm_name`
hostname=`hostname`
rpm_arch=`rpm -qp --queryformat %{ARCH} $rpm_name`
license=`rpm -qp --queryformat %{LICENSE} $rpm_name`
group=`rpm -qp --queryformat %{GROUP} $rpm_name`
if [[ "$rpm_arch" == "x86_64" ]]; then
    debArch="amd64";
elif [[ "$rpm_arch" == "x86" ]]; then
    debArch="i386";
fi


cd /tmp/
rm -rf /tmp/libuda
mkdir /tmp/libuda
#making sure command succeeded
if [ $? -ne 0 ]; then
	echo “CRITICAL: Failed to create new directory!!!”
	exit 1
fi

rpm2cpio $rpm_name | lzma -t -q > /dev/null 2>&1
rpm2cpio $rpm_name | (cd /tmp/libuda;  cpio --extract --make-directories --no-absolute-filenames --preserve-modification-time) 2>&1

cd /tmp/libuda
cp -rf $path_debian_dir ./debian


#replacing variables in ./debian with appropriate values:
cd ./debian
mv changelog changelog.template
mv control control.template
mv copyright copyright.template
#creating a temporary file to store contents of $description
echo $description > description
sed  -e "s/__DEB_UDA_VERSION/${version}/g" -e "s/__DEB_UDA_RELEASE/${release}/g" -e "s/__DEB_UDA_DATE/${date}/g" -e "s/__DEB_UDA_PACKAGER/${packager}/g"  changelog.template > changelog
sed  -e "s/__DEB_UDA_ARCH/${debArch}/g" -e "s/__DEB_UDA_PACKAGER/${packager}/g"  control.template > control
sed  -e "s/__DEB_UDA_VERSION/${version}/g" -e "s/__DEB_UDA_RELEASE/${release}/g" -e "s/__DEB_UDA_DATE/${date}/g" -e "s/__DEB_UDA_ARCH/${debArch}/g" -e "s/__DEB_UDA_PACKAGER/${packager}/g" -e "s/__DEB_UDA_SIZE/${size_rpm}/g"   -e "s/__DEB_UDA_SUMMARY/${summary}/g" -e "s/__DEB_UDA_HOST/${hostname}/g"   -e "s/__DEB_UDA_LICENSE/${license}/g" -e "s/__DEB_UDA_GROUP/${group}/g" copyright.template   > copyright
#workaround since sed does not like \n.
cat control | awk -v temp="`cat description`" 'BEGIN{}($1 !~ "Description"){print $0}($1~"Description"){print $1 " " temp}' > control2
mv control2 control
sed -e $'/DEB_UDA_DESCRIP/{r description\n;d;}' copyright > copyright2
mv copyright2 copyright

rm changelog.template
rm control.template
rm copyright.template
cd ..

./debian/rules binary  2>&1
#rm -rf /tmp/libuda

echo -e "\nSaving the UDA .deb file in ${path_target_dir}..."
sudo -u $permitted_user -H sh -c "cp -f /tmp/*.deb ${path_target_dir}/"
rm -rf /tmp/*.db
echo "Saved!"
