module photon;

import core.thread;
import core.lifetime;
import std.meta;

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

    this(size_t capacity) {
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
    return cast(shared)Channel!T(capacity);
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



/++
    Multiplex between multiple channels, executes a lambda attached to the first
    channel that becomes ready to read.
+/
void select(Args...)(auto ref Args args)
if (allSatisfy!(isChannel, Even!Args) && allSatisfy!(isHandler, Odd!Args)) {
    void delegate()[args.length/2] handlers = void;
    Event*[args.length/2] events = void;
    static foreach (i, v; args) {
        static if(i % 2 == 0) {
            events[i/2] = &v.buf.rtr;
        }
        else {
            handlers[i/2] = v;
        }
    }
    for (;;) {
        auto n = awaitAny(events[]);
    L_dispatch:
        switch(n) {
            static foreach (i, channel; Even!(args)) {
                case i:
                    if (channel.buf.readyToRead())
                        return handlers[n]();
                    break L_dispatch;
            }
            default:
                assert(0);
        }
    }
}

/// Trait for testing if a type is Channel
enum isChannel(T) = is(T == Channel!(V), V);

enum isHandler(T) = is(T == void delegate());

private template Even(T...) {
    static assert(T.length % 2 == 0);
    static if (T.length > 0) {
        alias Even = AliasSeq!(T[0], Even!(T[2..$]));
    }
    else {
        alias Even = AliasSeq!();
    }
}

private template Odd(T...) {
    static assert(T.length % 2 == 0);
    static if (T.length > 0) {
        alias Odd = AliasSeq!(T[1], Odd!(T[2..$]));
    }
    else {
        alias Odd = AliasSeq!();
    }
}

unittest {
    static assert(Even!(1, 2, 3, 4) == AliasSeq!(1, 3));
    static assert(Odd!(1, 2, 3, 4) == AliasSeq!(2, 4));
    static assert(isChannel!(Channel!int));
    static assert(isChannel!(shared Channel!int));
}