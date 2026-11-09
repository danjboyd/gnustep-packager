import base64, hashlib, json, os, sys
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives import serialization
root = sys.argv[1]
key = Ed25519PrivateKey.from_private_bytes(b"gnustep-packager test key, never")
pub = base64.b64encode(key.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)).decode()
ID = "org.example.UpdaterFixture"
def asset(version, payload_name, platform="linux-x64", tamper=False):
    path = os.path.join(root, payload_name)
    data = ("UpdaterFixture %s AppImage payload\n" % version).encode()
    open(path, "wb").write(data)
    sha = hashlib.sha256(data).hexdigest()
    signed = data if not tamper else b"what the publisher actually signed"
    msg = "\n".join(["gnustep-packager-update-v1", ID, version, "stable", platform, sha]).encode()
    return {"backend": "appimage", "platform": platform, "kind": "appimage", "name": payload_name,
            "url": "file://" + path, "sha256": sha, "sizeBytes": len(data),
            "edSignature": base64.b64encode(key.sign(signed)).decode(),
            "versionSignature": base64.b64encode(key.sign(msg)).decode()}
def release(version, notes=False, **kw):
    r = {"version": version, "tag": "v" + version, "assets": [asset(version, "UpdaterFixture-%s%s.AppImage" % (version, "-" + kw.get("platform", "x") if "platform" in kw else ("-tampered" if kw.get("tamper") else "")), **kw)]}
    if notes:
        r["releaseNotesUrl"] = "https://example.invalid/UpdaterFixture/releases/v" + version
    return r
feeds = {
    "uptodate": [release("1.0.0")],
    "offer101": [release("1.0.0"), release("1.0.1")],
    "offer101notes": [release("1.0.1", notes=True)],
    "offer102": [release("1.0.1"), release("1.0.2")],
    "armonly": [release("1.0.1", platform="linux-arm64")],
    "tampered": [release("1.0.1", tamper=True)],
}
for name, releases in feeds.items():
    json.dump({"formatVersion": 1, "channel": "stable", "releases": releases}, open(os.path.join(root, name + ".json"), "w"), indent=2)
cfg = {"package": {"id": ID, "name": "UpdaterFixture", "displayName": "Updater Fixture", "version": "1.0.0", "backend": "appimage"},
       "updates": {"feedUrl": "file://" + os.path.join(root, "uptodate.json"), "channel": "stable", "publicEDKey": pub,
                   "minimumCheckIntervalHours": 0, "startupDelaySeconds": 1}}
for name in list(feeds) + ["missing"]:
    cfg["updates"]["feedUrl"] = "file://" + os.path.join(root, name + ".json")
    json.dump(cfg, open(os.path.join(root, "config-" + name + ".json"), "w"), indent=2)
print(pub)
