
%define lib_target  %{_libdir}
%define uda_dirname  /usr/uda

#%define uda_lib   libuda.so
%define uda_lib   libhadoopUda.so
%define uda_jar   uda.jar
%define uda_xml   mapred-site.xml
%define uda_inst  install-uda.sh
%define uda_env   uda-env.sh

# %define uda_env_str export HADOOP_CLASSPATH=\$HADOOP_CLASSPATH:{uda_dirname}/%{uda_jar}


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
Release:        1%{?dist}
Summary:        libuda is an RDMA plugin for Hadoop Acceleration
Vendor:         Mellanox

Group:          Acceleration
License:        Mellanox
URL:            http://www.mellanox.com/
Source0:        %{uda_lib}
Source1:        %{uda_jar}
Source2:        %{uda_xml}
Source3:        %{uda_inst}
Source4:        %{uda_env}
#change-log
#license/eula





BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
#BuildArch:      noarch

#BuildRequires:  
#Requires:       

%description
Mellanox UDA, a software plugin, accelerates Hadoop network and improves
the scaling of Hadoop clusters executing data analytics intensive applications.
A novel data moving protocol which uses RDMA in combination with an efficient 
merge-sort algorithm enables Hadoop clusters based on Mellanox InfiniBand and 
10GbE and 40GbE RoCE (RDMA over Converged Ethernet) adapter cards to efficiently 
move data between servers accelerating the Hadoop framework.
Mellanox UDA is collaboratively developed with Auburn University.  

%prep
#%setup -q


%build

%install
#rm -rf $RPM_BUILD_ROOT
#make install DESTDIR=$RPM_BUILD_ROOT


rm -rf $RPM_BUILD_ROOT
%__install -d -m 0755 $RPM_BUILD_ROOT%{lib_target}
%__install -d -m 0755 $RPM_BUILD_ROOT%{uda_dirname}

install -m 0755 %{SOURCE0} $RPM_BUILD_ROOT%{lib_target}/%{uda_lib}
install -m 0644 %{SOURCE1} $RPM_BUILD_ROOT%{uda_dirname}/%{uda_jar}
install -m 0644 %{SOURCE2} $RPM_BUILD_ROOT%{uda_dirname}/%{uda_xml}
install -m 0755 %{SOURCE3} $RPM_BUILD_ROOT%{uda_dirname}/%{uda_inst}
install -m 0644 %{SOURCE4} $RPM_BUILD_ROOT%{uda_dirname}/%{uda_env}

# echo export HADOOP_CLASSPATH=\$HADOOP_CLASSPATH:{uda_dirname}/%{uda_jar} > $RPM_BUILD_ROOT%{uda_dirname}/%{uda_inst}
# echo %{uda_env_str} > $RPM_BUILD_ROOT%{uda_dirname}/%{uda_inst}


%post
bash $RPM_BUILD_ROOT%{uda_dirname}/%{uda_inst} \
  --distro-dir=$RPM_SOURCE_DIR \
  --build-dir=$PWD/build/%{name}-%{version} \
  --src-dir=$RPM_BUILD_ROOT%{src_hadoop} \
  --lib-dir=$RPM_BUILD_ROOT%{lib_hadoop} \
  --system-lib-dir=%{_libdir} \
  --etc-dir=$RPM_BUILD_ROOT%{etc_hadoop} \
  --prefix=$RPM_BUILD_ROOT \
  --doc-dir=$RPM_BUILD_ROOT%{doc_hadoop} \
  --native-build-string=%{hadoop_arch} \
  --installed-lib-dir=%{lib_hadoop} \
  --uda-dir=%{uda_dirname} \
  --uda-hadoop-conf-dir=$UDA_HADOOP_CONF_DIR \


#--uda-hadoop-conf-dir=/etc/hadoop/conf \
#--uda-hadoop-conf-dir=$UDA_HADOOP_CONF_DIR \


%postun
# rm -rf %{uda_dirname}

%clean
rm -rf $RPM_BUILD_ROOT


%files
%defattr(-,root,root,-)
%doc
%{lib_target}/%{uda_lib}
%{uda_dirname}/%{uda_jar}
%{uda_dirname}/%{uda_xml}
%{uda_dirname}/%{uda_inst}
%{uda_dirname}/%{uda_env}

%changelog
