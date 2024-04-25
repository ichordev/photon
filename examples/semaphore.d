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
    go({
        writeln("First fiber started!");
        sem.wait();
        writeln("First fiber exited!");
    });
    go({
        writeln("Second fiber started!");
        sem.wait();
        writeln("Second fiber exited!");
    });
    go({
        writeln("Main fiber started!");
        Thread.sleep(dur!"msecs"(1000));
        writeln("Releasing one fiber!");
        sem.trigger(1);
        Thread.sleep(dur!"msecs"(1000));
        writeln("Releasing one fiber!");
        sem.trigger(1);
        writeln("Main fiber exited!");
    });
    runFibers();
}