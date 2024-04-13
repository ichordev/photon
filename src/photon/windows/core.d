module photon.windows.core;
version(Windows):
private:

import core.sys.windows.core;
import core.sys.windows.winsock2;
import core.atomic;
import core.thread;
import std.exception;
import std.windows.syserror;
import std.random;
import std.stdio;

import photon.ds.intrusive_queue;
import photon.windows.support;

shared struct RawEvent {
nothrow:
    this(bool signaled) {
        ev = cast(shared(HANDLE))CreateEventA(null, FALSE, signaled, null);
        assert(ev != null, "Failed to create RawEvent");
    }

    void waitAndReset() {
        auto ret = WaitForSingleObject(cast(HANDLE)ev, INFINITE);
        assert(ret == WAIT_OBJECT_0, "Failed while waiting on event");
    }
    
    void trigger() { 
        auto ret = SetEvent(cast(HANDLE)ev);
        assert(ret != 0);
    }
    
    HANDLE ev;
}

struct SchedulerBlock {
    shared IntrusiveQueue!(FiberExt, RawEvent) queue;
    shared uint assigned;
    size_t[1] padding;
}
static assert(SchedulerBlock.sizeof == 64);

class FiberExt : Fiber { 
    FiberExt next;
    uint numScheduler;
    int bytesTransfered;

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

package(photon) shared SchedulerBlock[] scheds;

FiberExt currentFiber; 
__gshared RawEvent termination; // termination event, triggered once last fiber exits
__gshared HANDLE iocp; // IO Completion port
shared int alive; // count of non-terminated Fibers scheduled


public void startloop() {
    SYSTEM_INFO info;
    GetSystemInfo(&info);
    // TODO: handle NUMA case
    uint threads = info.dwNumberOfProcessors;
    scheds = new SchedulerBlock[threads];
    foreach(ref sched; scheds) {
        sched.queue = IntrusiveQueue!(FiberExt, RawEvent)(RawEvent(0));
    }
    termination = RawEvent(false);
    iocp = CreateIoCompletionPort(cast(HANDLE)INVALID_HANDLE_VALUE, null, 0, 1);
    wenforce(iocp != null, "Failed to create IO Completion Port");
    wenforce(CreateThread(null, 0, &eventLoop, null, 0, null) != null, "Failed to start event loop");
}


public void go(void delegate() func) {
    import std.random;
    uint choice;
    if (scheds.length == 1) choice = 0;
    else {
        uint a = uniform!"[)"(0, cast(uint)scheds.length);
        uint b = uniform!"[)"(0, cast(uint)scheds.length-1);
        if (a == b) b = cast(uint)scheds.length-1;
        uint loadA = scheds[a].assigned;
        uint loadB = scheds[b].assigned;
        if (loadA < loadB) choice = a;
        else choice = b;
    }
    atomicOp!"+="(scheds[choice].assigned, 1);
    atomicOp!"+="(alive, 1);
    auto f = new FiberExt(func, choice);
    logf("Assigned %x -> %d scheduler", cast(void*)f, choice);
    f.schedule();
}

package(photon) void schedulerEntry(size_t n)
{
    // TODO: handle NUMA case
    wenforce(SetThreadAffinityMask(GetCurrentThread(), 1L<<n), "failed to set affinity");
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
    foreach (ref s; scheds) {
        s.queue.event.trigger();
    }
}

enum int MAX_COMPLETIONS = 500;

extern(Windows) uint eventLoop(void* param) {
    HANDLE[2] events;
    events[0] = iocp;
    events[1] = cast(HANDLE)termination.ev;
    for (;;) {
        auto ret = WaitForMultipleObjects(2, events.ptr, FALSE, INFINITE);
        if (ret == WAIT_OBJECT_0) { // iocp
            OVERLAPPED_ENTRY[MAX_COMPLETIONS] entries = void;
            uint count = 0;
            while(GetQueuedCompletionStatusEx(iocp, entries.ptr, MAX_COMPLETIONS, &count, 0, FALSE)) {
                logf("Dequeued I/O events=%d", count);
                foreach (e; entries[0..count]) {
                    FiberExt fiber = *cast(FiberExt*)&e.lpCompletionKey;
                    fiber.bytesTransfered = cast(int)e.dwNumberOfBytesTransferred;
                    fiber.schedule();
                }
                if (count < MAX_COMPLETIONS) break;
            }
        }
        else if (ret == WAIT_OBJECT_0 + 1) { // termination
            break;
        }
        else {
            logf("Failed to wait for multiple objects: %x", ret);
            break;
        }
    }
    ExitThread(0);
    return 0;
}


// ===========================================================================
// INTERCEPTS
// ===========================================================================

extern(Windows) SOCKET socket(int af, int type, int protocol) {
    logf("Intercepted socket!");
    SOCKET s = WSASocketW(af, type, protocol, null, 0, WSA_FLAG_OVERLAPPED);
    registerSocket(s);
    return s;
}

void registerSocket(SOCKET s) {
    HANDLE port = iocp;
    wenforce(CreateIoCompletionPort(cast(void*)s, port, cast(size_t)cast(void*)currentFiber, 0) == port, "failed to register I/O completion");
}

extern(Windows) int recv(SOCKET s, void* buf, int len, int flags) {
    OVERLAPPED overlapped;
    WSABUF wsabuf = WSABUF(cast(uint)len, buf);
    
    int ret = WSARecv(s, &wsabuf, 1, null, cast(uint*)&flags, cast(LPWSAOVERLAPPED)&overlapped, null);
    logf("Got recv %d error: %d", ret, GetLastError());
    if (ret >= 0) {
        return ret;
    }
    else {
        FiberExt.yield();
        return currentFiber.bytesTransfered;
    }
}
