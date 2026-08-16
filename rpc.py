#!/usr/bin/env python3
"""Bridge Discord's RPC socket to line-delimited JSON on stdout and stdin.

Discord speaks a binary frame protocol over a unix socket, which QML cannot
parse; this process owns that connection and exposes one JSON object per line.
It prints a full state snapshot whenever anything changes, and reads one
command object per line from stdin.

Check it by hand with:  python3 rpc.py --probe
"""

import json, os, signal, socket, struct, sys, threading, time
import urllib.parse, urllib.request

OP_HANDSHAKE, OP_FRAME, OP_CLOSE, OP_PING, OP_PONG = 0, 1, 2, 3, 4

HEADER = struct.Struct("<II")
API = "https://discord.com/api"
SCOPES = ["rpc", "rpc.voice.read", "rpc.voice.write"]
REDIRECT_URI = "http://localhost/omarchy-discord"

# Discord numbers its sockets when several clients run; one instance uses 0.
SOCKET_RANGE = 10
TOKEN_MODE = 0o600
TOKEN_DIR_MODE = 0o700
REFRESH_MARGIN_SEC = 300
RECONNECT_DELAY_SEC = 5
SECRETS_READ_TIMEOUT_SEC = 5

STATE_DIR = os.path.join(
    os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")),
    "omarchy-discord")
TOKEN_PATH = os.path.join(STATE_DIR, "token.json")
SECRETS_PATH = os.environ.get("OMARCHY_DISCORD_SECRETS",
                              os.path.expanduser("~/.claude/secrets/.env"))


class RpcError(Exception):
    """Carries a message meant for the user, not a stack trace."""


# lines look like "DISCORD_CLIENT_ID=1234567890", values never evaluated
def read_secrets_file(path):
    """Parse KEY=value pairs the way load-secrets.sh does, without running them."""
    values = {}
    if not os.path.exists(path):
        return values

    def expired(_signum, _frame):
        raise TimeoutError

    # The 1Password mount is a FIFO that blocks until the app serves it.
    previous = signal.signal(signal.SIGALRM, expired)
    signal.alarm(SECRETS_READ_TIMEOUT_SEC)
    try:
        with open(path, "r") as handle:
            for line in handle:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, _, value = line.partition("=")
                values[key.strip()] = value
    except (TimeoutError, OSError):
        return {}
    finally:
        signal.alarm(0)
        signal.signal(signal.SIGALRM, previous)
    return values


def credentials():
    client_id = os.environ.get("DISCORD_CLIENT_ID", "")
    client_secret = os.environ.get("DISCORD_CLIENT_SECRET", "")
    if not client_id or not client_secret:
        secrets = read_secrets_file(SECRETS_PATH)
        client_id = client_id or secrets.get("DISCORD_CLIENT_ID", "")
        client_secret = client_secret or secrets.get("DISCORD_CLIENT_SECRET", "")
    if not client_id or not client_secret:
        raise RpcError("No Discord application credentials: set DISCORD_CLIENT_ID "
                       "and DISCORD_CLIENT_SECRET in the 1Password claude-skills Environment")
    return client_id.strip(), client_secret.strip()


def load_token():
    try:
        with open(TOKEN_PATH) as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return {}


def save_token(token):
    os.makedirs(STATE_DIR, mode=TOKEN_DIR_MODE, exist_ok=True)
    # chmod before the rename, so the token is never briefly world-readable
    temporary = TOKEN_PATH + ".tmp"
    with open(temporary, "w") as handle:
        json.dump(token, handle)
    os.chmod(temporary, TOKEN_MODE)
    os.replace(temporary, TOKEN_PATH)


def post_token(client_id, client_secret, fields):
    body = dict(fields, client_id=client_id, client_secret=client_secret)
    request = urllib.request.Request(
        API + "/oauth2/token",
        data=urllib.parse.urlencode(body).encode(),
        headers={"Content-Type": "application/x-www-form-urlencoded"})
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            token = json.load(response)
    except Exception as error:
        raise RpcError("Discord token request failed: %s" % error)
    if "access_token" not in token:
        raise RpcError("Discord returned no access token")
    token["expires_at"] = time.time() + float(token.get("expires_in", 0))
    save_token(token)
    return token


