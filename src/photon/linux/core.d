module photon.linux.core;
private:

import std.stdio;
import std.string;
import std.format;
import std.exception;
import std.conv;
import std.array;
import core.thread;
import core.sys.posix.sys.types;
import core.sys.posix.sys.socket;
import core.sys.posix.poll;
import core.sys.posix.netinet.in_;
import core.sys.posix.unistd;
import core.sys.linux.epoll;
import core.sys.linux.timerfd;
import core.sync.mutex;
import core.stdc.errno;
import core.atomic;
import core.sys.posix.stdlib: abort;
import core.sys.posix.fcntl;
import core.memory;
import core.sys.posix.sys.mman;
import core.sys.posix.pthread;
import core.sys.linux.sys.signalfd;
import core.sys.linux.sched;

import photon.linux.support;
import photon.linux.syscalls;
import photon.ds.common;
import photon.ds.intrusive_queue;

class FiberExt : Fiber { 
    FiberExt next;
    uint numScheduler;

    enum PAGESIZE = 4096;
    
    this(void function() fn, uint numSched) nothrow {
        super(fn);
        numScheduler = numSched;
    }

    this(void delegate() dg, uint numSched) nothrow {
        super(dg);
        numScheduler = numSched;
    }

    void schedule() nothrow
    {
        scheds[numScheduler].queue.push(this);
    }
}

FiberExt currentFiber; 
shared Event termination; // termination event, triggered once last fiber exits
shared pthread_t eventLoop; // event loop, runs outside of D runtime
shared int alive; // count of non-terminated Fibers scheduled

struct SchedulerBlock {
    shared IntrusiveQueue!(FiberExt, Event) queue;
    shared uint assigned;
    size_t[2] padding;
}
static assert(SchedulerBlock.sizeof == 64);

package(photon) shared SchedulerBlock[] scheds;

enum int MAX_EVENTS = 500;
enum int SIGNAL = 42;

package(photon) void schedulerEntry(size_t n)
{
    int tid = gettid();
    cpu_set_t mask;
    CPU_SET(n, &mask);
    sched_setaffinity(tid, mask.sizeof, &mask).checked("sched_setaffinity");
    shared SchedulerBlock* sched = scheds.ptr + n;
    while (alive > 0) {
        sched.queue.event.waitAndReset();
        for(;;) {
            FiberExt f = sched.queue.drain();
            if (f is null) break; // drained an empty queue, time to sleep
            do {
                auto next = f.next; //save next, it will be reused on scheduling
                currentFiber = f;
                logf("Fiber %x started", cast(void*)f);
                try {
                    f.call();
                }
                catch (Exception e) {
                    stderr.writeln(e);
                    atomicOp!"-="(alive, 1);
                }
                if (f.state == FiberExt.State.TERM) {
                    logf("Fiber %s terminated", cast(void*)f);
                    atomicOp!"-="(alive, 1);
                }
                f = next;
            } while(f !is null);
        }
    }
    termination.trigger();
}

public void spawn(void delegate() func) {
    import std.random;
    uint a = uniform!"[)"(0, cast(uint)scheds.length);
    uint b = uniform!"[)"(0, cast(uint)scheds.length-1);
    if (a == b) b = cast(uint)scheds.length-1;
    uint loadA = scheds[a].assigned;
    uint loadB = scheds[b].assigned;
    uint choice;
    if (loadA < loadB) choice = a;
    else choice = b;
    atomicOp!"+="(scheds[choice].assigned, 1);
    atomicOp!"+="(alive, 1);
    auto f = new FiberExt(func, choice);
    f.schedule();
}

shared Descriptor[] descriptors;
shared int event_loop_fd;
shared int signal_loop_fd;

enum ReaderState: uint {
    EMPTY = 0,
    UNCERTAIN = 1,
    READING = 2,
    READY = 3
}

enum WriterState: uint {
    READY = 0,
    UNCERTAIN = 1,
    WRITING = 2,
    FULL = 3
}

