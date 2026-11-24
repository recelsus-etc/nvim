return {
    name = "rust_analyzer",
    package = "rust-analyzer",
    requires = { "cargo" },
    config = {
        cmd = { "rust-analyzer" },
        filetypes = { "rust" },
        root_markers = { "Cargo.toml", "rust-project.json", ".git" },
    },
}
