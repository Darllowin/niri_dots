require("git"):setup {
    order = 1500,
    git = {
        unknown_sign = " ",
        modified_sign = "M",
        deleted_sign = "D",
        clean_sign = "✔",
        modified = ui.Style():fg("blue"),
        deleted = ui.Style():fg("red"):bold(),
    }
}