class Rpc:
    def __init__(self, sock):
        self.sock = sock
        self.lock = threading.Lock()
        self.nonce = 0

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass

    def send(self, op, payload):
        blob = json.dumps(payload).encode()
        with self.lock:
            self.sock.sendall(HEADER.pack(op, len(blob)) + blob)

    def recv(self):
        op, length = HEADER.unpack(self._read_exactly(HEADER.size))
        return op, json.loads(self._read_exactly(length).decode())

    def _read_exactly(self, count):
        chunks = b""
        while len(chunks) < count:
            chunk = self.sock.recv(count - len(chunks))
            if not chunk:
                raise RpcError("Discord closed the RPC socket")
            chunks += chunk
        return chunks

    def command(self, cmd, args=None, evt=None):
        self.nonce += 1
        nonce = str(self.nonce)
        frame = {"cmd": cmd, "nonce": nonce}
        if args is not None:
            frame["args"] = args
        if evt is not None:
            frame["evt"] = evt
        self.send(OP_FRAME, frame)
        return nonce

    def request(self, cmd, args=None, evt=None):
        """Send a command and pump frames until its own reply arrives."""
        nonce = self.command(cmd, args, evt)
        while True:
            op, payload = self.recv()
            if op == OP_CLOSE:
                raise RpcError(payload.get("message", "Discord closed the connection"))
            if op == OP_PING:
                self.send(OP_PONG, payload)
                continue
            if payload.get("nonce") != nonce:
                continue
            if payload.get("evt") == "ERROR":
                raise RpcError((payload.get("data") or {}).get("message", "RPC error"))
            return payload.get("data") or {}


def connect_socket():
    base = os.environ.get("XDG_RUNTIME_DIR") or "/run/user/%d" % os.getuid()
    for index in range(SOCKET_RANGE):
        path = os.path.join(base, "discord-ipc-%d" % index)
        if not os.path.exists(path):
            continue
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            sock.connect(path)
            return sock
        except OSError:
            sock.close()
    raise RpcError("Discord is not running (no discord-ipc socket)")


def handshake(rpc, client_id):
    rpc.send(OP_HANDSHAKE, {"v": 1, "client_id": client_id})
    while True:
        op, payload = rpc.recv()
        if op == OP_CLOSE:
            raise RpcError(payload.get("message", "Discord refused the handshake"))
        if payload.get("evt") == "READY":
            return payload.get("data") or {}


def authorize(rpc, client_id, client_secret):
    """One-time consent: Discord shows a modal, then the code buys a token."""
    data = rpc.request("AUTHORIZE", {"client_id": client_id, "scopes": SCOPES})
    code = data.get("code")
    if not code:
        raise RpcError("Discord did not return an authorization code")
    return post_token(client_id, client_secret,
                      {"grant_type": "authorization_code", "code": code,
                       "redirect_uri": REDIRECT_URI})


def valid_token(client_id, client_secret):
    token = load_token()
    if token.get("access_token") and token.get("expires_at", 0) > time.time() + REFRESH_MARGIN_SEC:
        return token
    if token.get("refresh_token"):
        try:
            return post_token(client_id, client_secret,
                              {"grant_type": "refresh_token",
                               "refresh_token": token["refresh_token"]})
        except RpcError:
            pass
    return None


