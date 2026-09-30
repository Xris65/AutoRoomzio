with open('android/app/build.gradle.kts', 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace('coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")', 'coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")')

with open('android/app/build.gradle.kts', 'w', encoding='utf-8') as f:
    f.write(content)