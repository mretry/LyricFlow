#!/usr/bin/env python3
"""Share a selected Windows folder to LyricFlow over the local Wi-Fi network.

Run: py -m pip install -r scripts/requirements-pc-share.txt
     py scripts/pc_lan_share_server.py
Then scan the QR code shown in the browser from LyricFlow on the iPhone/iPad.
Only supported media/subtitle files inside the chosen folder are exposed.
"""
from __future__ import annotations

import argparse
import io
import json
import secrets
import socket
import sys
import threading
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path, PurePosixPath
from urllib.parse import parse_qs, quote, urlparse

try:
    import qrcode
except ImportError:
    print('Missing dependency. Run: py -m pip install -r scripts/requirements-pc-share.txt')
    raise SystemExit(2)

SUPPORTED_EXTENSIONS = {
    'mp3', 'm4a', 'aac', 'wav', 'flac', 'mp4', 'mov', 'm4v',
    'lrc', 'srt', 'vtt', 'ass',
}


def pick_folder() -> Path:
    try:
        import tkinter as tk
        from tkinter import filedialog

        root = tk.Tk()
        root.withdraw()
        root.attributes('-topmost', True)
        chosen = filedialog.askdirectory(title='选择要共享给 LyricFlow 的媒体文件夹')
        root.destroy()
        if chosen:
            return Path(chosen).resolve()
    except Exception as exc:  # noqa: BLE001 - fall back to console input
        print(f'Folder picker unavailable: {exc}')
    value = input('输入要共享的文件夹路径: ').strip().strip('"')
    return Path(value).expanduser().resolve()


def detect_lan_ip() -> str:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.connect(('192.0.2.1', 80))
            address = sock.getsockname()[0]
            if address and not address.startswith('127.'):
                return address
    except OSError:
        pass
    return '127.0.0.1'


class ShareServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, address, handler, *, root: Path, token: str):
        super().__init__(address, handler)
        self.share_root = root.resolve()
        self.token = token