class Bridge:
    def __init__(self, rpc):
        self.rpc = rpc
        self.subscribed_channel = None
        self.members = {}
        self.speaking = set()
        self.guilds = {}
        self.state = {"ok": True, "channel": "", "guild": "", "mute": False,
                      "deaf": False, "inputVolume": 100, "outputVolume": 100,
                      "mode": "", "speaking": [], "error": ""}

    def emit(self):
        self.state["speaking"] = sorted(
            self.members.get(user_id, user_id) for user_id in self.speaking)
        sys.stdout.write(json.dumps(self.state) + "\n")
        sys.stdout.flush()

    def apply_voice_settings(self, data):
        self.state["mute"] = bool(data.get("mute"))
        self.state["deaf"] = bool(data.get("deaf"))
        self.state["inputVolume"] = round(float((data.get("input") or {}).get("volume", 100)))
        self.state["outputVolume"] = round(float((data.get("output") or {}).get("volume", 100)))
        self.state["mode"] = str((data.get("mode") or {}).get("type", ""))

    def guild_name(self, guild_id):
        if not guild_id:
            return ""
        if guild_id not in self.guilds:
            try:
                self.guilds[guild_id] = self.rpc.request(
                    "GET_GUILD", {"guild_id": guild_id}).get("name", "")
            except RpcError:
                self.guilds[guild_id] = ""
        return self.guilds[guild_id]

    def select_channel(self, channel_id):
        self.speaking.clear()
        self.members.clear()
        if not channel_id:
            self.state["channel"] = ""
            self.state["guild"] = ""
            self.resubscribe(None)
            return
        channel = self.rpc.request("GET_CHANNEL", {"channel_id": channel_id})
        self.state["channel"] = channel.get("name", "")
        self.state["guild"] = self.guild_name(channel.get("guild_id"))
        # voice_states already names everyone sitting in the call
        for entry in channel.get("voice_states") or []:
            user = entry.get("user") or {}
            if user.get("id"):
                self.members[user["id"]] = entry.get("nick") or user.get("username") or user["id"]
        self.resubscribe(channel_id)

    def resubscribe(self, channel_id):
        for event in ("SPEAKING_START", "SPEAKING_STOP"):
            if self.subscribed_channel:
                try:
                    self.rpc.request(event, {"channel_id": self.subscribed_channel},
                                     evt="UNSUBSCRIBE")
                except RpcError:
                    pass
            if channel_id:
                self.rpc.request(event, {"channel_id": channel_id}, evt="SUBSCRIBE")
        self.subscribed_channel = channel_id

    def handle_event(self, event, data):
        if event == "VOICE_SETTINGS_UPDATE":
            self.apply_voice_settings(data)
        elif event == "VOICE_CHANNEL_SELECT":
            self.select_channel(data.get("channel_id"))
        elif event == "SPEAKING_START":
            self.speaking.add(data.get("user_id"))
        elif event == "SPEAKING_STOP":
            self.speaking.discard(data.get("user_id"))
        else:
            return False
        return True

    # commands look like {"cmd": "mute", "value": true}
    def handle_command(self, line):
        try:
            message = json.loads(line)
        except ValueError:
            return
        name, value = message.get("cmd"), message.get("value")
        if name in ("mute", "deaf"):
            self.rpc.command("SET_VOICE_SETTINGS", {name: bool(value)})
        elif name == "inputVolume":
            self.rpc.command("SET_VOICE_SETTINGS", {"input": {"volume": float(value)}})
        elif name == "outputVolume":
            self.rpc.command("SET_VOICE_SETTINGS", {"output": {"volume": float(value)}})
        elif name == "mode":
            self.rpc.command("SET_VOICE_SETTINGS", {"mode": {"type": str(value)}})
        elif name == "disconnect":
            self.rpc.command("SELECT_VOICE_CHANNEL", {"channel_id": None, "force": True})
        elif name == "refresh":
            self.refresh()

    def refresh(self):
        self.apply_voice_settings(self.rpc.request("GET_VOICE_SETTINGS"))
        selected = self.rpc.request("GET_SELECTED_VOICE_CHANNEL")
        self.select_channel(selected.get("id") if selected else None)
        self.emit()

    def run(self):
        for event in ("VOICE_SETTINGS_UPDATE", "VOICE_CHANNEL_SELECT"):
            self.rpc.request(event, evt="SUBSCRIBE")
        self.refresh()
        threading.Thread(target=self.read_commands, daemon=True).start()
        while True:
            op, payload = self.rpc.recv()
            if op == OP_CLOSE:
                raise RpcError(payload.get("message", "Discord closed the connection"))
            if op == OP_PING:
                self.rpc.send(OP_PONG, payload)
                continue
            if payload.get("cmd") == "DISPATCH" and self.handle_event(
                    payload.get("evt"), payload.get("data") or {}):
                self.emit()

    def read_commands(self):
        for line in sys.stdin:
            try:
                self.handle_command(line)
            except (RpcError, OSError, ValueError):
                return


def emit_error(message, configured=True):
    payload = {"ok": False, "error": str(message)}
    # The widget shows a failure but stays silent about a tier nobody set up.
    if not configured:
        payload["configured"] = False
    sys.stdout.write(json.dumps(payload) + "\n")
    sys.stdout.flush()


def session():
    client_id, client_secret = credentials()
    rpc = Rpc(connect_socket())
    try:
        handshake(rpc, client_id)
        token = valid_token(client_id, client_secret) or authorize(rpc, client_id, client_secret)
        rpc.request("AUTHENTICATE", {"access_token": token["access_token"]})
        Bridge(rpc).run()
    finally:
        rpc.close()


def probe():
    """Report what the socket and credentials look like, without authenticating."""
    try:
        client_id, _ = credentials()
    except RpcError as error:
        print("credentials: %s" % error)
        return 1
    print("client_id: %s... (%d chars)" % (client_id[:6], len(client_id)))
    try:
        rpc = Rpc(connect_socket())
    except RpcError as error:
        print("socket: %s" % error)
        return 1
    try:
        ready = handshake(rpc, client_id)
        print("handshake: ok, Discord reports user %s"
              % (ready.get("user") or {}).get("username", "unknown"))
        print("token cached: %s" % bool(load_token().get("access_token")))
        return 0
    except RpcError as error:
        print("handshake: %s" % error)
        return 1
    finally:
        rpc.close()


EXIT_UNCONFIGURED = 2


def main():
    if "--probe" in sys.argv:
        return probe()
    # Credentials cannot appear while we run, so retrying would only spin.
    try:
        credentials()
    except RpcError as error:
        emit_error(error, configured=False)
        return EXIT_UNCONFIGURED
    while True:
        try:
            session()
        except RpcError as error:
            emit_error(error)
        except Exception as error:  # keep the bridge alive; the widget shows the text
            emit_error("%s: %s" % (type(error).__name__, error))
        time.sleep(RECONNECT_DELAY_SEC)


if __name__ == "__main__":
    sys.exit(main() or 0)
