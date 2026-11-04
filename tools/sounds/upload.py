"""Uploads an audio file as a Roblox Audio asset through the Open Cloud Assets API and prints its id:
`python tools/sounds/upload.py <file> "<display name>" "<description>"`.

The key is read from ROBLOX_API_KEY (asset write access) and never printed; the creator is the
game owner's user (assets/sounds/README.md). The call returns an operation, polled until done.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request
import uuid

CREATOR = "1636829198"
TYPES = {".mp3": "audio/mpeg", ".ogg": "audio/ogg", ".wav": "audio/wav", ".flac": "audio/flac"}


def upload(path, name, description):
    key = os.environ["ROBLOX_API_KEY"]
    kind = TYPES[os.path.splitext(path)[1].lower()]
    boundary = uuid.uuid4().hex
    request = {
        "assetType": "Audio",
        "displayName": name,
        "description": description,
        "creationContext": {"creator": {"userId": CREATOR}},
    }
    with open(path, "rb") as file:
        data = file.read()
    body = b"".join(
        [
            f'--{boundary}\r\nContent-Disposition: form-data; name="request"\r\n'
            f"Content-Type: application/json\r\n\r\n{json.dumps(request)}\r\n".encode(),
            f'--{boundary}\r\nContent-Disposition: form-data; name="fileContent"; '
            f'filename="{os.path.basename(path)}"\r\nContent-Type: {kind}\r\n\r\n'.encode() + data + b"\r\n",
            f"--{boundary}--\r\n".encode(),
        ]
    )
    post = urllib.request.Request(
        "https://apis.roblox.com/assets/v1/assets",
        data=body,
        method="POST",
        headers={"x-api-key": key, "Content-Type": f"multipart/form-data; boundary={boundary}"},
    )
    try:
        operation = json.load(urllib.request.urlopen(post))
    except urllib.error.HTTPError as error:
        return None, f"HTTP {error.code} {error.read().decode()[:300]}"
    path_id = operation["path"].split("/")[-1]
    for _ in range(60):
        time.sleep(3)
        poll = urllib.request.Request(
            f"https://apis.roblox.com/assets/v1/operations/{path_id}", headers={"x-api-key": key}
        )
        result = json.load(urllib.request.urlopen(poll))
        if result.get("done"):
            if "response" in result:
                return result["response"]["assetId"], None
            return None, json.dumps(result.get("error"))
    return None, "timed out"


if __name__ == "__main__":
    asset, error = upload(sys.argv[1], sys.argv[2], sys.argv[3])
    print(os.path.basename(sys.argv[1]), asset, error or "")
