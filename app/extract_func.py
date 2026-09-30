with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

in_func = False
for line in lines:
    if line.strip().startswith("Widget _buildUpcomingBookings()"):
        in_func = True
    if in_func:
        print(line, end="")
        if line.strip() == "Widget _buildUpcomingList() {":
            break