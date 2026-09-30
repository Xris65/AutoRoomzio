import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

switcher_old = """                body: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),"""
switcher_new = """                body: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
                    return Stack(
                      alignment: Alignment.topCenter,
                      children: <Widget>[
                        ...previousChildren,
                        if (currentChild != null) currentChild,
                      ],
                    );
                  },"""
content = content.replace(switcher_old, switcher_new)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)