module photon.support;

version(linux) public import photon.linux.support;
else version(FreeBSD) public import photon.freebsd.support;
else version(OSX) public import photon.macos.support;
else version(Windows) public import photon.windows.support;
