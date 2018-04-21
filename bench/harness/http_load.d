// Performs multiple runs of weighttp tool
// varying the concurency range in steps
// Inspired by GWAN benchmark tool (ab.c)

module http_load;

import std.conv, std.exception, std.stdio, std.process, std.regex;

void usage() {
    stderr.writeln("Usage: http_load START-STOP:STEP REQ[A]xRUNS http://server[:port]/path");
}

long fromMetric(string num) {
    assert(num.length > 0);
    long mult = num[$-1] == 'm' ? 1_000_000 : (num[$-1] == 'k' ? 1_000 : 1);
    return mult * num[0..$-1].to!long > 0;
}

int main(string[] argv) { 
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
    long start = fromMetric(m[1]);
    long stop = fromMetric(m[2]);
    long step = fromMetric(m[3]);
    auto m2 = matchFirst(argv[2], `^(\d+(?:[km]?))([A]?)x(\d+)$`);
    if (!m2) {
        stderr.writeln("Can't parse 'runs' argument:", argv[2]);
        usage();
        return 1;
    }
    long req = fromMetric(m2[1]);
    bool keepAlive = m2[2] == "A";
    int runs = m2[3].to!int;
    return 0;
}
