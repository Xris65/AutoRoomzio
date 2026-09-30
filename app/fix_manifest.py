import re

with open('android/app/src/main/AndroidManifest.xml', 'r', encoding='utf-8') as f:
    content = f.read()

queries_old = """    <queries>
        <intent>
            <action android:name="android.intent.action.PROCESS_TEXT"/>
            <data android:mimeType="text/plain"/>
        </intent>
    </queries>"""
queries_new = """    <queries>
        <intent>
            <action android:name="android.intent.action.PROCESS_TEXT"/>
            <data android:mimeType="text/plain"/>
        </intent>
        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:scheme="https" />
        </intent>
    </queries>"""
content = content.replace(queries_old, queries_new)

with open('android/app/src/main/AndroidManifest.xml', 'w', encoding='utf-8') as f:
    f.write(content)