with open('lib/api_service.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

old_wn = "                              final workspaceName = item['name']?.toString() ?? item['workspaceName']?.toString();\n"
old_loc = "                              final location = isMyDesk ? 'Mon bureau' : (workspaceName ?? 'Autre bureau');\n"
new_loc = "                              final location = isMyDesk ? 'Mon bureau' : (elsewhereMap[date] ?? item['workspaceName']?.toString() ?? item['name']?.toString() ?? 'Autre bureau');\n"

replaced = False
i = 0
while i < len(lines):
    if lines[i] == old_wn and i+1 < len(lines) and lines[i+1] == old_loc:
        lines[i] = new_loc
        del lines[i+1]
        replaced = True
        print('Replaced!')
        break
    i += 1

if not replaced:
    print('Not found! First 5 chars of suspect lines:')
    for j, l in enumerate(lines):
        if 'workspaceName' in l and 'final' in l:
            print(j, repr(l[:80]))

with open('lib/api_service.dart', 'w', encoding='utf-8') as f:
    f.writelines(lines)
