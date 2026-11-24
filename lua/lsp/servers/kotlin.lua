return {
    name = "kotlin_lsp",
    package = "kotlin-lsp",
    requires = {},
    config = {
        cmd = { "intellij-server", "--stdio" },
        filetypes = { "kotlin" },
        root_markers = {
            "settings.gradle",
            "settings.gradle.kts",
            "pom.xml",
            "build.gradle",
            "build.gradle.kts",
            "workspace.json",
        },
    },
}
