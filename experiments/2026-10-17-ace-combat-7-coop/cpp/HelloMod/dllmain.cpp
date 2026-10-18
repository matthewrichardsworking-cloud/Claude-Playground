// HelloMod: the UE4SS guide's own example C++ mod ("MyAwesomeMod" in
// docs/guides/creating-a-c++-mod.md at commit 48e7edfe), built here first to prove that
// the compiler, the headers and the import library match the UE4SS.dll in the game copy.
//
// The guide's Part 3 also looks up an Unreal object by name; that part needs UE4SS's
// private Unreal headers, which this build does not have, so it is left out. Everything
// else is the guide's code: say hello when the mod starts, and again once Unreal is up.

#include <Mod/CppUserModBase.hpp>
#include <DynamicOutput/DynamicOutput.hpp>

using namespace RC;

// __DATE__ and __TIME__ are narrow string literals; UE4SS logs wide strings.
#define WIDEN2(x) L##x
#define WIDEN(x) WIDEN2(x)

class HelloMod : public CppUserModBase
{
  public:
    HelloMod() : CppUserModBase()
    {
        ModName = STR("HelloMod");
        ModVersion = STR("1.0");
        ModDescription = STR("UE4SS guide example, built for the AC7 co-op workbench");
        ModAuthors = STR("UE4SS Team / AC7-Coop");

        Output::send<LogLevel::Verbose>(STR("[HelloMod] HelloMod says hello (built {} {})\n"), WIDEN(__DATE__), WIDEN(__TIME__));
    }

    ~HelloMod() override
    {
        Output::send<LogLevel::Verbose>(STR("[HelloMod] goodbye\n"));
    }

    auto on_unreal_init() -> void override
    {
        Output::send<LogLevel::Verbose>(STR("[HelloMod] Unreal is initialised; the mod is alive inside the game\n"));
    }
};

#define HELLO_MOD_API __declspec(dllexport)
extern "C"
{
    HELLO_MOD_API CppUserModBase* start_mod()
    {
        return new HelloMod();
    }

    HELLO_MOD_API void uninstall_mod(CppUserModBase* mod)
    {
        delete mod;
    }
}
