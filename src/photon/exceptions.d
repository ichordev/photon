module photon.exceptions;

class ChannelClosed : Exception
{
    this(string file = __FILE__, size_t line = __LINE__, Throwable nextInChain = null) pure nothrow @nogc @safe
    {
        super("Put on the closed channel", file, line, nextInChain);
    }
}
