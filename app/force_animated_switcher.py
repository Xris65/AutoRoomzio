import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Replace AnimatedSwitcher completely using regex to avoid line ending issues
pattern = r"body:\s*AnimatedSwitcher\([\s\S]*?child:\s*KeyedSubtree"

replacement = """body: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
                  return Stack(
                    alignment: Alignment.topCenter,
                    children: <Widget>[
                      ...previousChildren,
                      if (currentChild != null) currentChild,
                    ],
                  );
                },
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.04), // slight slide up
                      end: Offset.zero,
                    ).animate(animation),
                    child: FadeTransition(opacity: animation, child: child),
                  );
                },
                child: KeyedSubtree"""

content = re.sub(pattern, replacement, content)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)