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

/// Origin of the wrapper that served this page.
///
/// In the real app that is always [desktopWrapperOrigin]; a test wrapper on
/// another port then talks only to *itself*. With the hard-coded origin a
/// test page on :8731 would POST its backlog to the real wrapper on :8730 --
/// a CORS "simple request" the browser sends without a preflight -- and
/// overwrite the real `BACKLOG.md`. Off the web (unit tests: `file:` base)
/// it falls back to [desktopWrapperOrigin].
/// [pageUrl] defaults to the page's own URL; tests pass one.
String servingWrapperOrigin([Uri? pageUrl]) {
  final base = pageUrl ?? Uri.base;
  return base.scheme == 'http' || base.scheme == 'https'
      ? base.origin
      : desktopWrapperOrigin;
}
