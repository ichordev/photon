import std.algorithm, std.net.curl, std.string, std.datetime.stopwatch, std.range, std.stdio;
import std.file : remove;
import core.thread;
import photon;

// try your own urls
immutable urls = [
	"https://mirror.yandex.ru/debian/doc/FAQ/debian-faq.en.html.tar.gz",
	"https://mirror.yandex.ru/debian/doc/FAQ/debian-faq.en.pdf.gz",
	"https://mirror.yandex.ru/debian/doc/FAQ/debian-faq.en.ps.gz",
	"https://mirror.yandex.ru/debian/doc/FAQ/debian-faq.en.txt.gz"
];

void main(){
	startloop();
	void spawnDownload(string url, string file) {
		spawn(() => download(url, file));
	}
	Thread threadDownload(string url, string file) {
		auto t = new Thread(() => download(url, file));
		t.start();
		return t;
	}
	StopWatch sw;

	foreach(url; urls) {
		remove(url.split('/').back);
	}
	sw.reset();
	sw.start();
	urls
		.map!(url => threadDownload(url, url.split('/').back))
		.each!(t => t.join());
	sw.stop();
	writefln("Threads: %s ms", sw.peek.total!"msecs");


	sw.reset();
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