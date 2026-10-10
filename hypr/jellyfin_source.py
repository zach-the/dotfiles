#!/usr/bin/env python3
"""Pure Jellyfin REST-API logic (no GTK) shared by jellyfin_popup.py
(popup_daemon.py's "jellyfin" target): toggling per-library visibility
via the account's Policy.EnabledFolders, per https://api.jellyfin.org.

This is a single-account setup (one user, "zach", also the admin --
confirmed restricting EnabledFolders still hides a folder for an admin
account on this server, despite some older Jellyfin versions exempting
admins from that restriction) -- get_user_id() just takes /Users[0]
rather than resolving a particular TV login.

Auth: a local-only API key in ~/.config/jellyfin/waybar.env (generated
via Dashboard -> Advanced -> API Keys). That path is deliberately
outside ~/dotfiles -- unlike every other hypr/*.py here, this one
touches a secret, and ~/dotfiles is a symlinked, git-tracked repo."""
import os
import subprocess

import requests

BASE_URL = "http://localhost:8096"
ENV_PATH = os.path.expanduser("~/.config/jellyfin/waybar.env")
REQUEST_TIMEOUT = 3  # seconds; local server on this same machine

# ScheduledTasks' stable Key for the built-in "Scan Media Library" task
# (its Id is server-generated but its Key is a fixed string across
# every Jellyfin install).
SCAN_TASK_KEY = "RefreshLibrary"

_api_key = None
_scan_task_id = None


def _load_api_key():
    global _api_key
    if _api_key is None:
        with open(ENV_PATH) as f:
            for line in f:
                if line.startswith("JELLYFIN_API_KEY="):
                    _api_key = line.split("=", 1)[1].strip()
                    break
    return _api_key


def _headers():
    return {"Authorization": f'MediaBrowser Token="{_load_api_key()}"'}


def is_running():
    return subprocess.run(["systemctl", "is-active", "--quiet", "jellyfin"], check=False).returncode == 0


def start():
    subprocess.run(["systemctl", "start", "jellyfin"], check=False)
    subprocess.run(["pkill", "-RTMIN+14", "waybar"], capture_output=True, check=False)


def get_libraries():
    """Real content libraries only -- excludes the auto-generated
    "Collections" boxsets view, which isn't something you add media to
    or would ever want to hide/show from the TV."""
    resp = requests.get(f"{BASE_URL}/Library/VirtualFolders", headers=_headers(), timeout=REQUEST_TIMEOUT)
    resp.raise_for_status()
    return [
        {"id": f["ItemId"], "name": f["Name"]}
        for f in resp.json()
        if f.get("CollectionType") != "boxsets"
    ]


def get_policy():
    """Returns (user_id, policy_dict). The full Policy object is needed
    (not just EnabledFolders) since POST /Users/{id}/Policy replaces the
    whole thing -- partial updates would silently drop every other
    permission back to its JSON-default value."""
    resp = requests.get(f"{BASE_URL}/Users", headers=_headers(), timeout=REQUEST_TIMEOUT)
    resp.raise_for_status()
    user = resp.json()[0]
    return user["Id"], user["Policy"]


def is_enabled(policy, folder_id):
    return policy["EnableAllFolders"] or folder_id in policy["EnabledFolders"]


def set_folder_enabled(folder_id, enable, all_folder_ids):
    """Flip one library's visibility, re-fetching the policy first so
    this never clobbers a concurrent change. Collapses back to
    EnableAllFolders=True once every known library is enabled again,
    rather than leaving an explicit-but-complete EnabledFolders list --
    keeps the account's policy in the same state Jellyfin's own UI would
    leave it in."""
    user_id, policy = get_policy()
    current = set(all_folder_ids) if policy["EnableAllFolders"] else set(policy["EnabledFolders"])
    if enable:
        current.add(folder_id)
    else:
        current.discard(folder_id)

    if current == set(all_folder_ids):
        policy["EnableAllFolders"] = True
        policy["EnabledFolders"] = []
    else:
        policy["EnableAllFolders"] = False
        policy["EnabledFolders"] = sorted(current)

    resp = requests.post(f"{BASE_URL}/Users/{user_id}/Policy", headers=_headers(), json=policy, timeout=REQUEST_TIMEOUT)
    resp.raise_for_status()


def _get_scan_task_id():
    # Cached process-wide: the task's Id is stable for the lifetime of a
    # given Jellyfin server install, so this is one extra request ever
    # (the first poll after this module loads), not one per poll.
    global _scan_task_id
    if _scan_task_id is None:
        resp = requests.get(f"{BASE_URL}/ScheduledTasks", headers=_headers(), timeout=REQUEST_TIMEOUT)
        resp.raise_for_status()
        task = next((t for t in resp.json() if t["Key"] == SCAN_TASK_KEY), None)
        if task is not None:
            _scan_task_id = task["Id"]
    return _scan_task_id


def start_library_scan():
    task_id = _get_scan_task_id()
    if task_id is None:
        return False
    resp = requests.post(f"{BASE_URL}/ScheduledTasks/Running/{task_id}", headers=_headers(), timeout=REQUEST_TIMEOUT)
    resp.raise_for_status()
    return True


def get_scan_progress():
    """Returns (running, percent): percent is 0-100 while a scan is in
    progress, None otherwise (idle, or the server hasn't reported a
    percentage yet)."""
    task_id = _get_scan_task_id()
    if task_id is None:
        return False, None
    resp = requests.get(f"{BASE_URL}/ScheduledTasks/{task_id}", headers=_headers(), timeout=REQUEST_TIMEOUT)
    resp.raise_for_status()
    data = resp.json()
    running = data["State"] != "Idle"
    return running, (data.get("CurrentProgressPercentage") if running else None)
