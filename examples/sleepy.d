#!/usr/bin/env dub
/+ dub.json:
    {
	"authors": [
		"Dmitry Olshansky"
	],
	"copyright": "Copyright © 2024, Dmitry Olshansky",
	"dependencies": {
		"photon": { "path": ".." }
	},
	"description": "A test for sleep function interception",
	"license": "BOOST",
	"name": "sleepy"
}
+/
module examples.sleepy;

import std.stdio;
import core.time;
import core.thread;
import photon;


void task(Duration duration) {
    Thread.sleep(duration);
    writeln("Sleep is over");
}

void main() {
    startloop();
    writeln("Starting a bunch of fibers, each waiting 1 second");
    foreach (v; 0..1000)
    {
        go({
            task(1.seconds);
        });
    }
    runFibers();
}
