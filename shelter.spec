Name:      shelter
Version:   %{rpm_version}
Release:   %{rpm_release}
Summary:   Shell-based testing framework
URL:       https://github.com/node13h/shelter
License:   MIT
BuildArch: noarch
Source0:   %{sdist_tarball}

%description
A library for shell-based testing scripts

%prep
%setup -n %{sdist_dir}

%clean
rm -rf --one-file-system --preserve-root -- "%{buildroot}"

%install
make install DESTDIR="%{buildroot}" PREFIX="%{prefix}"

%files
%{_bindir}/*
%{_defaultdocdir}/*
%{_mandir}/*
