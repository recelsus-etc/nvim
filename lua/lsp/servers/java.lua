local compat = require("compat")
local root_markers = {
    "mvnw",
    "gradlew",
    "settings.gradle",
    "settings.gradle.kts",
    "build.xml",
    "pom.xml",
    "build.gradle",
    "build.gradle.kts",
    ".git",
}

return {
    name = "jdtls",
    package = "jdtls",
    requires = { "java", "python3" },
    runtime_requires = { "java", "python3" },
    executable = "jdtls",
    config = {
        cmd = function(dispatchers, config)
            config = config or {}
            local root = config.root_dir or compat.find_root(0, root_markers) or vim.fn.getcwd()
            local data = compat.joinpath(vim.fn.stdpath("cache"), "jdtls", (root:gsub("[/\\:]", "%%")))
            return compat.lsp_rpc_start({ "jdtls", "-data", data }, dispatchers, {
                cwd = config.cmd_cwd,
                env = config.cmd_env,
            })
        end,
        filetypes = { "java" },
        root_markers = root_markers,
    },
}
