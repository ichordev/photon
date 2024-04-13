module photon.windows.support;
version(Windows):
import core.sys.windows.core;


void outputToConsole(const(wchar)[] msg)
{
    HANDLE output = GetStdHandle(STD_OUTPUT_HANDLE);
    uint size = cast(uint)msg.length;
    WriteConsole(output, msg.ptr, size, &size, null);
}

void logf(T...)(const(wchar)[] fmt, T args)
{
    debug try {
        formattedWrite(&outputToConsole, fmt, args);
    }
    catch (Exception e) {
        outputToConsole("ARGH!"w);
    }
}
