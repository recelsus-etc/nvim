return {
    name = "sourcekit",
    requires = {},
    config = {
        cmd = { "sourcekit-lsp" },
        filetypes = { "swift" },
        root_markers = { "buildServer.json", ".bsp", "Package.swift", "compile_commands.json", ".git" },
    },
}
