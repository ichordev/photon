// Performs multiple runs of weighttp tool
// varying the concurency range in steps
// Inspired by GWAN benchmark tool (ab.c)

module http_load;

import core.cpuid, core.thread;
import std.getopt, std.array, std.algorithm, std.numeric,
    std.conv, std.datetime, std.exception,
    std.stdio, std.process, std.regex;

void usage() {
    stderr.writeln("Usage: http_load START-STOP:STEP REQ[A]xRUNS http://server[:port]/path");
}

long fromMetric(string num) {
    assert(num.length > 0);
    long mult;
    switch(num[$-1]){
    case 'm':
        mult = 1_000_000;
        num = num[0..$-1];
        break;
    case 'k':
        mult = 1_000;
        num = num[0..$-1];
        break;
    default:
        mult = 1;
    }
    return mult * num.to!long;
}

int main(string[] argv) { 
    bool trace = false;
    getopt(argv,
        "v", &trace
    );
    if (argv.length < 4) {
        usage();
        return 1;
    }
    auto m = matchFirst(argv[1], `^(\d+(?:[km]?))-(\d+(?:[km]?)):(\d+(?:[km]?))$`);
    if (!m) {
        stderr.writeln("Can't parse 'range' argument:", argv[1]);
        usage();
        return 1;
    }
    string url = argv[3];
    long start = fromMetric(m[1]);
    long stop = fromMetric(m[2]);
    long step = fromMetric(m[3]);
    auto m2 = matchFirst(argv[2], `^(\d+(?:[km]?))([A]?)x(\d+)$`);
    if (!m2) {
        stderr.writeln("Can't parse 'runs' argument:", argv[2]);
        usage();
        return 1;
    }
    int numThreads = coresPerCPU;
    long req = fromMetric(m2[1]);
    bool keepAlive = m2[2] == "A";
    int runs = m2[3].to!int;
    writefln("time,concurrency,RPS(min),RPS(avg),RPS(max),errors(max)");
    for(long c = start; c <= stop; c += step) {
        c = c / step * step; // truncate to step
        if (c < numThreads) c = numThreads;     
        auto dt = Clock.currTime();   
        long[] rps = new long[runs];
        long[] errors = new long[runs];
        foreach(r; 0..runs) {
            auto cmd = ["weighttp", "-c", c.to!string, "-t", numThreads.to!string, "-n", req.to!string, url];
            if (keepAlive) cmd.insertInPlace(1, "-k");
            if(trace) stderr.writeln(cmd.join(" "));
            auto pipes = pipeProcess(cmd);
            foreach (line; pipes.stdout.byLine) {
                auto result = matchFirst(line, `finished in .*?, (\d+) req/s`);
                if(result) {
                    rps[r] = result[1].to!long;
                }
                result = matchFirst(line, `requests: .*? (\d+) failed, (\d+) errored`);
                if (result) {
                    errors[r] = result[1].to!long + result[2].to!long;
                }
            }
            if (wait(pipes.pid)) {
                stderr.writeln("weighttp failed, stopping benchmark");
                return 1;
            }
        }
        writefln("%s,%d,%d,%d,%d,%d",
            dt.toISOExtString, c, reduce!(min)(rps), mean(rps).to!long, reduce!max(rps), reduce!max(errors));
        stdout.flush();
        Thread.sleep(100.msecs);
    }
    return 0;
}