// list of awaiting fibers
shared struct Descriptor {
    ReaderState _readerState;   
    FiberExt _readerWaits;
    WriterState _writerState;
    FiberExt _writerWaits;
    bool intercepted;
    bool isSocket;
nothrow:
    ReaderState readerState()() {
        return atomicLoad(_readerState);
    }

    WriterState writerState()() {
        return atomicLoad(_writerState);
    }

    // try to change state & return whatever it happend to be in the end
    bool changeReader()(ReaderState from, ReaderState to) {
        return cas(&_readerState, from, to);
    }

    // ditto for writer
    bool changeWriter()(WriterState from, WriterState to) {
        return cas(&_writerState, from, to);
    }

    //
    shared(FiberExt) readWaiters()() {
        return atomicLoad(_readerWaits);
    }

    //
    shared(FiberExt) writeWaiters()(){
        return atomicLoad(_writerWaits);
    }

    // try to enqueue reader fiber given old head
    bool enqueueReader()(shared(FiberExt) head, shared(FiberExt) fiber) {
        fiber.next = head;
        return cas(&_readerWaits, head, fiber);
    }

    // try to enqueue writer fiber given old head
    bool enqueueWriter()(shared(FiberExt) head, shared(FiberExt) fiber) {
        fiber.next = head;
        return cas(&_writerWaits, head, fiber);
    }

    // try to schedule readers - if fails - someone added a reader, it's now his job to check state
    void scheduleReaders()() {
        auto w = readWaiters;
        if (w && cas(&_readerWaits, w, cast(shared)null)) {
            auto wu = w.unshared;
            while(wu.next) {
                wu.schedule();
                wu = wu.next;
            }
            wu.schedule();
        }
    }

    // try to schedule writers, ditto
    void scheduleWriters()() {
        auto w = writeWaiters;
        if (w && cas(&_writerWaits, w, cast(shared)null)) {
            auto wu = w.unshared;
            while(wu.next) {
                wu.schedule();
                wu = wu.next;
            }
            wu.schedule();
        }
    }
}

enum Fcntl { no, yes }
enum SyscallKind { accept, read, write }

// intercept - a filter for file descriptor, changes flags and register on first use
void interceptFd(Fcntl needsFcntl)(int fd) nothrow {
    logf("Hit interceptFD");
    if (fd < 0 || fd >= descriptors.length) return;
    if (cas(&descriptors[fd].intercepted, false, true)) {
        logf("First use, registering fd = %d", fd);
        static if(needsFcntl == Fcntl.yes) {
            int flags = fcntl(fd, F_GETFL, 0);
            fcntl(fd, F_SETFL, flags | O_NONBLOCK).checked;
        }
        epoll_event event;
        event.events = EPOLLIN | EPOLLOUT | EPOLLET;
        event.data.fd = fd;
        if (epoll_ctl(event_loop_fd, EPOLL_CTL_ADD, fd, &event) < 0 && errno == EPERM) {
            logf("Detected real file FD, switching from epoll to aio");
            descriptors[fd].isSocket = false;
        }
        else {
            logf("isSocket = true");
            descriptors[fd].isSocket = true;
        }
        descriptors[fd].intercepted = true;
    }
    int flags = fcntl(fd, F_GETFL, 0);
    if (!(flags & O_NONBLOCK)) {
        logf("WARNING: Socket (%d) not set in O_NONBLOCK mode!", fd);
    }
}

void deregisterFd(int fd) nothrow {
    if(fd >= 0 && fd < descriptors.length) {
        auto descriptor = descriptors.ptr + fd;
        atomicStore(descriptor._writerState, WriterState.READY);
        atomicStore(descriptor._readerState, ReaderState.EMPTY);
        descriptor.scheduleReaders();
        descriptor.scheduleWriters();
        atomicStore(descriptor.intercepted, false);
    }
}

extern(C) void graceful_shutdown_on_signal(int, siginfo_t*, void*)
{
    version(photon_tracing) printStats();
    _exit(9);
}

version(photon_tracing) 
void printStats()
{
    // TODO: report on various events in eventloop/scheduler
    string msg = "Tracing report:\n\n";
    write(2, msg.ptr, msg.length);
}

