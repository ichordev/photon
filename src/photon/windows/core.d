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


struct SchedulerBlock
{
    AlignedSpinLock lock; // lock around the queue
    UMS_COMPLETION_LIST* completionList;
    RingQueue!(UMS_CONTEXT*) queue; // queue has the number of outstanding threads
    shared uint assigned; // total assigned UMS threads

    this(int size)
    {
        lock = AlignedSpinLock(SpinLock.Contention.brief);
        queue = RingQueue!(UMS_CONTEXT*)(size);
        wenforce(CreateUmsCompletionList(&completionList), "failed to create UMS completion");
    }
}

package(photon) __gshared SchedulerBlock[] scheds;
shared uint activeThreads;
size_t schedNum; // (TLS) number of scheduler

struct Functor
{
	void delegate() func;
}

public void startloop()
{
    import core.cpuid;
    uint threads = threadsPerCPU;
    scheds = new SchedulerBlock[threads];
    foreach (ref sched; scheds)
        sched = SchedulerBlock(100_000);
}

extern(Windows) uint worker(void* func)
{
    auto functor = *cast(Functor*)func;
    functor.func();
    return 0;
}

public void spawn(void delegate() func)
{
    ubyte[128] buf = void;
    size_t size = buf.length;
    PROC_THREAD_ATTRIBUTE_LIST* attrList = cast(PROC_THREAD_ATTRIBUTE_LIST*)buf.ptr;
    wenforce(InitializeProcThreadAttributeList(attrList, 1, 0, &size), "failed to initialize proc thread");
    scope(exit) DeleteProcThreadAttributeList(attrList);
    
    UMS_CONTEXT* ctx;
    wenforce(CreateUmsThreadContext(&ctx), "failed to create UMS context");

    // power of 2 random choices:
    size_t a = uniform!"[)"(0, scheds.length);
    size_t b = uniform!"[)"(0, scheds.length);
    uint loadA = scheds[a].assigned; // take into account active queue.size?
    uint loadB = scheds[b].assigned; // ditto
    if (loadA < loadB) atomicOp!"+="(scheds[a].assigned, 1);
    else atomicOp!"+="(scheds[b].assigned, 1);
    UMS_CREATE_THREAD_ATTRIBUTES umsAttrs;
    umsAttrs.UmsCompletionList = loadA < loadB ? scheds[a].completionList : scheds[b].completionList;
    umsAttrs.UmsContext = ctx;
    umsAttrs.UmsVersion = UMS_VERSION;

    wenforce(UpdateProcThreadAttribute(attrList, 0, PROC_THREAD_ATTRIBUTE_UMS_THREAD, &umsAttrs, umsAttrs.sizeof, null, null), "failed to update proc thread");
    HANDLE handle = wenforce(CreateRemoteThreadEx(GetCurrentProcess(), null, 0, &worker, new Functor(func), 0, attrList, null), "failed to create thread");
    atomicOp!"+="(activeThreads, 1);
}

package(photon) void schedulerEntry(size_t n)
{
    schedNum = n;
    UMS_SCHEDULER_STARTUP_INFO info;
    info.UmsVersion = UMS_VERSION;
    info.CompletionList = scheds[n].completionList;
    info.SchedulerProc = &umsScheduler;
    info.SchedulerParam = null;
    wenforce(SetThreadAffinityMask(GetCurrentThread(), 1<<n), "failed to set affinity");
    wenforce(EnterUmsSchedulingMode(&info), "failed to enter UMS mode\n");
}

extern(Windows) VOID umsScheduler(UMS_SCHEDULER_REASON Reason, ULONG_PTR ActivationPayload, PVOID SchedulerParam)
{
    UMS_CONTEXT* ready;
    auto completionList = scheds[schedNum].completionList;
       logf("-----\nGot scheduled, reason: %d, schedNum: %x\n"w, Reason, schedNum);
    if(!DequeueUmsCompletionListItems(completionList, 0, &ready)){
        logf("Failed to dequeue ums workers!\n"w);
        return;
    }    
    for (;;)
    {
      scheds[schedNum].lock.lock();
      auto queue = &scheds[schedNum].queue; // struct, so take a ref
      while (ready != null)
      {
          logf("Dequeued UMS thread context: %x\n"w, ready);
          queue.push(ready);
          ready = GetNextUmsListItem(ready);
      }
      scheds[schedNum].lock.unlock();
      while(!queue.empty)
      {
        UMS_CONTEXT* ctx = queue.pop;
        logf("Fetched thread context from our queue: %x\n", ctx);
        BOOLEAN terminated;
        uint size;
        if(!QueryUmsThreadInformation(ctx, UMS_THREAD_INFO_CLASS.UmsThreadIsTerminated, &terminated, BOOLEAN.sizeof, &size))
        {
            logf("Query UMS failed: %d\n"w, GetLastError());
            return;
        }
        if (!terminated)
        {
            auto ret = ExecuteUmsThread(ctx);
            if (ret == ERROR_RETRY) // this UMS thread is locked, try it later
            {
                logf("Need retry!\n");
                queue.push(ctx);
            }
            else
            {
                logf("Failed to execute thread: %d\n"w, GetLastError());
                return;
            }
        }
        else
        {
            logf("Terminated: %x\n"w, ctx);
            //TODO: delete context or maybe cache them somewhere?
            DeleteUmsThreadContext(ctx);
            atomicOp!"-="(scheds[schedNum].assigned, 1);
            atomicOp!"-="(activeThreads, 1);
        }
      }
      if (activeThreads == 0)
      {
          logf("Shutting down\n"w);
          return;
      }
      if(!DequeueUmsCompletionListItems(completionList, INFINITE, &ready))
      {
           logf("Failed to dequeue UMS workers!\n"w);
           return;
      }
    }
}
