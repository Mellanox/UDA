
%define lib_target  %{_libdir}
%define uda_dir  %{_libdir}/uda
%define doc_dir  /usr/share/doc/%{name}-%{version}/

#%define uda_lib   libuda.so
%define uda_lib    libhadoopUda.so
%define uda_jar    uda.jar
%define uda_readme README
%define uda_lic    LICENSE.txt


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
Version:        3.0.0
Release:        4%{?dist}
Summary:        libuda is an RDMA plugin for Hadoop Acceleration
Vendor:         Mellanox
Packager:       Avner BenHanoch <avnerb@mellanox.com>
License:        Apache License v2.0


#change-log
#license/eula

Group:          Acceleration
URL:            http://www.mellanox.com/
Source0:        %{uda_lib}
Source1:        %{uda_jar}
Source2:        %{uda_readme}
Source3:        %{uda_lic}




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
%__install -d -m 0755 $RPM_BUILD_ROOT%{lib_target}
%__install -d -m 0755 $RPM_BUILD_ROOT%{uda_dir}
%__install -d -m 0755 $RPM_BUILD_ROOT%{doc_dir}

install -m 0755 %{SOURCE0} $RPM_BUILD_ROOT%{lib_target}/%{uda_lib}
install -m 0644 %{SOURCE1} $RPM_BUILD_ROOT%{uda_dir}/%{uda_jar}
install -m 0644 %{SOURCE2} $RPM_BUILD_ROOT%{doc_dir}/%{uda_readme}
install -m 0644 %{SOURCE3} $RPM_BUILD_ROOT%{doc_dir}/%{uda_lic}


#%post

#%postun

%clean
rm -rf $RPM_BUILD_ROOT


%files
%defattr(-,root,root,-)
%doc
%{lib_target}/%{uda_lib}
%{uda_dir}/%{uda_jar}
%{doc_dir}/%{uda_readme}
%{doc_dir}/%{uda_lic}

%changelog
