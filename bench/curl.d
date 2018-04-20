import std.stdio;
import std.net.curl;
import photon;

void main()
{
    auto content = get("wttr.in");
    writeln(content);
}
