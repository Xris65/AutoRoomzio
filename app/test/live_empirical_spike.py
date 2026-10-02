import json
import subprocess
import requests

adb = r'C:\Users\krisd\AppData\Local\Android\Sdk\platform-tools\adb.exe'

# 1. Read current refresh token from device
res = subprocess.run([adb, 'shell', 'run-as com.autoroomzio.app.debug cat shared_prefs/FlutterSharedPreferences.xml'], capture_output=True, text=True)
import re
match = re.search(r'<string name="flutter\.refresh_token">([^<]+)</string>', res.stdout)
if not match:
    print("Could not find refresh token in device XML!")
    exit(1)

refresh_token = match.group(1)
print(f"Current device refresh token: {refresh_token[:15]}...")

# 2. Exchange for access token
login_url = "https://login.roomz.io/connect/token"
resp = requests.post(login_url, data={
    "grant_type": "refresh_token",
    "refresh_token": refresh_token,
    "client_id": "my-roomz",
    "scope": "openid profile email identityServer-api my-roomz-api offline_access"
})

if resp.status_code != 200:
    print(f"Refresh failed: {resp.status_code} - {resp.text}")
    exit(1)

token_data = resp.json()
access_token = token_data['access_token']
new_refresh_token = token_data.get('refresh_token')
print(f"Obtained access token successfully!")

# 3. If rotated, update device XML immediately so user doesn't get logged out
if new_refresh_token and new_refresh_token != refresh_token:
    print(f"Updating device with new refresh token: {new_refresh_token[:15]}...")
    new_xml = res.stdout.replace(refresh_token, new_refresh_token)
    # Write to temp on device, then move with run-as
    p1 = subprocess.run([adb, 'shell', f"echo '{new_xml}' > /data/local/tmp/prefs.xml"], capture_output=True, text=True)
    p2 = subprocess.run([adb, 'shell', 'run-as com.autoroomzio.app.debug cp /data/local/tmp/prefs.xml shared_prefs/FlutterSharedPreferences.xml'], capture_output=True, text=True)
    print("Updated device preferences.")

# Save access token to a local file for subsequent spike runs
with open(r'c:\Users\krisd\AppData\Local\Temp\myroomz_active_token.txt', 'w') as f:
    f.write(access_token)

print("Active access token saved to temp file.")
