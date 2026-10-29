#!/usr/bin/env python3
"""Exercise the actual Swift Realtime clients against a local Phoenix WebSocket fixture."""
import base64
import hashlib
import http.server
import json
import pathlib
import socket
import struct
import subprocess
import threading
import urllib.parse


peers = set()
peers_lock = threading.Lock()


class WebSocket(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def do_POST(self):
        if self.path != "/drop":
            self.send_error(404)
            return
        with peers_lock:
            active = list(peers)
        for peer in active:
            try:
                peer.connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
        self.send_response(200)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self):
        query = urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query)
        if query.get("vsn") != ["1.0.0"]:
            self.send_error(400, "Expected JSON protocol 1.0.0")
            return
        key = self.headers["Sec-WebSocket-Key"]
        digest = hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()
        self.send_response(101)
        self.send_header("Upgrade", "websocket")
        self.send_header("Connection", "Upgrade")
        self.send_header("Sec-WebSocket-Accept", base64.b64encode(digest).decode())
        self.end_headers()
        self.topic = None
        self.join_ref = None
        self.send_lock = threading.Lock()
        with peers_lock:
            peers.add(self)
        try:
            while True:
                header = self.rfile.read(2)
                if len(header) != 2:
                    break
                opcode, size = header[0] & 15, header[1] & 127
                if size == 126:
                    size = struct.unpack("!H", self.rfile.read(2))[0]
                elif size == 127:
                    size = struct.unpack("!Q", self.rfile.read(8))[0]
                mask = self.rfile.read(4) if header[1] & 128 else None
                payload = self.rfile.read(size)
                if mask:
                    payload = bytes(value ^ mask[i % 4] for i, value in enumerate(payload))
                if opcode == 8:
                    break
                if opcode != 1:
                    continue
                message = json.loads(payload)
                event = message["event"]
                if event == "phx_join":
                    self.topic, self.join_ref = message["topic"], message.get("join_ref")
                if event in ("phx_join", "phx_leave", "heartbeat", "broadcast"):
                    self.send_json({
                        "topic": message["topic"], "event": "phx_reply",
                        "ref": message.get("ref"), "join_ref": message.get("join_ref"),
                        "payload": {"status": "ok", "response": {"postgres_changes": []} if event == "phx_join" else {}},
                    })
                if event == "phx_leave":
                    self.send_json({
                        "topic": self.topic, "event": "phx_close", "payload": {},
                        "ref": None, "join_ref": self.join_ref,
                    })
                    self.topic = None
                if event == "broadcast":
                    with peers_lock:
                        targets = [p for p in peers if p is not self and p.topic == message["topic"]]
                    for target in targets:
                        try:
                            target.send_json({
                                "topic": target.topic, "event": "broadcast",
                                "ref": None, "join_ref": target.join_ref, "payload": message["payload"],
                            })
                        except OSError:
                            pass
        except (OSError, ValueError):
            pass
        finally:
            with peers_lock:
                peers.discard(self)
            self.close_connection = True

    def send_json(self, message):
        payload = json.dumps(message, ensure_ascii=False).encode()
        header = bytes([0x81, len(payload)]) if len(payload) < 126 else b"\x81\x7e" + struct.pack("!H", len(payload))
        with self.send_lock:
            self.connection.sendall(header + payload)


def main():
    root = pathlib.Path(__file__).resolve().parent.parent
    subprocess.run(["swift", "build", "-Xswiftc", "-warnings-as-errors"], cwd=root, check=True)
    build = root / ".build/debug"
    link_inputs = (build / "CoupleMon.product/Objects.LinkFileList").read_text().splitlines()
    objects = [p for p in link_inputs if pathlib.Path(p).name != "CoupleMonApp.swift.o"]
    executable = root / ".build/realtime-check"
    subprocess.run([
        "swiftc", "-parse-as-library", "-I", str(build), str(root / "Checks/RealtimeCheck.swift"),
        *map(str, objects), "-o", str(executable),
    ], cwd=root, check=True)
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), WebSocket)
    server.daemon_threads = True
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        subprocess.run([str(executable), f"http://127.0.0.1:{server.server_port}/realtime"],
                       cwd=root, check=True, timeout=90)
    finally:
        server.shutdown()
        server.server_close()


if __name__ == "__main__":
    main()
