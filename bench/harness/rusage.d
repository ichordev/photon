// Runs a process
// dump resource usage of a process
// each ~100ms
// to a rusage.log

import std.exception, std.stdio, std.format, std.string, std.conv, std.datetime, std.process;
import core.thread;
import core.sys.posix.unistd;
import core.sys.posix.signal;

struct Stats {
    SysTime dt;
    string name;
    ulong rbytes, wbytes; // read/write(-ish) syscalls
    ulong stime, utime; // CPU time in clock ticks
    ulong rss; // resident memory pages
}

shared int targetPid;

extern(C) void signal_handler(int sig, siginfo_t*, void*)
{
    kill(targetPid, sig);
    _exit(9);
}

Stats statsOf(SysTime dt, int pid) {
    string ioPath = format("/proc/%d/io", pid);
    string statPath = format("/proc/%d/stat", pid);
    long rd;
    long wr;
    File stat = File(statPath, "r");
    File io = File(ioPath, "r");
    io.readf("rchar: %d\nwchar: %d\n", &rd, &wr);
    int _;
    string name, rest;
    stat.readf("%d (%s) %s", _, name, rest);
    string[] fields = rest.split(" ");
    ulong stime = fields[11].to!ulong;
    ulong utime = fields[12].to!ulong;
    ulong rss = fields[21].to!ulong;
    return Stats(dt, name, rd, wr, stime, utime, rss);
}

int main(string[] argv) {
    if (argv.length < 2) {
        stderr.writeln("Usage: rusage <command> [args*]");
        return 1;
    }
    double MB = 1024.0 * 1024.0;
    File log = File("rusage.log", "w");
    Pid p = spawnProcess(argv[1..$]);
    double pageSize = 1.0*sysconf(_SC_PAGE_SIZE);
    double tickSize = 1.0*sysconf(_SC_CLK_TCK);
    targetPid = p.processID;
    sigaction_t action;
    action.sa_sigaction = &signal_handler;
    enforce(sigaction(SIGTERM, &action, null) >= 0);
    enforce(sigaction(SIGINT, &action, null) >= 0);
    writeln("name,read(MB),written(MB),kernel cpu time(sec),user cpu time(sec),RSS(MB)");
    for(;;) {
        auto status = tryWait(p);
        if (status.terminated) break;
        SysTime dt = Clock.currTime;
        auto stats = statsOf(dt, targetPid);
        writefln("%s,%s,%f,%f,%f,%f,%f", 
            dt.toISOExtString, stats.name,
            stats.rbytes / MB,
            stats.wbytes / MB,
            stats.stime / tickSize,
            stats.utime / tickSize, 
            stats.rss*pageSize / MB
        );
        Thread.sleep(200.msecs);
    }
    return 0;
}
