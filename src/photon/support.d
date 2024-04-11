module photon.support;

import core.sys.posix.unistd;
import core.stdc.errno;
import core.stdc.stdlib;
import core.sys.posix.pthread;

version(linux) public import photon.linux.support;
else version(FreeBSD) public import photon.freebsd.support;
else version(OSX) public import photon.macos.support;