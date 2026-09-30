import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# For Home Tab
home_col = """                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,"""
home_constrained = """                padding: const EdgeInsets.all(16),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: MediaQuery.of(context).size.height),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,"""
content = content.replace(home_col, home_constrained)
# Close ConstrainedBox
home_col_end = """                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_isCalendarBusy)"""
home_constrained_end = """                        }).toList(),
                      ),
                    ),
                  ],
                ),
                ),
              ),
            ),
          ),
        ),
        if (_isCalendarBusy)"""
content = content.replace(home_col_end, home_constrained_end)

# For Calendar Tab
cal_col = """      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          children: ["""
cal_constrained = """      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: MediaQuery.of(context).size.height),
          child: Column(
            children: ["""
content = content.replace(cal_col, cal_constrained)
# Close ConstrainedBox
cal_col_end = """          )
        ],
      ),
      ),
    );
  }"""
cal_constrained_end = """          )
        ],
      ),
      ),
      ),
    );
  }"""
content = content.replace(cal_col_end, cal_constrained_end)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)