public void startloop()
{
    import core.cpuid;
    uint threads = threadsPerCPU;

    event_loop_fd = cast(int)epoll_create1(0).checked("ERROR: Failed to create event-loop!");
    // use RT signals, disable default termination on signal received
    sigset_t mask;
    sigemptyset(&mask);
    sigaddset(&mask, SIGNAL);
    pthread_sigmask(SIG_BLOCK, &mask, null).checked;
    signal_loop_fd = cast(int)signalfd(-1, &mask, 0).checked("ERROR: Failed to create signalfd!");

    epoll_event event;
    event.events = EPOLLIN;
    event.data.fd = signal_loop_fd;
    epoll_ctl(event_loop_fd, EPOLL_CTL_ADD, signal_loop_fd, &event).checked;

    termination = Event(0);
    event.events = EPOLLIN;
    event.data.fd = termination.fd;
    epoll_ctl(event_loop_fd, EPOLL_CTL_ADD, termination.fd, &event).checked;

    {
        
        sigaction_t action;
        action.sa_sigaction = &graceful_shutdown_on_signal;
        sigaction(SIGTERM, &action, null).checked;
    }

    ssize_t fdMax = sysconf(_SC_OPEN_MAX).checked;
    descriptors = (cast(shared(Descriptor*)) mmap(null, fdMax * Descriptor.sizeof, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0))[0..fdMax];
    scheds = new SchedulerBlock[threads];
    foreach(ref sched; scheds) {
        sched.queue = IntrusiveQueue!(FiberExt, Event)(Event(0));
    }
    eventLoop = pthread_create(cast(pthread_t*)&eventLoop, null, &processEventsEntry, null);
}

void stoploop()
{
    void* ret;
    pthread_join(eventLoop, &ret);
}

extern(C) void* processEventsEntry(void*)
{
    for (;;) {
        epoll_event[MAX_EVENTS] events = void;
        signalfd_siginfo[20] fdsi = void;
        int r;
        do {
            r = epoll_wait(event_loop_fd, events.ptr, MAX_EVENTS, -1);
        } while (r < 0 && errno == EINTR);
        checked(r);
        for (int n = 0; n < r; n++) {
            int fd = events[n].data.fd;
            if (fd == termination.fd) {
                foreach(ref s; scheds) s.queue.event.trigger();
                return null;
            }
            else if (fd == signal_loop_fd) {
                logf("Intercepted our aio SIGNAL");
                ssize_t r2 = raw_read(signal_loop_fd, &fdsi, fdsi.sizeof);
                logf("aio events = %d", r2 / signalfd_siginfo.sizeof);
                if (r2 % signalfd_siginfo.sizeof != 0)
                    checked(r2, "ERROR: failed read on signalfd");

                for(int i = 0; i < r2 / signalfd_siginfo.sizeof; i++) { //TODO: stress test multiple signals
                    logf("Processing aio event idx = %d", i);
                    if (fdsi[i].ssi_signo == SIGNAL) {
                        logf("HIT our SIGNAL");
                        auto fiber = cast(FiberExt)cast(void*)fdsi[i].ssi_ptr;
                        fiber.schedule();
                    }
                }
            }
            else {
                logf("Event for fd=%d", fd);
                auto descriptor = descriptors.ptr + fd;
                if (events[n].events & EPOLLIN) {
                    auto state = descriptor.readerState;
                    logf("state = %d", state);
                    final switch(state) with(ReaderState) { 
                        case EMPTY:
                            descriptor.changeReader(EMPTY, READY);
                            descriptor.scheduleReaders();
                            break;
                        case UNCERTAIN:
                            descriptor.changeReader(UNCERTAIN, READY);
                            break;
                        case READING:
                            if (!descriptor.changeReader(READING, UNCERTAIN)) {
                                if (descriptor.changeReader(EMPTY, UNCERTAIN)) // if became empty - move to UNCERTAIN and wake readers
                                    descriptor.scheduleReaders();
                            }
                            break;
                        case READY:
                            break;
                    }
                    logf("Awaits %x", cast(void*)descriptor.readWaiters);
                }
                if (events[n].events & EPOLLOUT) {
                    auto state = descriptor.writerState;
                    logf("state = %d", state);
                    final switch(state) with(WriterState) { 
                        case FULL:
                            descriptor.changeWriter(FULL, READY);
                            descriptor.scheduleWriters();
                            break;
                        case UNCERTAIN:
                            descriptor.changeWriter(UNCERTAIN, READY);
                            break;
                        case WRITING:
                            if (!descriptor.changeWriter(WRITING, UNCERTAIN)) {
                                if (descriptor.changeWriter(FULL, UNCERTAIN)) // if became empty - move to UNCERTAIN and wake writers
                                    descriptor.scheduleWriters();
                            }
                            break;
                        case READY:
                            break;
                    }
                    logf("Awaits %x", cast(void*)descriptor.writeWaiters);
                }
            }
        }
    }
}

