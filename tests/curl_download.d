import std.net.curl, std.string, std.range;
import core.thread;
import photon;

immutable urls = [
	//"http://www.bbc.com",
	"https://github.com/DmitryOlshansky/jsm4s/releases/download/v1.4.1/jsm4s-1.4.1.jar"/*,
	"https://github.com/DmitryOlshansky/jsm4s/releases/download/v.1.4.0/jsm4s-v.1.4.0.jar",
	"https://github.com/DmitryOlshansky/jsm4s/releases/download/v1.3.0/jsm4s-1.3.0.jar"*/
];

void main(){
	startloop();
	void spawnDownload(string url, string file) {
		spawn(() => download(url, file));
	}
	foreach(url; urls) {
		auto file = url.split('/').back;
		spawnDownload(url, file);
	}
	runFibers();
}