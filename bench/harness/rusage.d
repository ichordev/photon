// Runs a process
// dump resource usage of a process
// each ~100ms
// to a rusage.log

import std.process;
import std.stdio, std.format, std.datetime;
import core.thread;

int main(string argv[]) {
    if (argv.length < 2) {
        stderr.writeln("Usage: rusage <command> [args*]");
        return 1;
    }
    File log = File("rusage.log", "w");
    Pid p = spawnProcess(argv[1..$]);
    int id = p.processID;
    string ioPath = format("/proc/%d/io", id);
    string statPath = format("/proc/%d/stat", id);
    char[1024] buf;
    long rd;
    long wr;
    string name;
    writeln("name,read bytes,write bytes,");
    for(;;){
        auto status = tryWait(p);
        if (status.terminated) break;
        File stat = File(statPath, "r");
        File io = File(ioPath, "r");
        io.readf("rchar: %d\nwchar: %d\n", &rd, &wr);
        int _;
        stat.readf("%d (%s) %s", _, name);
        writefln("%s,%d,%d", name, rd, wr);
        Thread.sleep(500.msecs);
    }
    return 0;
}