// ======================================================================================
// SYSCALL warappers intercepts
// ======================================================================================

extern(C) ssize_t read(int fd, void *buf, size_t count) nothrow
{
    return universalSyscall!(SYS_READ, "READ", SyscallKind.read, Fcntl.yes, EWOULDBLOCK)
        (fd, cast(size_t)buf, count);
}

extern(C) ssize_t write(int fd, const void *buf, size_t count)
{
    return universalSyscall!(SYS_WRITE, "WRITE", SyscallKind.write, Fcntl.yes, EWOULDBLOCK)
        (fd, cast(size_t)buf, count);
}

extern(C) ssize_t accept(int sockfd, sockaddr *addr, socklen_t *addrlen)
{
    return universalSyscall!(SYS_ACCEPT, "accept", SyscallKind.accept, Fcntl.yes, EWOULDBLOCK)
        (sockfd, cast(size_t) addr, cast(size_t) addrlen);    
}

extern(C) ssize_t accept4(int sockfd, sockaddr *addr, socklen_t *addrlen, int flags)
{
    return universalSyscall!(SYS_ACCEPT4, "accept4", SyscallKind.accept, Fcntl.yes, EWOULDBLOCK)
        (sockfd, cast(size_t) addr, cast(size_t) addrlen, flags);
}

extern(C) ssize_t connect(int sockfd, const sockaddr *addr, socklen_t *addrlen)
{
    return universalSyscall!(SYS_CONNECT, "connect", SyscallKind.accept, Fcntl.yes, EINPROGRESS)
        (sockfd, cast(size_t) addr, cast(size_t) addrlen);
}

extern(C) ssize_t sendto(int sockfd, const void *buf, size_t len, int flags,
                      const sockaddr *dest_addr, socklen_t addrlen)
{
    return universalSyscall!(SYS_SENDTO, "sendto", SyscallKind.read, Fcntl.no, EWOULDBLOCK)
        (sockfd, cast(size_t) buf, len, flags, cast(size_t) dest_addr, cast(size_t) addrlen);
}

extern(C) size_t recv(int sockfd, void *buf, size_t len, int flags) nothrow {
    sockaddr_in src_addr;
    src_addr.sin_family = AF_INET;
    src_addr.sin_port = 0;
    src_addr.sin_addr.s_addr = htonl(INADDR_ANY);
    ssize_t addrlen = sockaddr_in.sizeof;
    return recvfrom(sockfd, buf, len, flags, cast(sockaddr*)&src_addr, &addrlen);   
}

extern(C) private ssize_t recvfrom(int sockfd, void *buf, size_t len, int flags,
                        sockaddr *src_addr, ssize_t* addrlen) nothrow
{
    return universalSyscall!(SYS_RECVFROM, "RECVFROM", SyscallKind.read, Fcntl.no, EWOULDBLOCK)
        (sockfd, cast(size_t)buf, len, flags, cast(size_t)src_addr, cast(size_t)addrlen);
}

extern(C) private int poll(pollfd *fds, nfds_t nfds, int timeout)
{
    /*if (currentFiber is null) {
        logf("POLL PASSTHROUGH!");
        return cast(int)syscall(SYS_POLL, cast(size_t)fds, cast(size_t)nfds, timeout).withErrorno;
    }
    else {
        logf("HOOKED POLL");
        if (timeout <= 0) return sys_poll(fds, nfds, timeout);

        foreach (ref fd; fds[0..nfds]) {
            interceptFd(fd.fd);
            descriptors[fd.fd].unshared.blockFiber(currentFiber, fd.events);
        }
        TimerFD tfd = timerFdPool.getObject();
        int timerfd = tfd.getFD();
        tfd.armTimer(timeout);
        interceptFd(timerfd);
        descriptors[timerfd].unshared.blockFiber(currentFiber, EPOLLIN);
        Fiber.yield();

        timerFdPool.releaseObject(tfd);
        foreach (ref fd; fds[0..nfds]) {
            descriptors[fd.fd].unshared.removeFiber(currentFiber);
        }

        return sys_poll(fds, nfds, 0);
    }*/
    abort();
    return 0;
}

extern(C) private ssize_t close(int fd) nothrow
{
    logf("HOOKED CLOSE!");
    deregisterFd(fd);
    return cast(int)withErrorno(syscall(SYS_CLOSE, fd));
}
