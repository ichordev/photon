module photon;

import core.thread;
import core.lifetime;

import photon.ds.ring_queue;

version(Windows) public import photon.windows.core;
else version(linux) public import photon.linux.core;
else version(freeBSD) public import photon.freebsd.core;
else version(OSX) public import photon.macos.core;
else static assert(false, "Target OS not supported by Photon yet!");

/// Start sheduler and run fibers until all are terminated.
void runFibers()
{
    Thread runThread(size_t n){ // damned D lexical capture "semantics"
        auto t = new Thread(() => schedulerEntry(n));
        t.start();
        return t;
    }
    Thread[] threads = new Thread[scheds.length-1];
    foreach (i; 0..threads.length){
        threads[i] = runThread(i+1);
    }
    schedulerEntry(0);
    foreach (t; threads)
        t.join();
    version(linux) stoploop();
}

struct Channel(T) {
    __gshared RingQueue!(T, Event)* buf;
    __gshared T item;
    bool loaded;

    this(size_t capacity) shared {
        buf = allocRingQueue!T(capacity, event(false), event(false));
    }

    this(this) {
        buf.retain();
    }

    void put(T value) {
        buf.push(move(value));
    }

    void put(T value) shared {
        buf.push(move(value));
    }

    void close() shared {
        buf.close();
    }

    bool empty() {
        if (loaded) return false;
        loaded = buf.tryPop(item);
        return !loaded;
    }

    bool empty() shared {
        if (loaded) return false;
        loaded = buf.tryPop(item);
        return !loaded;
    }

    ref T front() {
        return cast()item;
    }

    ref T front() shared {
        return item;
    }

    void popFront() {
        loaded = false;
    }

    void popFront() shared {
        loaded = false;
    }

    ~this() {
        if (buf) {
            if (buf.release) {
                disposeRingQueue(buf);
                buf = null;
            }
        }
    }
}

/++
    Create ref-counted channel that is safe to shared between multiple fibers.
    In essence it's a multiple producer single consumer queue, that implements
    `OutputRange` and `InputRange` concepts.
+/
auto channel(T)(size_t capacity = 1) {
    return shared(Channel!T)(capacity);
}

unittest {
    import std.range.primitives, std.traits;
    import std.algorithm;
    static assert(isInputRange!(Channel!int));
    static assert(isInputRange!(Unqual!(shared Channel!int)));
    static assert(isOutputRange!(shared Channel!int, int));
    //
    auto ch = channel!int(10);
    foreach (i; 0..10){
        ch.put(i);
    }
    ch.close();
    auto sum = ch.sum;
    assert(sum == 45);
}