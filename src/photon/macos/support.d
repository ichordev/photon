module photon.macos.support;

import core.sys.posix.unistd;
import core.stdc.errno;
import core.stdc.stdlib;
import core.thread;
import core.stdc.config;
import core.sys.posix.pthread;

enum int MSG_DONTWAIT = 0x80;

extern(C) void perror(const(char) *s) nothrow;

T checked(T: ssize_t)(T value, const char* msg="unknown place") nothrow {
    if (value < 0) {
        perror(msg);
        _exit(cast(int)-value);
    }
    return value;
}

ssize_t withErrorno(ssize_t resp) nothrow {
    if(resp < 0) {
        //logf("Syscall ret %d", resp);
        errno = cast(int)-resp;
        return -1;
    }
    else {
        return resp;
    }
}

void logf(string file = __FILE__, int line = __LINE__, T...)(string msg, T args)
{
    debug(photon) {
        try {
            import std.stdio;
            stderr.writefln(msg, args);
            stderr.writefln("\tat %s:%s:[LWP:%s]", file, line, pthread_self());
        }
        catch(Throwable t) {
            abort();
        }
    }
}

