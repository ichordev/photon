#!/usr/bin/env dub
/+ dub.json:
    {
	    "name" : "semaphore",
        "dependencies": {
		    "photon": { "path" : ".." }
        }
    }
+/
module examples.semaphore;

import std.stdio;
import photon;
import core.thread;
import core.time;

void main() {
    startloop();
    Semaphore sem = Semaphore(0);
    void waitingTask(int n) {
        go({
            writefln("Fiber  #%d started!", n);
            sem.wait();
            writefln("Fiber #%d exited!", n);
        });
    }
    foreach (i; 0..3) {
        waitingTask(i);
    }
    go({
        auto tm = timer();
        writeln("Main fiber started!");
        tm.arm(1000.msecs);
        tm.wait();
        writeln("Releasing two fibers!");
        sem.trigger(2);
        tm.arm(1000.msecs);
        tm.wait();
        writeln("Releasing one fiber!");
        sem.trigger(1);
        writeln("Main fiber exited!");
    });
    runFibers();
    sem.dispose();
}