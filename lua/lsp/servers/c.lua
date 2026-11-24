return {
    name = "clangd",
    package = "clangd",
    requires = { "unzip", "gcc|clang" },
    config = {
        cmd = { "clangd" },
        filetypes = { "c", "cpp", "objc", "objcpp", "cuda" },
        root_markers = {
            ".clangd",
            ".clang-tidy",
            ".clang-format",
            "compile_commands.json",
            "compile_flags.txt",
            "configure.ac",
            ".git",
        },
    },
}
