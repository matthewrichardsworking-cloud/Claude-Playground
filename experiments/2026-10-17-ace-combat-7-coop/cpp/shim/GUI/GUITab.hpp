#pragma once
// Stand-in for UE4SS's own UE4SS/include/GUI/GUITab.hpp.
//
// The real header pulls in GUI/GUI.hpp, which needs the Dear ImGui headers and UE4SS's
// private Unreal headers (the UEPseudo repository, only open to GitHub accounts linked to
// an Epic Games account). CppUserModBase.hpp only needs the GUITab class declaration, so
// this copy of that declaration (identical members, same RenderFunctionType) is put on
// the include path ahead of UE4SS's include folder. Mods built this way must not use
// register_tab(); CoopNetMod and HelloMod don't.
//
// Copied from RE-UE4SS commit 48e7edfe (UE4SS/include/GUI/GUITab.hpp), MIT licence.

#include <utility>

#include <File/Macros.hpp>

namespace RC
{
    class CppUserModBase;
}

namespace RC::GUI
{
    class GUITab
    {
        friend class DebuggingGUI;

      public:
        using RenderFunctionType = void (*)(CppUserModBase*);

      private:
        RenderFunctionType render_function{};
        CppUserModBase* owner{};
        StringType tab_name{};

      public:
        GUITab() = delete;
        GUITab(StringViewType name, RenderFunctionType render_function) : tab_name(name), render_function(render_function) {};
        GUITab(StringViewType name, RenderFunctionType render_function, CppUserModBase* owner)
            : tab_name(name), render_function(render_function), owner(owner) {};
        ~GUITab() = default;

      private:
        auto get_owner() -> CppUserModBase*
        {
            return owner;
        }
    };
} // namespace RC::GUI
