module photon.windows.support;
version(Windows):
import core.sys.windows.core;
import core.sys.windows.winsock2;
import std.format;

struct WSABUF 
{
    uint length;
    void* buf;
}

extern(Windows) SOCKET WSASocketW(
  int                af,
  int                type,
  int                protocol,
  void*              lpProtocolInfo,
  WORD               g,
  DWORD              dwFlags
);

// hackish, we do not use LPCONDITIONPROC
alias LPCONDITIONPROC = void*;

extern(Windows) SOCKET WSAAccept(
  SOCKET          s,
  sockaddr        *addr,
  LPINT           addrlen,
  LPCONDITIONPROC lpfnCondition,
  DWORD_PTR       dwCallbackData
);

extern(Windows) int WSARecv(
  SOCKET                             s,
  WSABUF                             *lpBuffers,
  DWORD                              dwBufferCount,
  LPDWORD                            lpNumberOfBytesRecvd,
  LPDWORD                            lpFlags,
  LPWSAOVERLAPPED                    lpOverlapped,
  LPWSAOVERLAPPED_COMPLETION_ROUTINE lpCompletionRoutine
);

extern(Windows) int WSASend(
  SOCKET                             s,
  WSABUF                             *lpBuffers,
  DWORD                              dwBufferCount,
  LPDWORD                            lpNumberOfBytesRecvd,
  LPDWORD                            lpFlags,
  LPWSAOVERLAPPED                    lpOverlapped,
  LPWSAOVERLAPPED_COMPLETION_ROUTINE lpCompletionRoutine
);

struct OVERLAPPED_ENTRY {
  ULONG_PTR    lpCompletionKey;
  LPOVERLAPPED lpOverlapped;
  ULONG_PTR    Internal;
  DWORD        dwNumberOfBytesTransferred;
}

alias LPOVERLAPPED_ENTRY = OVERLAPPED_ENTRY*;

extern(Windows) BOOL GetQueuedCompletionStatusEx(
  HANDLE             CompletionPort,
  LPOVERLAPPED_ENTRY lpCompletionPortEntries,
  ULONG              ulCount,
  PULONG             ulNumEntriesRemoved,
  DWORD              dwMilliseconds,
  BOOL               fAlertable
);

enum WSA_FLAG_OVERLAPPED  =  0x01;

void outputToConsole(const(wchar)[] msg)
{
    HANDLE output = GetStdHandle(STD_OUTPUT_HANDLE);
    uint size = cast(uint)msg.length;
    WriteConsole(output, msg.ptr, size, &size, null);
}

void logf(T...)(const(wchar)[] fmt, T args)
{
    debug(photon) try {
        formattedWrite(&outputToConsole, fmt, args);
        formattedWrite(&outputToConsole, "\n");
    }
    catch (Exception e) {
        outputToConsole("ARGH!"w);
    }
}

