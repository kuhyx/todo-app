/// The fixed origin the desktop wrapper serves on.
///
/// **Do not change this casually.** `localStorage` (which holds the GitHub
/// token) and IndexedDB (which holds the note log) are both keyed by origin, so
/// changing the port silently logs the user out and hides their local notes
/// behind an origin they no longer visit. The wrapper script and
/// `install_arch.sh` must use the same value.
const desktopWrapperPort = 8730;

/// Origin of the desktop wrapper, e.g. `http://localhost:8730`.
const desktopWrapperOrigin = 'http://localhost:$desktopWrapperPort';
