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
        writeln("Main fiber started!");
        Thread.sleep(dur!"msecs"(1000));
        writeln("Releasing two fibers!");
        sem.trigger(2);
        Thread.sleep(dur!"msecs"(1000));
        writeln("Releasing one fiber!");
        sem.trigger(1);
        writeln("Main fiber exited!");
    });
    runFibers();
}