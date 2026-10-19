/* Minimal loopback static-file HTTP server.
 * Serves the bundled web game to WKWebView over http://127.0.0.1:<port>
 * so that localStorage (save games), WebAudio and fonts behave like a
 * normal web origin. Pure POSIX C, no Foundation.
 */
#ifndef HTTPSERVER_H
#define HTTPSERVER_H

/* Starts the server rooted at `root` (absolute path, no trailing slash is fine).
 * Tries `firstPort`, then firstPort+1 ... up to `tries` ports.
 * Returns the bound port on success, -1 on failure. */
int hs_start(const char *root, int firstPort, int tries);

/* Port that was bound, or -1. */
int hs_port(void);

#endif