class ShareHandler(BaseHTTPRequestHandler):
    server: ShareServer
    protocol_version = 'HTTP/1.1'

    def log_message(self, fmt: str, *args) -> None:
        sys.stdout.write('[%s] %s\n' % (self.log_date_time_string(), fmt % args))

    def _send(self, status: int, body: bytes, content_type: str) -> None:
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(body)

    def _authorized(self, query: dict[str, list[str]]) -> bool:
        values = query.get('token', [])
        return bool(values) and secrets.compare_digest(values[0], self.server.token)

    def _files(self) -> list[dict[str, object]]:
        root = self.server.share_root
        result: list[dict[str, object]] = []
        for candidate in root.rglob('*'):
            try:
                if not candidate.is_file() or candidate.is_symlink():
                    continue
                resolved = candidate.resolve()
                relative = resolved.relative_to(root)
                if resolved.suffix.lower().lstrip('.') not in SUPPORTED_EXTENSIONS:
                    continue
                # Avoid exposing hidden/system metadata files by default.
                if any(part.startswith('.') for part in relative.parts):
                    continue
                rel = PurePosixPath(*relative.parts).as_posix()
                result.append({
                    'name': relative.name,
                    'path': rel,
                    'size': resolved.stat().st_size,
                    'extension': resolved.suffix.lower().lstrip('.'),
                })
            except (OSError, ValueError):
                continue
        result.sort(key=lambda item: str(item['path']).casefold())
        return result

    def _safe_file(self, relative: str) -> Path | None:
        if not relative or '\\' in relative:
            return None
        root = self.server.share_root
        try:
            candidate = (root / Path(*PurePosixPath(relative).parts)).resolve()
            candidate.relative_to(root)
            if not candidate.is_file() or candidate.is_symlink():
                return None
            if candidate.suffix.lower().lstrip('.') not in SUPPORTED_EXTENSIONS:
                return None
            return candidate
        except (OSError, ValueError):
            return None

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        query = parse_qs(parsed.query)
        if not self._authorized(query):
            self._send(403, b'Invalid or missing token', 'text/plain; charset=utf-8')
            return

        url = f'http://{self.headers.get("Host", "127.0.0.1")}/?token={quote(self.server.token)}'
        if parsed.path == '/':
            body = f'''<!doctype html><html lang="en"><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>LyricFlow LAN Share</title>
<style>body{{font:16px system-ui;max-width:760px;margin:32px auto;padding:0 18px;background:#10121a;color:#f5f2ff}}a{{color:#c9abff}}.card{{padding:22px;border-radius:18px;background:#1b1d2a}}img{{width:min(78vw,340px);height:auto;background:white;padding:10px;border-radius:12px}}small{{color:#aaa7bc}}</style>
<h1>LyricFlow · LAN Share</h1><div class="card"><p>Scan this QR code in LyricFlow on your iPhone/iPad.</p>
<img alt="LAN share QR code" src="/qr.png?token={quote(self.server.token)}">
<p><small>Devices must be on the same Wi-Fi. Keep this page open while importing.</small></p></div>
<h2>Shared folder files</h2><p id="status">Loading…</p><ul id="files"></ul>
<script>fetch('/api/files?token={quote(self.server.token)}').then(r=>r.json()).then(d=>{{document.getElementById('status').textContent=d.files.length+' supported files';document.getElementById('files').innerHTML=d.files.map(f=>'<li>'+f.name.replace(/[&<>]/g,c=>({{'&':'&amp;','<':'&lt;','>':'&gt;'}}[c]))+' ('+(f.size/1048576).toFixed(1)+' MB)</li>').join('')}}).catch(()=>document.getElementById('status').textContent='Unable to load files');</script>
<p><small>Local-network only. Press Ctrl+C in the terminal to stop sharing.</small></p></html>'''.encode('utf-8')
            self._send(200, body, 'text/html; charset=utf-8')
            return

        if parsed.path == '/qr.png':
            image = qrcode.make(url)
            buffer = io.BytesIO()
            image.save(buffer, format='PNG')
            self._send(200, buffer.getvalue(), 'image/png')
            return

        if parsed.path == '/api/files':
            body = json.dumps({'files': self._files()}, ensure_ascii=False).encode('utf-8')
            self._send(200, body, 'application/json; charset=utf-8')
            return

        if parsed.path == '/api/download':
            values = query.get('path', [])
            target = self._safe_file(values[0] if values else '')
            if target is None:
                self._send(404, b'File not found', 'text/plain; charset=utf-8')
                return
            try:
                size = target.stat().st_size
                self.send_response(200)
                self.send_header('Content-Type', 'application/octet-stream')
                self.send_header('Content-Length', str(size))
                self.send_header('Content-Disposition', f"attachment; filename*=UTF-8''{quote(target.name)}")
                self.send_header('Cache-Control', 'no-store')
                self.end_headers()
                with target.open('rb') as source:
                    while chunk := source.read(1024 * 1024):
                        self.wfile.write(chunk)
            except (BrokenPipeError, ConnectionResetError):
                pass
            except OSError as exc:
                print(f'Download failed for {target}: {exc}')
            return

        self._send(404, b'Not found', 'text/plain; charset=utf-8')


def main() -> int:
    parser = argparse.ArgumentParser(description='Share local media to LyricFlow over Wi-Fi.')
    parser.add_argument('--folder', type=Path, help='Folder to share; a folder picker opens if omitted.')
    parser.add_argument('--port', type=int, default=8765)
    parser.add_argument('--host-ip', help='Override detected LAN IPv4 address shown in the QR code.')
    args = parser.parse_args()

    root = args.folder.expanduser().resolve() if args.folder else pick_folder()
    if not root.is_dir():
        print(f'Not a directory: {root}', file=sys.stderr)
        return 2
    lan_ip = args.host_ip or detect_lan_ip()
    if lan_ip == '127.0.0.1':
        print('Could not detect a LAN IP. Connect this PC to Wi-Fi/Ethernet and retry, or use --host-ip.')
        return 2

    token = secrets.token_urlsafe(18)
    server = ShareServer(('0.0.0.0', args.port), ShareHandler, root=root, token=token)
    url = f'http://{lan_ip}:{args.port}/?token={quote(token)}'
    print('\nLyricFlow LAN Share is ready')
    print(f'Shared folder: {root}')
    print(f'Open on this PC: {url}')
    print('Scan the QR code in the browser from LyricFlow on your iPhone/iPad.')
    print('Only supported media/subtitle files in this folder are exposed. Press Ctrl+C to stop.\n')
    try:
        threading.Timer(0.8, lambda: webbrowser.open(url)).start()
        server.serve_forever(poll_interval=0.4)
    except KeyboardInterrupt:
        print('\nStopping LAN share…')
    finally:
        server.server_close()
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
