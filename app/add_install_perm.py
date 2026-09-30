import re

with open('android/app/src/main/AndroidManifest.xml', 'r', encoding='utf-8') as f:
    content = f.read()

if "android.permission.REQUEST_INSTALL_PACKAGES" not in content:
    content = content.replace(
        '<uses-permission android:name="android.permission.INTERNET"/>',
        '<uses-permission android:name="android.permission.INTERNET"/>\n    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />'
    )

with open('android/app/src/main/AndroidManifest.xml', 'w', encoding='utf-8') as f:
    f.write(content)