
%define lib_target  %{_libdir}
%define jar_target  %{_libexecdir}
%define conf_target /etc

%define lib_file  libuda.so
%define jar_file  hadoop-test-1.0.2.jar
%define conf_file mapred-site.xml


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


Name:           uda
Version:        2.5
Release:        1%{?dist}
Summary:        Mellanox UDA (Hadoop Accelaration)

#Group:          
License:        Mellanox
#URL:            
Source0:        %{lib_file}
Source1:        %{jar_file}
Source2:        %{conf_file}
#change-log
#license/eula





BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
#BuildArch:      noarch

#BuildRequires:  
#Requires:       

%description
Mellanox UDA (Hadoop Accelaration)

%prep
#%setup -q


%build

%install
#rm -rf $RPM_BUILD_ROOT
#make install DESTDIR=$RPM_BUILD_ROOT
rm -rf $RPM_BUILD_ROOT
mkdir -p $RPM_BUILD_ROOT%{lib_target}
mkdir -p $RPM_BUILD_ROOT%{jar_target}
mkdir -p $RPM_BUILD_ROOT%{conf_target}

install -m 0755 %{SOURCE0} $RPM_BUILD_ROOT%{lib_target}/%{lib_file}
install -m 0644 %{SOURCE1} $RPM_BUILD_ROOT%{jar_target}/%{jar_file}
install -m 0644 %{SOURCE2} $RPM_BUILD_ROOT%{conf_target}/%{conf_file}

%clean
rm -rf $RPM_BUILD_ROOT


%files
%defattr(-,root,root,-)
%doc
%{lib_target}/%{lib_file}
%{jar_target}/%{jar_file}
%{conf_target}/%{conf_file}

%changelog
