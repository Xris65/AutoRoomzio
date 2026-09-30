with open('lib/api_service.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

for i, line in enumerate(lines):
    if "delegateName = organizerName;" in line:
        lines[i] = "                              final evId = bookedTimeSlot['eventId']?.toString() ?? bookedTimeSlot['id']?.toString() ?? \"\";\n                              final orgId = organizer['id']?.toString() ?? \"\";\n                              delegateName = \"${organizerName}|${evId}|${orgId}\";\n"
        print("Replaced delegateName!")
        break

with open('lib/api_service.dart', 'w', encoding='utf-8') as f:
    f.writelines(lines)