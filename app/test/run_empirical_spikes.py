import json
import requests

with open(r'c:\Users\krisd\AppData\Local\Temp\myroomz_active_token.txt', 'r') as f:
    token = f.read().strip()

api = "https://api.my.roomz.io"
org_id = "3b0ce737-a6cd-4a6b-b543-09b879fa1655"
site_id = "86f52773-595d-4ad4-dd94-08de536ceae5"
floor_id = "ca9b458a-2c84-4285-3f25-08de536d0906"
workspace_id = "4344b4aa-ebba-4598-b66e-97157be8b339"
my_user_id = "a2221459-c00e-40c2-891f-25a9c470094f"
colleague_id = "e9d7243e-6845-4a04-8718-d572cb005382"
colleague_name = "FOLLAIN Tristan"
colleague_email = "tristan.follain@soprasteria.com"

headers = {
    "Authorization": f"Bearer {token}",
    "Content-Type": "application/json",
    "Accept": "application/json",
    "roomz-source-type": "MyRoomzWeb",
    "Origin": "https://my.roomz.io",
    "Referer": "https://my.roomz.io/",
}

print("==================================================")
print("SPIKE 2: GLOBAL DIRECTORY ENDPOINT DISCOVERY")
print("==================================================")

search_terms = ["FOLLAIN", "Tristan", "kristo", "dhima"]
directory_probes = [
    # 1. /users variants
    ("GET", f"{api}/users", {}),
    ("GET", f"{api}/users?search=FOLLAIN", {}),
    ("GET", f"{api}/users?search=Tristan", {}),
    ("GET", f"{api}/users?q=FOLLAIN", {}),
    ("GET", f"{api}/users?filter=FOLLAIN", {}),
    ("GET", f"{api}/users?name=FOLLAIN", {}),
    ("GET", f"{api}/users?email=tristan.follain@soprasteria.com", {}),
    ("GET", f"{api}/users/{colleague_id}", {}),
    ("GET", f"{api}/users/search?query=FOLLAIN", {}),
    ("GET", f"{api}/users/search?search=FOLLAIN", {}),
    ("GET", f"{api}/users/search?q=FOLLAIN", {}),
    
    # 2. /organizations variants
    ("GET", f"{api}/organizations/{org_id}/users", {}),
    ("GET", f"{api}/organizations/{org_id}/users?search=FOLLAIN", {}),
    ("GET", f"{api}/organizations/{org_id}/directory", {}),
    ("GET", f"{api}/organizations/{org_id}/members", {}),
    ("GET", f"{api}/organizations/users", {}),
    ("GET", f"{api}/organization/users", {}),
    
    # 3. /tenants variants
    ("GET", f"{api}/tenants/{org_id}/users", {}),
    ("GET", f"{api}/tenants/{org_id}/users?search=FOLLAIN", {}),
    
    # 4. /directory variants
    ("GET", f"{api}/directory", {}),
    ("GET", f"{api}/directory/users", {}),
    ("GET", f"{api}/directory/search?query=FOLLAIN", {}),
    ("GET", f"{api}/directory/search?q=FOLLAIN", {}),
    
    # 5. /search variants
    ("GET", f"{api}/search/users?term=FOLLAIN", {}),
    ("GET", f"{api}/search/users?q=FOLLAIN", {}),
    ("GET", f"{api}/search/users?query=FOLLAIN", {}),
    ("GET", f"{api}/search?query=FOLLAIN", {}),
    ("GET", f"{api}/search?type=User&query=FOLLAIN", {}),
    
    # 6. /company & /colleagues variants
    ("GET", f"{api}/company/users", {}),
    ("GET", f"{api}/colleagues", {}),
    ("GET", f"{api}/colleagues?search=FOLLAIN", {}),
    
    # 7. /sites & /buildings & /floors variants
    ("GET", f"{api}/sites/{site_id}/users", {}),
    ("GET", f"{api}/buildings/{site_id}/users", {}),
    ("GET", f"{api}/buildings/{site_id}/users?search=FOLLAIN", {}),
    ("GET", f"{api}/floors/{floor_id}/users", {}),
    
    # 8. POST directory search variants
    ("POST", f"{api}/users/search", {"query": "FOLLAIN"}),
    ("POST", f"{api}/users/search", {"search": "FOLLAIN"}),
    ("POST", f"{api}/directory/search", {"query": "FOLLAIN"}),
    ("POST", f"{api}/organizations/{org_id}/users/search", {"query": "FOLLAIN"}),
]

for method, url, body in directory_probes:
    try:
        if method == "GET":
            r = requests.get(url, headers=headers, timeout=5)
        else:
            r = requests.post(url, headers=headers, json=body, timeout=5)
        print(f"[{method}] {url}")
        print(f"   -> Status: {r.status_code}, Length: {len(r.content)}")
        if r.status_code not in [404, 405]:
            print(f"   -> Response: {r.text[:300]}")
    except Exception as e:
        print(f"[{method}] {url} -> ERROR: {e}")
