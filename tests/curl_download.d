import std.net.curl;
import core.thread;
import photon;

void main(){
	startloop();
	spawn({
		string url = "http://arsdnet.net/dcode/book/chapter_02/03/client.d";
    	download(url, "download.txt");
	});
	runFibers();
}