module photon.windows.core;
version(Windows):
private:

import core.sys.windows.core;
import core.atomic;
import core.internal.spinlock;
import core.stdc.stdlib;
import core.thread;
import std.exception;
import std.windows.syserror;
import std.random;
import std.format;
import photon.ds.intrusive_queue;

// T becomes thread-local b/c it's stolen from shared resource
auto steal(T)(ref shared T arg)
{
    for (;;) {
        auto v = atomicLoad(arg);
        if(cas(&arg, v, cast(shared(T))null)) return v;
    }
}


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
        SetEvent(cast(HANDLE)ev);
    }
    
    HANDLE ev;
}

struct SchedulerBlock {
    shared IntrusiveQueue!(FiberExt, RawEvent) queue;
    shared uint assigned;
    size_t[1] padding;
}
static assert(SchedulerBlock.sizeof == 64);

package(photon) __gshared SchedulerBlock[] scheds;

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

FiberExt currentFiber; 
shared RawEvent termination; // termination event, triggered once last fiber exits
shared HANDLE eventLoop; // event loop, runs outside of D runtime
shared int alive; // count of non-terminated Fibers scheduled
enum int MAX_EVENTS = 500;

public void startloop()
{
    import core.cpuid;
    uint threads = threadsPerCPU;
    scheds = new SchedulerBlock[threads];
    foreach (ref sched; scheds)
        sched = SchedulerBlock();
}


public void go(void delegate() func)
{
    
    // power of 2 random choices:
    size_t a = uniform!"[)"(0, scheds.length);
    size_t b = uniform!"[)"(0, scheds.length);
    uint loadA = scheds[a].assigned; // take into account active queue.size?
    uint loadB = scheds[b].assigned; // ditto
    size_t c = loadA < loadB ? a : b;
    atomicOp!"+="(scheds[c].assigned, 1);
   
    atomicOp!"+="(alive, 1);
}

package(photon) void schedulerEntry(size_t n)
{
    wenforce(SetThreadAffinityMask(GetCurrentThread(), 1L<<n), "failed to set affinity");

}
