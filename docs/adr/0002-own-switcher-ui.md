# Own switcher UI instead of the native Cmd-Tab switcher

Posting synthetic Cmd-Tab key events would show the real system switcher for apps (Touch-Tab does this). But native Cmd-` has no UI, so the Window Switcher needs our own UI regardless. Driving the native switcher would also limit us to discrete Tab presses, hide the Selection from us, and clash with other Cmd-Tab replacements. We draw both Switchers ourselves, styled after the native one, for a consistent look and full control over behaviour.
