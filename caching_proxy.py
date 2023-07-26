#!/usr/bin/env python3

import sys
import os
import time
import http.client
import http.server
from io import StringIO
import pathlib
import urllib.parse

oldcachedir = None
newcachedir = None
readonly = False


class ProxyRequestHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        assert int(self.headers.get("Content-Length", 0)) == 0
        assert self.headers["Host"]
        pathprefix = "http://" + self.headers["Host"] + "/"
        assert self.path.startswith(pathprefix)
        sanitizedpath = urllib.parse.unquote(self.path.removeprefix(pathprefix))
        oldpath = oldcachedir / sanitizedpath
        newpath = newcachedir / sanitizedpath

        if not readonly:
            newpath.parent.mkdir(parents=True, exist_ok=True)

        # just send back to client
        if newpath.exists():
            print(f"proxy cached: {self.path}", file=sys.stderr)
            self.wfile.write(b"HTTP/1.1 200 OK\r\n")
            self.send_header("Content-Length", newpath.stat().st_size)
            self.end_headers()
            with newpath.open(mode="rb") as new:
                while True:
                    buf = new.read(64 * 1024)  # same as shutil uses
                    if not buf:
                        break
                    self.wfile.write(buf)
            self.wfile.flush()
            return

        if readonly:
            newpath = pathlib.Path("/dev/null")

        # copy from oldpath to newpath and send back to client
        # Only take files from the old cache if they are .deb files or Packages
        # files in the by-hash directory as only those are unique by their path
        # name. Other files like InRelease files have to be downloaded afresh.
        if oldpath.exists() and (
            oldpath.suffix == ".deb" or "by-hash" in oldpath.parts
        ):
            print(f"proxy cached: {self.path}", file=sys.stderr)
            self.wfile.write(b"HTTP/1.1 200 OK\r\n")
            self.send_header("Content-Length", oldpath.stat().st_size)
            self.end_headers()
            with oldpath.open(mode="rb") as old, newpath.open(mode="wb") as new:
                # we are not using shutil.copyfileobj() because we want to
                # write to two file objects simultaneously
                while True:
                    buf = old.read(64 * 1024)  # same as shutil uses
                    if not buf:
                        break
                    self.wfile.write(buf)
                    new.write(buf)
            self.wfile.flush()
            return

        # download fresh copy
        try:
            print(f"\rproxy download: {self.path}", file=sys.stderr)
            conn = http.client.HTTPConnection(self.headers["Host"], timeout=5)
            conn.request("GET", self.path, None, dict(self.headers))
            res = conn.getresponse()
            assert (res.status, res.reason) == (200, "OK"), (res.status, res.reason)
            self.wfile.write(b"HTTP/1.1 200 OK\r\n")
            for k, v in res.getheaders():
                # do not allow a persistent connection
                if k == "connection":
                    continue
                self.send_header(k, v)
            self.end_headers()
            with newpath.open(mode="wb") as f:
                # we are not using shutil.copyfileobj() because we want to
                # write to two file objects simultaneously and throttle the
                # writing speed to 1024 kB/s
                while True:
                    buf = res.read(64 * 1024)  # same as shutil uses
                    if not buf:
                        break
                    self.wfile.write(buf)
                    f.write(buf)
                    time.sleep(64 / 1024)  # 1024 kB/s
            self.wfile.flush()
        except Exception as e:
            self.send_error(502)


def main():
    global oldcachedir, newcachedir, readonly
    if sys.argv[1] == "--readonly":
        readonly = True
        oldcachedir = pathlib.Path(sys.argv[2])
        newcachedir = pathlib.Path(sys.argv[3])
    else:
        oldcachedir = pathlib.Path(sys.argv[1])
        newcachedir = pathlib.Path(sys.argv[2])
    print(f"starting caching proxy for {newcachedir}", file=sys.stderr)
    httpd = http.server.ThreadingHTTPServer(
        server_address=("", 8080), RequestHandlerClass=ProxyRequestHandler
    )
    httpd.serve_forever()


if __name__ == "__main__":
    main()
