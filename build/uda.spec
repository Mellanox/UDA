
%define uda_dir  %{_libdir}/uda
%define doc_dir  /usr/share/doc/%{name}-%{version}/

%define uda_lib   				libuda.so
%define uda_hadoop_1x_jar    	uda-hadoop-1.x.jar
%define uda_CDH3u4_jar    		uda-CDH3u4.jar
%define uda_0_20_2_jar    		uda-hadoop-0.20.2.jar
%define uda_readme 				README
%define uda_lic    				LICENSE.txt
%define hadoop_prop_script    	set_hadoop_slave_property.sh

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
#3.0.1 for patch v2 after comuunity (Arun) comments
Version:        3.0.1
Release:        4297%{?dist}
Summary:        libuda is an RDMA plugin for Hadoop Acceleration
Vendor:         Mellanox
Packager:       Avner BenHanoch <avnerb@mellanox.com>
License:        Apache License v2.0


#change-log
#license/eula

Group:          Acceleration
URL:            http://www.mellanox.com/
Source0:        %{uda_lib}
Source1:        %{uda_hadoop_1x_jar}
Source2:        %{uda_readme}
Source3:        %{uda_lic}
Source4:        %{hadoop_prop_script}
Source5:        %{uda_CDH3u4_jar}
Source6:        %{uda_0_20_2_jar}

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
install -m 0644 %{SOURCE1} $RPM_BUILD_ROOT%{uda_dir}/%{uda_hadoop_1x_jar}
install -m 0644 %{SOURCE2} $RPM_BUILD_ROOT%{doc_dir}/%{uda_readme}
install -m 0644 %{SOURCE3} $RPM_BUILD_ROOT%{doc_dir}/%{uda_lic}
install -m 0755 %{SOURCE4} $RPM_BUILD_ROOT%{uda_dir}/%{hadoop_prop_script}
install -m 0644 %{SOURCE5} $RPM_BUILD_ROOT%{uda_dir}/%{uda_CDH3u4_jar}
install -m 0644 %{SOURCE6} $RPM_BUILD_ROOT%{uda_dir}/%{uda_0_20_2_jar}

#%post

#%postun

%clean
rm -rf $RPM_BUILD_ROOT


%files
%defattr(-,root,root,-)
%doc
%{uda_dir}/%{uda_lib}
%{uda_dir}/%{uda_CDH3u4_jar}
%{uda_dir}/%{uda_0_20_2_jar}
%{uda_dir}/%{uda_hadoop_1x_jar}
%{doc_dir}/%{uda_readme}
%{doc_dir}/%{uda_lic}
%{uda_dir}/%{hadoop_prop_script}

%changelog
