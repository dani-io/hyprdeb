-- The settings window (`hyprdeb gui`, a Quickshell FloatingWindow, class org.quickshell, title "hyprdeb settings")
-- opens floating and centered. Matched by class AND exact title, so other Quickshell windows are not touched.
-- Without a rule it opens tiled (tested on 0.55.2).
hl.window_rule({
    name  = "hyprdeb-settings-window",
    match = { class = "^org\\.quickshell$", title = "^hyprdeb settings$" },
    float = true,
    center = true,
    size = "760 720",
})

-- The shortcuts list (`hyprdeb gui --page shortcuts`, SUPER + slash): same rule, its own exact title.
hl.window_rule({
    name  = "hyprdeb-shortcuts-window",
    match = { class = "^org\\.quickshell$", title = "^hyprdeb shortcuts$" },
    float = true,
    center = true,
    size = "620 720",
})
