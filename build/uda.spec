#
# Copyright (C) 2012 Auburn University
# Copyright (C) 2012 Mellanox Technologies
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at:
#  
# http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, 
# either express or implied. See the License for the specific language 
# governing permissions and  limitations under the License.
#
# 

%define uda_dir  %{_libdir}/uda
#%define doc_dir  /usr/share/doc/%{name}-%{version}/
%define doc_dir  %{uda_dir}

%define uda_lib                 libuda.so
%define uda_hadoop_1x_v3_jar    uda-hadoop-1.x-v3.jar
%define uda_hadoop_1x_v2_jar    uda-hadoop-1.x-v2.jar
%define uda_hadoop_1x_v1_jar    uda-hadoop-1.x-v1.jar
%define uda_hadoop_1x_cdh42_jar uda-hadoop-1.x-cdh-4.2.jar
%define uda_hadoop_3x_jar       uda-hadoop-3.x.jar
%define uda_hadoop_2x_jar       uda-hadoop-2.x.jar
%define uda_readme              README
%define uda_lic                 LICENSE.txt
%define uda_utils               utils.tgz
%define uda_source              source.tgz
%define uda_journal             journal.txt

%define hname hadoop
%define hadoop_name hadoop
%define etc_hadoop /etc/%{hname}
%define config_hadoop %{etc_hadoop}/conf
%define lib_hadoop_dirname /usr/lib
%define lib_hadoop %{lib_hadoop_dirname}/%{hname}
%define log_hadoop_dirname /var/log
%define log_hadoop %{log_hadoop_dirname}/%{hname}
%define bin_hadoop %{_bindir}
%define man_hadoop %{_mandir}
%define src_hadoop /usr/src/%{hname}
%define hadoop_username mapred
%define hadoop_services namenode secondarynamenode datanode jobtracker tasktracker
# Hadoop outputs built binaries into %{hadoop_build}
%define hadoop_build_path build
%define static_images_dir src/webapps/static/images

%ifarch i386
%global hadoop_arch Linux-i386-32
%endif
%ifarch amd64 x86_64
%global hadoop_arch Linux-amd64-64
%endif


Name:           libuda
#3.0.3 structure change
Version:        %{_uda_version}
Release:        %{_uda_fix}.%{_revision}%{?dist}

Summary:        libuda is an RDMA plugin for Hadoop Acceleration
Vendor:         Mellanox
Packager:       Avner BenHanoch <avnerb@mellanox.com>
License:        Apache License v2.0


#change-log
#license/eula

Group:          Acceleration
URL:            http://www.mellanox.com/
Source0:        %{uda_lib}
Source1:        %{uda_hadoop_1x_v2_jar}
Source2:        %{uda_readme}
Source3:        %{uda_lic}
Source4:        %{uda_utils}
Source5:        %{uda_hadoop_2x_jar}
Source7:        %{uda_hadoop_3x_jar}
Source8:        %{uda_source}
Source9:        %{uda_journal}
Source10:       %{uda_hadoop_1x_v1_jar}
Source11:       %{uda_hadoop_1x_cdh42_jar}
Source12:       %{uda_hadoop_1x_v3_jar}

BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
#BuildArch:      noarch

#BuildRequires:  
Requires:       librdmacm, libibverbs


%description
Mellanox UDA, a software plugin, accelerates Hadoop network and improves
the scaling of Hadoop clusters executing data analytics intensive applications.
A novel data moving protocol which uses RDMA in combination with an efficient 
merge-sort algorithm enables Hadoop clusters based on Mellanox InfiniBand and 
10GbE and 40GbE RoCE (RDMA over Converged Ethernet) adapter cards to efficiently 
move data between servers accelerating the Hadoop framework.
Mellanox UDA is collaboratively developed with Auburn University.  

#%prep
#%setup -q


#%build

%install

rm -rf $RPM_BUILD_ROOT
%__install -d -m 0755 $RPM_BUILD_ROOT%{uda_dir}
%__install -d -m 0755 $RPM_BUILD_ROOT%{doc_dir}

install -m 0755 %{SOURCE0} $RPM_BUILD_ROOT%{uda_dir}/%{uda_lib}
install -m 0644 %{SOURCE1} $RPM_BUILD_ROOT%{uda_dir}/%{uda_hadoop_1x_v2_jar}
install -m 0644 %{SOURCE2} $RPM_BUILD_ROOT%{doc_dir}/%{uda_readme}
install -m 0644 %{SOURCE3} $RPM_BUILD_ROOT%{doc_dir}/%{uda_lic}
install -m 0644 %{SOURCE4} $RPM_BUILD_ROOT%{uda_dir}/%{uda_utils}
install -m 0644 %{SOURCE5} $RPM_BUILD_ROOT%{uda_dir}/%{uda_hadoop_2x_jar}
install -m 0644 %{SOURCE7} $RPM_BUILD_ROOT%{uda_dir}/%{uda_hadoop_3x_jar}
install -m 0644 %{SOURCE8} $RPM_BUILD_ROOT%{doc_dir}/%{uda_source}
install -m 0644 %{SOURCE9} $RPM_BUILD_ROOT%{doc_dir}/%{uda_journal}
install -m 0644 %{SOURCE10} $RPM_BUILD_ROOT%{uda_dir}/%{uda_hadoop_1x_v1_jar}
install -m 0644 %{SOURCE11} $RPM_BUILD_ROOT%{uda_dir}/%{uda_hadoop_1x_cdh42_jar}
install -m 0644 %{SOURCE12} $RPM_BUILD_ROOT%{uda_dir}/%{uda_hadoop_1x_v3_jar}

%post
(cd %{uda_dir}; tar -xf %{uda_utils})
(cd %{uda_dir}; ln  -sf %{uda_hadoop_1x_v2_jar} uda-hadoop-1.x.jar )

%postun
[ ! -z "$1" ] && [ $1 -le 0 ] && rm -rf %{uda_dir} || true

%clean
rm -rf $RPM_BUILD_ROOT


%files
%defattr(-,root,root,-)
%doc
%{uda_dir}/%{uda_lib}
%{uda_dir}/%{uda_hadoop_2x_jar}
%{uda_dir}/%{uda_hadoop_1x_v2_jar}
%{doc_dir}/%{uda_readme}
%{doc_dir}/%{uda_lic}
%{uda_dir}/%{uda_utils}
%{uda_dir}/%{uda_hadoop_3x_jar}
%{doc_dir}/%{uda_source}
%{doc_dir}/%{uda_journal}
%{uda_dir}/%{uda_hadoop_1x_v1_jar}
%{uda_dir}/%{uda_hadoop_1x_cdh42_jar}
%{uda_dir}/%{uda_hadoop_1x_v3_jar}

%changelog
