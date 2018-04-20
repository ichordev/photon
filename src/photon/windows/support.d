module photon.windows.support;

import core.sys.windows.core;

//opaque structs
struct UMS_COMPLETION_LIST;
struct UMS_CONTEXT;
struct PROC_THREAD_ATTRIBUTE_LIST;

struct UMS_SCHEDULER_STARTUP_INFO {
    ULONG                      UmsVersion;
    UMS_COMPLETION_LIST*       CompletionList;
    UmsSchedulerProc           SchedulerProc;
    PVOID                      SchedulerParam;
}

struct UMS_CREATE_THREAD_ATTRIBUTES {
  DWORD UmsVersion;
  PVOID UmsContext;
  PVOID UmsCompletionList;
}

enum UMS_SCHEDULER_REASON: uint {
  UmsSchedulerStartup = 0,
  UmsSchedulerThreadBlocked = 1,
  UmsSchedulerThreadYield = 2
}

enum UMS_VERSION =  0x0100;
enum
    PROC_THREAD_ATTRIBUTE_NUMBER = 0x0000FFFF,
    PROC_THREAD_ATTRIBUTE_THREAD = 0x00010000,    // Attribute may be used with thread creation
    PROC_THREAD_ATTRIBUTE_INPUT = 0x00020000,     // Attribute is input only
    PROC_THREAD_ATTRIBUTE_ADDITIVE = 0x00040000;  // Attribute may be "accumulated," e.g. bitmasks, counters, etc.

enum
    ProcThreadAttributeParentProcess                = 0,
    ProcThreadAttributeHandleList                   = 2,
    ProcThreadAttributeGroupAffinity                = 3,
    ProcThreadAttributePreferredNode                = 4,
    ProcThreadAttributeIdealProcessor               = 5,
    ProcThreadAttributeUmsThread                    = 6,
    ProcThreadAttributeMitigationPolicy             = 7;

 enum UMS_THREAD_INFO_CLASS: uint { 
  UmsThreadInvalidInfoClass  = 0,
  UmsThreadUserContext       = 1,
  UmsThreadPriority          = 2,
  UmsThreadAffinity          = 3,
  UmsThreadTeb               = 4,
  UmsThreadIsSuspended       = 5,
  UmsThreadIsTerminated      = 6,
  UmsThreadMaxInfoClass      = 7
}

uint ProcThreadAttributeValue(uint Number, bool Thread, bool Input, bool Additive)
{
    return (Number & PROC_THREAD_ATTRIBUTE_NUMBER) | 
     (Thread != FALSE ? PROC_THREAD_ATTRIBUTE_THREAD : 0) | 
     (Input != FALSE ? PROC_THREAD_ATTRIBUTE_INPUT : 0) | 
     (Additive != FALSE ? PROC_THREAD_ATTRIBUTE_ADDITIVE : 0);
}

enum PROC_THREAD_ATTRIBUTE_UMS_THREAD = ProcThreadAttributeValue(ProcThreadAttributeUmsThread, true, true, false);

extern(Windows) BOOL EnterUmsSchedulingMode(UMS_SCHEDULER_STARTUP_INFO* SchedulerStartupInfo);
extern(Windows) BOOL UmsThreadYield(PVOID SchedulerParam);
extern(Windows) BOOL DequeueUmsCompletionListItems(UMS_COMPLETION_LIST* UmsCompletionList, DWORD WaitTimeOut, UMS_CONTEXT** UmsThreadList);
extern(Windows) UMS_CONTEXT* GetNextUmsListItem(UMS_CONTEXT* UmsContext);
extern(Windows) BOOL ExecuteUmsThread(UMS_CONTEXT* UmsThread);
extern(Windows) BOOL CreateUmsCompletionList(UMS_COMPLETION_LIST** UmsCompletionList);
extern(Windows) BOOL CreateUmsThreadContext(UMS_CONTEXT** lpUmsThread);
extern(Windows) BOOL DeleteUmsThreadContext(UMS_CONTEXT* UmsThread);
extern(Windows) BOOL QueryUmsThreadInformation(
    UMS_CONTEXT*          UmsThread,
    UMS_THREAD_INFO_CLASS UmsThreadInfoClass,
    PVOID                 UmsThreadInformation,
    ULONG                 UmsThreadInformationLength,
    PULONG                ReturnLength
);

extern(Windows) BOOL InitializeProcThreadAttributeList(
  PROC_THREAD_ATTRIBUTE_LIST* lpAttributeList,
  DWORD                        dwAttributeCount,
  DWORD                        dwFlags,
  PSIZE_T                      lpSize
);

extern(Windows) VOID DeleteProcThreadAttributeList(PROC_THREAD_ATTRIBUTE_LIST* lpAttributeList);
extern(Windows) BOOL UpdateProcThreadAttribute(
  PROC_THREAD_ATTRIBUTE_LIST* lpAttributeList,
  DWORD                        dwFlags,
  DWORD_PTR                    Attribute,
  PVOID                        lpValue,
  SIZE_T                       cbSize,
  PVOID                        lpPreviousValue,
  PSIZE_T                      lpReturnSize
);

extern(Windows) HANDLE CreateRemoteThreadEx(
  HANDLE                       hProcess,
  PSECURITY_ATTRIBUTES        lpThreadAttributes,
  SIZE_T                       dwStackSize,
  LPTHREAD_START_ROUTINE       lpStartAddress,
  LPVOID                       lpParameter,
  DWORD                        dwCreationFlags,
  PROC_THREAD_ATTRIBUTE_LIST*  lpAttributeList,
  LPDWORD                      lpThreadId
);

enum STACK_SIZE_PARAM_IS_A_RESERVATION = 0x00010000;

alias UmsSchedulerProc = extern(Windows) VOID function(UMS_SCHEDULER_REASON Reason, ULONG_PTR ActivationPayload, PVOID SchedulerParam);

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
