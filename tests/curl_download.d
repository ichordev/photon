import std.net.curl, std.string, std.datetime.stopwatch, std.range, std.stdio;
import std.file : remove;
import core.thread;
import photon;

immutable urls = [
	"https://github.com/DmitryOlshansky/jsm4s/releases/download/v1.4.1/jsm4s-1.4.1.jar",
	/*"https://github.com/DmitryOlshansky/jsm4s/releases/download/v.1.4.0/jsm4s-v.1.4.0.jar",
	"https://github.com/DmitryOlshansky/jsm4s/releases/download/v1.3.0/jsm4s-1.3.0.jar"*/
];

void main(){
	startloop();
	void spawnDownload(string url, string file) {
		spawn(() => download(url, file));
	}
	StopWatch sw;
	sw.start();
	foreach(url; urls) {
		download(url, url.split('/').back);
	}
	sw.stop();
	writefln("Sequentially: %s ms", sw.peek.total!"msecs");
	foreach(url; urls) {
		remove(url.split('/').back);
	}
	sw.reset();
	sw.start();
	foreach(url; urls) {
		spawnDownload(url, url.split('/').back);
	}
	runFibers();
	sw.stop();
	writefln("Concurrently: %s ms", sw.peek.total!"msecs");
}