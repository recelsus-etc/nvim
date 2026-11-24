return {
    name = "bashls",
    package = "bash-language-server",
    requires = { "npm" },
    runtime_requires = { "node" },
    config = {
        cmd = { "bash-language-server", "start" },
        filetypes = { "sh", "bash" },
        root_markers = { ".git" },
        settings = {
            bashIde = {
                globPattern = "*@(.sh|.inc|.bash|.command)",
            },
        },
    },
}
