module photon.macos.support;

import core.sys.posix.unistd;
import core.stdc.errno;
import core.stdc.stdlib;
import core.thread;
import core.stdc.config;
import core.sys.posix.pthread;

enum int MSG_DONTWAIT = 0x80;

enum int EV_ADD     = 0x0001;	/* add event to kq (implies enable) */
enum int EV_DELETE  = 0x0002;	/* delete event from kq */
enum int EV_ENABLE  = 0x0004;	/* enable event */
enum int EV_DISABLE = 0x0008;	/* disable event (not reported) */

/* flags */
enum int EV_ONESHOT	= 0x0010;	/* only report one occurrence */
enum int EV_CLEAR	= 0x0020;	/* clear event state after reporting */
enum int EVFILT_READ     =  (-1);
enum int EVFILT_WRITE    =  (-2);
enum int EVFILT_AIO		 =  (-3);	/* attached to aio requests */
enum int EVFILT_VNODE	 =	(-4);	/* attached to vnodes */
enum int EVFILT_PROC	 =	(-5);	    /* attached to struct proc */
enum int EVFILT_SIGNAL	 =	(-6);	/* attached to struct proc */
enum int EVFILT_TIMER	 =	(-7);	/* timers */
enum int EVFILT_MACHPORT =	(-8);	/* Mach ports */
enum int EVFILT_FS		 =  (-9);	    /* Filesystem events */


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

