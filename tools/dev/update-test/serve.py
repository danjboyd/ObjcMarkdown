#!/usr/bin/env python3
"""Serves the feeds make-feeds.py made, on the test machine (#114).

Usage: sudo serve.py <out-dir>

http://127.0.0.1:8765/       <out-dir>/www, for the rc (GP_UPDATER_FEED_URL)
https://danjboyd.github.io/  the same, on 127.0.0.1:443 with the throwaway
                             certificate, for the released 0.2.0. Needs
                             "127.0.0.1 danjboyd.github.io" in /etc/hosts and
                             GSTLSCAFile (NSGlobalDomain) set to <out-dir>/tls/ca.pem.
Port 443 needs root; with --http-only it serves only port 8765, as any user.
Use only on a throwaway test machine.
"""

import functools
import http.server
import os
import ssl
import sys
import threading


def server(port, directory, context=None):
    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=directory)
    httpd = http.server.ThreadingHTTPServer(("127.0.0.1", port), handler)
    if context is not None:
        httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
    return httpd


def main():
    arguments = [a for a in sys.argv[1:] if a != "--http-only"]
    if len(arguments) != 1:
        sys.stderr.write(__doc__)
        sys.exit(2)
    out = os.path.abspath(arguments[0])
    www = os.path.join(out, "www")
    servers = [server(8765, www)]
    if "--http-only" not in sys.argv:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(os.path.join(out, "tls", "server.pem"), os.path.join(out, "tls", "server.key"))
        servers.append(server(443, www, context))
    for httpd in servers[1:]:
        threading.Thread(target=httpd.serve_forever, daemon=True).start()
    print("Serving %s on http://127.0.0.1:8765/%s" % (www, "" if len(servers) == 1 else " and https://danjboyd.github.io/"))
    servers[0].serve_forever()


if __name__ == "__main__":
    main()
