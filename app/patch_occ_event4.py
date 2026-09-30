with open('lib/api_service.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

for i, line in enumerate(lines):
    if "final evId = bookedTimeSlot['eventId']" in line:
        lines[i] = "                              final wsId = item['workspaceId']?.toString() ?? item['id']?.toString() ?? workspaceId;\n                              final location = isMyDesk ? 'Mon bureau' : 'Autre bureau';\n                              final evId = bookedTimeSlot['eventId']?.toString() ?? bookedTimeSlot['id']?.toString() ?? '';\n"
    if "delegateName = \"${organizerName}|${evId}|${orgId}\";" in line:
        lines[i] = "                              delegateName = \"${wsId}|${organizerName}|${location}|${evId}|${orgId}\";\n"
        print("Replaced delegateName to full format!")
        break

with open('lib/api_service.dart', 'w', encoding='utf-8') as f:
    f.writelines(lines)