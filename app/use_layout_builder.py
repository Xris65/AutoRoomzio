import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# For Home Tab
home_old = """            child: _wrapWithPtr(
              SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: MediaQuery.of(context).size.height),"""
home_new = """            child: LayoutBuilder(
              builder: (context, constraints) {
                return _wrapWithPtr(
                  SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight - 32), // -32 for padding (16*2)"""
content = content.replace(home_old, home_new)

# Close LayoutBuilder for Home Tab
home_close_old = """                ],
              ),
            ),
          ),
        ),
        ),
        ),
        if (_isCalendarBusy)"""
home_close_new = """                ],
              ),
            ),
          ),
        );
        },
        ),
        ),
        ),
        if (_isCalendarBusy)"""
content = content.replace(home_close_old, home_close_new)


# For Calendar Tab
cal_old = """    return _wrapWithPtr(
      SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: MediaQuery.of(context).size.height),"""
cal_new = """    return LayoutBuilder(
      builder: (context, constraints) {
        return _wrapWithPtr(
          SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),"""
content = content.replace(cal_old, cal_new)

cal_close_old = """          )
        ],
      ),
      ),
      ),
    );
  }"""
cal_close_new = """          )
        ],
      ),
      ),
      ),
    );
    },
    );
  }"""
content = content.replace(cal_close_old, cal_close_new)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)