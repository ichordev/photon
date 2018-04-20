module curl_download;
import std.net.curl;
import std.stdio;
import photon;

void main(){
    startloop();
    string url = "http://arsdnet.net/dcode/book/chapter_02/03/client.d";
    spawn({
        download(url, "download.txt");
    });
    writeln("Job done!");
    runFibers();
}
