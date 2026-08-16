#!/usr/bin/env python3
"""Bridge Discord's RPC socket to line-delimited JSON on stdout and stdin.

Discord speaks a binary frame protocol over a unix socket, which QML cannot
parse; this process owns that connection and exposes one JSON object per line.
It prints a full state snapshot whenever anything changes, and reads one
command object per line from stdin.

Set it up with:         python3 rpc.py --setup
Check it by hand with:  python3 rpc.py --probe
"""

import json, os, queue, select, signal, socket, struct, subprocess, sys, threading, time
import urllib.error, urllib.parse, urllib.request

OP_HANDSHAKE, OP_FRAME, OP_CLOSE, OP_PING, OP_PONG = 0, 1, 2, 3, 4

HEADER = struct.Struct("<II")
API = "https://discord.com/api"
PORTAL = "https://discord.com/developers/applications"
# Discord's edge answers the default Python user agent with a bare 403.
USER_AGENT = "omarchy-discord (https://github.com/thisisgm/omarchy-discord, 1.0)"
SCOPES = ["rpc", "rpc.voice.read", "rpc.voice.write"]
REDIRECT_URI = "http://localhost/omarchy-discord"

# Discord numbers its sockets when several clients run; one instance uses 0.
SOCKET_RANGE = 10
TOKEN_MODE = 0o600
TOKEN_DIR_MODE = 0o700
REFRESH_MARGIN_SEC = 300
RECONNECT_DELAY_SEC = 5
# The receive loop wakes this often to run queued commands.
SOCKET_POLL_SEC = 0.2
# Discord pings several times a second; a bar only cares about the coarse value.
PING_ROUND_MS = 10
SECRETS_READ_TIMEOUT_SEC = 5
# Warnings quote their input, clipped so one bad line cannot flood the log.
WARN_INPUT_CHARS = 80
HTTP_DETAIL_CHARS = 200
PUBLIC_KEY_LENGTH = 64
HEX_DIGITS = "0123456789abcdefABCDEF"

STATE_DIR = os.path.join(
    os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")),
    "omarchy-discord")
TOKEN_PATH = os.path.join(STATE_DIR, "token.json")
CONFIG_DIR = os.path.join(
    os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")),
    "omarchy-discord")
CREDENTIALS_PATH = os.path.join(CONFIG_DIR, "credentials.json")
SECRETS_PATH = os.environ.get("OMARCHY_DISCORD_SECRETS",
                              os.path.expanduser("~/.claude/secrets/.env"))


COMMANDS = queue.Queue()


class RpcError(Exception):
    """Carries a message meant for the user, not a stack trace."""


class RpcRejected(RpcError):
    """Discord refused one command; the connection itself is still good."""


def clip(text, limit):
    """Shorten for a log line, marking the cut so nobody reads it as the whole input."""
    text = str(text).strip()
    return text if len(text) <= limit else text[:limit] + "..."


def warn(message):
    sys.stderr.write("omarchy-discord: %s\n" % message)
    sys.stderr.flush()


def as_number(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def start_stdin_reader():
    """One reader for the whole process, so a reconnect cannot orphan a line."""
    def pump():
        for line in sys.stdin:
            COMMANDS.put(line)

    threading.Thread(target=pump, daemon=True).start()


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


def write_private(path, payload):
    """Write JSON readable only by its owner, and never briefly wider."""
    os.makedirs(os.path.dirname(path), mode=TOKEN_DIR_MODE, exist_ok=True)
    temporary = path + ".tmp"
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, TOKEN_MODE)
    # O_CREAT ignores its mode on a leftover temporary, so narrow the fd itself.
    os.fchmod(descriptor, TOKEN_MODE)
    with os.fdopen(descriptor, "w") as handle:
        json.dump(payload, handle)
    os.replace(temporary, path)


def read_credentials_file():
    try:
        with open(CREDENTIALS_PATH) as handle:
            stored = json.load(handle)
    except (OSError, ValueError):
        return {}
    return stored if isinstance(stored, dict) else {}


