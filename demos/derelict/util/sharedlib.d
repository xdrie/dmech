/*

Boost Software License - Version 1.0 - August 17th, 2003

Permission is hereby granted, free of charge, to any person or organization
obtaining a copy of the software and accompanying documentation covered by
this license (the "Software") to use, reproduce, display, distribute,
execute, and transmit the Software, and to prepare derivative works of the
Software, and to permit third-parties to whom the Software is furnished to
do so, all subject to the following:

The copyright notices in the Software and this entire statement, including
the above license grant, this restriction and the following disclaimer,
must be included in all copies of the Software, in whole or in part, and
all derivative works of the Software, unless such copies or derivative
works are solely in the form of machine-executable object code generated by
a source language processor.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.

*/
module derelict.util.sharedlib;

private
{
    import derelict.util.exception;
    import derelict.util.compat;
}

version(linux)
{
    version = Nix;
}
else version(darwin)
{
    version = Nix;
}
else version(OSX)
{
    version = Nix;
}
else version(FreeBSD)
{
    version = Nix;
    version = freebsd;
}
else version(freebsd)
{
    version = Nix;
}
else version(Unix)
{
    version = Nix;
}
else version(Posix)
{
    version = Nix;
}

version(Nix)
{
    // for people using DSSS, tell it to link the executable with libdl
    version(build)
    {
        version(freebsd)
        {
            // the dl* functions are in libc on FreeBSD
        }
        else pragma(link, "dl");
    }

    version(Tango)
    {
        private import tango.sys.Common;
    }
    else version(linux)
    {
        private import core.sys.posix;
    }
    else
    {
        extern(C)
        {
            /* From <dlfcn.h>
            *  See http://www.opengroup.org/onlinepubs/007908799/xsh/dlsym.html
            */

            const int RTLD_NOW = 2;

            void *dlopen(CCPTR file, int mode);
            int dlclose(void* handle);
            void *dlsym(void* handle, CCPTR name);
            CCPTR dlerror();
        }
    }

    alias void* SharedLibHandle;

    private SharedLibHandle LoadSharedLib(string libName)
    {
        return dlopen(toCString(libName), RTLD_NOW);
    }

    private void UnloadSharedLib(SharedLibHandle hlib)
    {
        dlclose(hlib);
    }

    private void* GetSymbol(SharedLibHandle hlib, string symbolName)
    {
        return dlsym(hlib, toCString(symbolName));
    }

    private string GetErrorStr()
    {
        CCPTR err = dlerror();
        if(err is null)
            return "Uknown Error";

        return toDString(err);
    }

}
else version(Windows)
{
    private import derelict.util.wintypes;
    alias HMODULE SharedLibHandle;

    private SharedLibHandle LoadSharedLib(string libName)
    {
        return LoadLibraryA(toCString(libName));
    }

    private void UnloadSharedLib(SharedLibHandle hlib)
    {
        FreeLibrary(hlib);
    }

    private void* GetSymbol(SharedLibHandle hlib, string symbolName)
    {
        return GetProcAddress(hlib, toCString(symbolName));
    }

    private string GetErrorStr()
    {
        // adapted from Tango

        DWORD errcode = GetLastError();

        LPCSTR msgBuf;
        DWORD i = FormatMessageA(
            FORMAT_MESSAGE_ALLOCATE_BUFFER |
            FORMAT_MESSAGE_FROM_SYSTEM |
            FORMAT_MESSAGE_IGNORE_INSERTS,
            null,
            errcode,
            MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
            cast(LPCSTR)&msgBuf,
            0,
            null);

        string text = toDString(msgBuf);
        LocalFree(cast(HLOCAL)msgBuf);

        if(i >= 2)
            i -= 2;
        return text[0 .. i];
    }
}
else
{
    static assert(0, "Derelict does not support this platform.");
}

final class SharedLib
{
public:
    this()
    {
    }

    string name()
    {
        return _name;
    }

    bool isLoaded()
    {
        return (_hlib !is null);
    }

    void load(string[] names)
    {
        if(isLoaded)
            return;

        string[] failedLibs;
        string[] reasons;

        foreach(n; names)
        {
            _hlib = LoadSharedLib(n);
            if(_hlib !is null)
            {
                _name = n;
                break;
            }

            failedLibs ~= n;
            reasons ~= GetErrorStr();
        }

        if(!isLoaded)
        {
            SharedLibLoadException.throwNew(failedLibs, reasons);
        }
    }

    void* loadSymbol(string symbolName, bool doThrow = true)
    {
        void* sym = GetSymbol(_hlib, symbolName);
        if(doThrow && (sym is null))
            Derelict_HandleMissingSymbol(name, symbolName);

        return sym;
    }

    void unload()
    {
        if(isLoaded)
        {
            UnloadSharedLib(_hlib);
            _hlib = null;
        }
    }

private:
    string _name;
    SharedLibHandle _hlib;
}
