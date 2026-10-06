/* Minimal wlanapi.dll for winws.exe on Windows without a Wi-Fi stack.
   winws imports: WlanOpenHandle, WlanEnumInterfaces, WlanQueryInterface,
   WlanFreeMemory, WlanCloseHandle. Returning "no adapters" is enough. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#ifndef WLAN_API_MAKE_VERSION
#define WLAN_API_MAKE_VERSION(major, minor) (((DWORD)major) << 16 | (DWORD)(minor))
#endif

__declspec(dllexport) DWORD WINAPI WlanOpenHandle(
    DWORD dwClientVersion,
    PVOID pReserved,
    PDWORD pdwNegotiatedVersion,
    PHANDLE phClientHandle)
{
    (void)dwClientVersion;
    (void)pReserved;
    if (pdwNegotiatedVersion) *pdwNegotiatedVersion = WLAN_API_MAKE_VERSION(2, 0);
    if (phClientHandle) *phClientHandle = (HANDLE)(ULONG_PTR)1;
    return ERROR_SUCCESS;
}

__declspec(dllexport) DWORD WINAPI WlanCloseHandle(HANDLE hClientHandle, PVOID pReserved)
{
    (void)hClientHandle;
    (void)pReserved;
    return ERROR_SUCCESS;
}

__declspec(dllexport) DWORD WINAPI WlanEnumInterfaces(
    HANDLE hClientHandle,
    PVOID pReserved,
    PVOID *ppInterfaceList)
{
    (void)hClientHandle;
    (void)pReserved;
    if (ppInterfaceList) *ppInterfaceList = NULL;
    return ERROR_NOT_FOUND;
}

__declspec(dllexport) VOID WINAPI WlanFreeMemory(PVOID pMemory)
{
    if (pMemory) HeapFree(GetProcessHeap(), 0, pMemory);
}

__declspec(dllexport) DWORD WINAPI WlanQueryInterface(
    HANDLE hClientHandle,
    const GUID *pInterfaceGuid,
    INT OpCode,
    PVOID pReserved,
    PDWORD pdwDataSize,
    PVOID *ppData,
    PVOID pWlanOpcodeValueType)
{
    (void)hClientHandle;
    (void)pInterfaceGuid;
    (void)OpCode;
    (void)pReserved;
    (void)pWlanOpcodeValueType;
    if (pdwDataSize) *pdwDataSize = 0;
    if (ppData) *ppData = NULL;
    return ERROR_NOT_FOUND;
}

BOOL WINAPI DllMain(HINSTANCE h, DWORD reason, LPVOID reserved)
{
    (void)h;
    (void)reason;
    (void)reserved;
    return TRUE;
}