def credentials():
    """Environment first, then the file --setup writes, then a secrets mount."""
    client_id = os.environ.get("DISCORD_CLIENT_ID", "")
    client_secret = os.environ.get("DISCORD_CLIENT_SECRET", "")
    if not client_id or not client_secret:
        stored = read_credentials_file()
        client_id = client_id or str(stored.get("client_id", ""))
        client_secret = client_secret or str(stored.get("client_secret", ""))
    if not client_id or not client_secret:
        secrets = read_secrets_file(SECRETS_PATH)
        client_id = client_id or secrets.get("DISCORD_CLIENT_ID", "")
        client_secret = client_secret or secrets.get("DISCORD_CLIENT_SECRET", "")
    if not client_id or not client_secret:
        raise RpcError("Discord voice controls are not set up yet, run: "
                       "python3 %s --setup" % os.path.abspath(__file__))
    return client_id.strip(), client_secret.strip()


def load_token():
    try:
        with open(TOKEN_PATH) as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return {}


def save_token(token):
    write_private(TOKEN_PATH, token)


def post_token(client_id, client_secret, fields):
    body = dict(fields, client_id=client_id, client_secret=client_secret)
    request = urllib.request.Request(
        API + "/oauth2/token",
        data=urllib.parse.urlencode(body).encode(),
        headers={"Content-Type": "application/x-www-form-urlencoded",
                 "User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            token = json.load(response)
    except urllib.error.HTTPError as error:
        # The body names the actual problem; the status alone never does.
        detail = ""
        try:
            detail = clip(error.read().decode("utf-8", "replace"), HTTP_DETAIL_CHARS)
        except OSError:
            pass
        raise RpcError("Discord token request failed: HTTP %d %s"
                       % (error.code, detail))
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
        self.deferred = []

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass

    def send(self, op, payload):
        blob = json.dumps(payload).encode()
        with self.lock:
            self.sock.sendall(HEADER.pack(op, len(blob)) + blob)

    # frames are 4 bytes little-endian opcode, 4 bytes little-endian length,
    # then that many bytes of JSON: 01 00 00 00 12 00 00 00 {"cmd":"DISPATCH"...}
    def recv(self):
        op, length = HEADER.unpack(self._read_exactly(HEADER.size))
        return op, json.loads(self._read_exactly(length).decode())

    def readable(self, timeout):
        return bool(select.select([self.sock], [], [], timeout)[0])

    def take_deferred(self):
        events, self.deferred = self.deferred, []
        return events

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

    def subscribe(self, event, args=None):
        return self.request("SUBSCRIBE", args, evt=event)

    def unsubscribe(self, event, args=None):
        return self.request("UNSUBSCRIBE", args, evt=event)

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
                # An event that lands mid-request is still owed to the caller.
                if payload.get("cmd") == "DISPATCH":
                    self.deferred.append(payload)
                continue
            if payload.get("evt") == "ERROR":
                raise RpcRejected((payload.get("data") or {}).get("message", "RPC error"))
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
                      "deaf": False, "inputVolume": 100,
                      "speaking": [], "error": "",
                      "ping": 0, "voiceState": ""}

    def emit(self):
        self.state["speaking"] = sorted(
            self.members.get(user_id, user_id) for user_id in self.speaking)
        sys.stdout.write(json.dumps(self.state) + "\n")
        sys.stdout.flush()

    def apply_voice_settings(self, data):
        self.state["mute"] = bool(data.get("mute"))
        self.state["deaf"] = bool(data.get("deaf"))
        self.state["inputVolume"] = round(float((data.get("input") or {}).get("volume", 100)))

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
                    self.rpc.unsubscribe(event, {"channel_id": self.subscribed_channel})
                except RpcError:
                    pass
            if channel_id:
                self.rpc.subscribe(event, {"channel_id": channel_id})
        self.subscribed_channel = channel_id

    # {"state": "VOICE_CONNECTED", "average_ping": 36, "last_ping": 35, ...}
    def apply_connection(self, data):
        state = str(data.get("state") or "")
        ping = int(data.get("average_ping") or 0)
        rounded = int(round(ping / float(PING_ROUND_MS)) * PING_ROUND_MS)
        if state == self.state["voiceState"] and rounded == self.state["ping"]:
            return False
        self.state["voiceState"] = state
        self.state["ping"] = rounded
        return True

    def handle_event(self, event, data):
        if event == "VOICE_CONNECTION_STATUS":
            return self.apply_connection(data)
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
            warn("ignored a command that is not JSON: %r" % clip(line, WARN_INPUT_CHARS))
            return
        name, value = message.get("cmd"), message.get("value")
        if name in ("mute", "deaf"):
            self.rpc.command("SET_VOICE_SETTINGS", {name: bool(value)})
        elif name == "inputVolume":
            volume = as_number(value)
            if volume is None:
                warn("inputVolume needs a number, got %r" % (value,))
                return
            self.rpc.command("SET_VOICE_SETTINGS", {"input": {"volume": volume}})
        elif name == "disconnect":
            self.rpc.command("SELECT_VOICE_CHANNEL", {"channel_id": None, "force": True})
        elif name == "refresh":
            self.refresh()
        else:
            warn("unknown command %r" % (name,))

    def drain_commands(self):
        while True:
            try:
                line = COMMANDS.get_nowait()
            except queue.Empty:
                return
            # A refused command is not a dead socket, so it must not end the session.
            try:
                self.handle_command(line)
            except RpcRejected as error:
                warn("Discord refused %s: %s" % (clip(line, WARN_INPUT_CHARS), error))

    def drain_deferred(self):
        changed = False
        for payload in self.rpc.take_deferred():
            if self.handle_event(payload.get("evt"), payload.get("data") or {}):
                changed = True
        return changed

    def refresh(self):
        self.apply_voice_settings(self.rpc.request("GET_VOICE_SETTINGS"))
        selected = self.rpc.request("GET_SELECTED_VOICE_CHANNEL")
        self.select_channel(selected.get("id") if selected else None)
        self.emit()

    # This thread owns the socket outright; nothing else reads or writes it.
    def run(self):
        for event in ("VOICE_SETTINGS_UPDATE", "VOICE_CHANNEL_SELECT",
                      "VOICE_CONNECTION_STATUS"):
            self.rpc.subscribe(event)
        self.refresh()
        while True:
            self.drain_commands()
            if self.drain_deferred():
                self.emit()
            if not self.rpc.readable(SOCKET_POLL_SEC):
                continue
            op, payload = self.rpc.recv()
            if op == OP_CLOSE:
                raise RpcError(payload.get("message", "Discord closed the connection"))
            if op == OP_PING:
                self.rpc.send(OP_PONG, payload)
                continue
            # Nobody is waiting on a fire and forget command, so warn here.
            if payload.get("evt") == "ERROR":
                warn("Discord refused %s: %s"
                     % (payload.get("cmd"),
                        (payload.get("data") or {}).get("message", "unknown error")))
                continue
            if payload.get("cmd") == "DISPATCH" and self.handle_event(
                    payload.get("evt"), payload.get("data") or {}):
                self.emit()


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


def looks_like_public_key(value):
    return len(value) == PUBLIC_KEY_LENGTH and all(c in HEX_DIGITS for c in value)


# stdin carries {"client_id": "...", "client_secret": "..."} on one line
def save_from_stdin():
    """Take the pair on stdin so no secret ever appears in argv or in ps."""
    try:
        message = json.loads(sys.stdin.readline())
    except ValueError:
        sys.stderr.write("Expected one JSON object on stdin\n")
        return 1
    client_id = str(message.get("client_id", "")).strip()
    client_secret = str(message.get("client_secret", "")).strip()
    if not client_id.isdigit():
        sys.stderr.write("The Client ID is a long number, digits only\n")
        return 1
    if not client_secret:
        sys.stderr.write("The Client Secret is empty\n")
        return 1
    if looks_like_public_key(client_secret):
        sys.stderr.write("That is the Public Key; the secret is on the OAuth2 page\n")
        return 1
    write_private(CREDENTIALS_PATH, {"client_id": client_id,
                                     "client_secret": client_secret})
    return 0


EXIT_UNCONFIGURED = 2


def ask(label):
    sys.stdout.write(label)
    sys.stdout.flush()
    return sys.stdin.readline().strip()


def open_portal():
    if not (os.environ.get("WAYLAND_DISPLAY") or os.environ.get("DISPLAY")):
        return
    try:
        subprocess.Popen(["xdg-open", PORTAL],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print("Opened the developer portal in your browser.\n")
    except OSError:
        pass


def collect_credentials():
    """Reuse what is already saved, or walk through registering an application."""
    stored = read_credentials_file()
    client_id = str(stored.get("client_id", ""))
    client_secret = str(stored.get("client_secret", ""))
    if client_id and client_secret:
        print("Using the application already saved in %s." % CREDENTIALS_PATH)
        print("Delete that file to enter a different one.\n")
        return client_id, client_secret

    print("Discord refuses anonymous clients, so the voice controls need an")
    print("application of your own. This is the only setup, and it is one time.\n")
    print("1. Create an application, any name, at:")
    print("     %s" % PORTAL)
    print("2. Open its OAuth2 page and add this redirect URI, exactly:")
    print("     %s" % REDIRECT_URI)
    print("3. Copy CLIENT ID and CLIENT SECRET from that same OAuth2 page.")
    print("   Reset Secret reveals the secret. Do not use the Public Key on")
    print("   General Information, which signs webhooks and will not work.\n")
    open_portal()

    client_id = ask("Client ID (a long number):     ")
    if not client_id.isdigit():
        print("\nThat is not the Client ID. It is a long number, digits only.")
        return None
    client_secret = ask("Client Secret (OAuth2 page):   ")
    if not client_secret:
        print("\nNo client secret given.")
        return None
    # The Public Key is an Ed25519 key: 32 bytes, so exactly 64 hex characters.
    if looks_like_public_key(client_secret):
        print("\nThat is the Public Key, not the Client Secret. It signs")
        print("interaction webhooks and cannot buy a token. The secret is on")
        print("the OAuth2 page, behind Reset Secret.")
        return None

    write_private(CREDENTIALS_PATH, {"client_id": client_id,
                                     "client_secret": client_secret})
    print("\nSaved to %s, readable only by you." % CREDENTIALS_PATH)
    return client_id, client_secret


def setup():
    """Get the application, then prove the whole tier end to end."""
    pair = collect_credentials()
    if pair is None:
        return 1
    client_id, client_secret = pair

    try:
        rpc = Rpc(connect_socket())
    except RpcError as error:
        print("%s. Start Discord and run this again." % error)
        return 1

    print("Discord will now ask you to authorize it. Approve that prompt.\n")
    try:
        ready = handshake(rpc, client_id)
        token = valid_token(client_id, client_secret) or authorize(rpc, client_id, client_secret)
        rpc.request("AUTHENTICATE", {"access_token": token["access_token"]})
        print("Ready. Authenticated as %s."
              % (ready.get("user") or {}).get("username", "your account"))
        print("Open the Discord panel in the bar and the call controls are there.")
        return 0
    except RpcError as error:
        print("Discord refused: %s\n" % error)
        if "redirect_uri" in str(error):
            print("That means the application has no redirect URI registered,")
            print("Discord has none to fall back on. On its OAuth2 page, under")
            print("Redirects, Add Redirect and paste exactly:")
            print("     %s" % REDIRECT_URI)
            print("then click Save Changes. The portal keeps that button in a")
            print("bar at the bottom and discards the entry without it.")
            print("Run this again afterwards; it reuses what you already saved.")
        else:
            print("Check the redirect URI is exactly %s." % REDIRECT_URI)
            print("If the application is not yours, your account must be on its")
            print("App Testers list; the owner is already covered.")
        return 1
    finally:
        rpc.close()


def main():
    if "--save" in sys.argv:
        return save_from_stdin()
    if "--setup" in sys.argv:
        return setup()
    if "--probe" in sys.argv:
        return probe()
    # Credentials cannot appear while we run, so retrying would only spin.
    try:
        credentials()
    except RpcError as error:
        emit_error(error, configured=False)
        return EXIT_UNCONFIGURED
    start_stdin_reader()
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
