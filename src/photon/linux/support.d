module photon.linux.support;

import core.sys.posix.unistd;
import core.sys.linux.timerfd;
import core.stdc.errno;
import core.thread;

import photon.linux.syscalls;

enum int MSG_DONTWAIT = 0x40;
enum int SOCK_NONBLOCK = 0x800;

extern(C) int eventfd(uint initial, int flags) nothrow;
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
    debug {
        import std.stdio;
        stderr.writefln(msg, args);
        stderr.writefln("\tat %s:%s:[LWP:%s]", file, line, pthread_self());
    }
}

shared struct Event {
nothrow:
    this(int init) {
        fd = eventfd(init, 0);
    }

    void waitAndReset() {
        ubyte[8] bytes = void;
        ssize_t r;
        do {
            r = raw_read(fd, bytes.ptr, 8);
        } while(r < 0 && errno == EINTR);
        r.checked("event reset");
    }
    
    void trigger() { 
        union U {
            ulong cnt;
            ubyte[8] bytes;
        }
        U value;
        value.cnt = 1;
        ssize_t r;
        do {
            r = raw_write(fd, value.bytes.ptr, 8);
        } while(r < 0 && errno == EINTR);
        r.checked("event trigger");
    }
    
    int fd;
}

struct Timer {
nothrow:
    private int timerfd;

    void init() {
        timerfd = timerfd_create(CLOCK_MONOTONIC, TFD_NONBLOCK | TFD_CLOEXEC).checked;
    }

    int fd() {
        return timerfd;
    }

    static void ms2ts(timespec *ts, ulong ms)
    {
        ts.tv_sec = ms / 1000;
        ts.tv_nsec = (ms % 1000) * 1000000;
    }

    void arm(int timeout) {
        timespec ts_timeout;
        ms2ts(&ts_timeout, timeout); //convert miliseconds to timespec
        itimerspec its;
        its.it_value = ts_timeout;
        its.it_interval.tv_sec = 0;
        its.it_interval.tv_nsec = 0;
        timerfd_settime(timerfd, 0, &its, null);
    }

    void disam() {
        itimerspec its; // zeros
        timerfd_settime(timerfd, 0, &its, null);
    }

    void dispose() { 
        close(timerfd).checked;
    }
}
