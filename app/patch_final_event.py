with open('lib/api_service.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

for i, line in enumerate(lines):
    if "foundBookingId = b['id']?.toString();" in line:
        lines[i] = "            foundBookingId = b['eventId']?.toString() ?? b['id']?.toString();\n            if (foundBookingId != null && foundBookingId!.contains('/')) foundBookingId = foundBookingId!.split('/')[1];\n"
        print("Replaced foundBookingId!")
        break

for i, line in enumerate(lines):
    if "final eventId = bookedTimeSlot['id']?.toString() ?? \"\";" in line:
        lines[i] = "                                final eventId = bookedTimeSlot['eventId']?.toString() ?? bookedTimeSlot['id']?.toString() ?? \"\";\n"
        print("Replaced eventId in occupancy!")
        break

with open('lib/api_service.dart', 'w', encoding='utf-8') as f:
    f.writelines(lines)