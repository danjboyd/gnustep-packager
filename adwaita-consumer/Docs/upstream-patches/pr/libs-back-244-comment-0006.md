A note on merging this one: please merge #PR_NUMBER first, or together with this.

This keeps the window's functions in its Motif hints, close included, so Mutter starts offering to close windows the gui decorates. But those windows don't list `WM_DELETE_WINDOW` (`-_setSupportedWMProtocols:` reads the closable bit from the stripped style the X window is created with). So Mutter closes them by killing the client: with only this PR, Alt+F4 quits the whole application. On master it does nothing. #PR_NUMBER lists `WM_DELETE_WINDOW` for closable windows the gui decorates; with both, Alt+F4 closes the window through `-performClose:`.

The two touch different functions and apply in either order; only the ChangeLog's top entry needs a hand merge.
