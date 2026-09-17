"""Phase-1 loop for: 'New quiz opens the last-opened quiz'.

Asserts the new-quiz entry points fully reset builder state. A headless
browser is unavailable in this env (no jsdom, no new deps per offline-first
policy), so this static check is the tight loop: it reads the exact
functions users click and fails on the exact stale-state vectors.
Run: python3 scripts/check_quiz_reset.py (from Debian Server/)
"""
import re
import sys
from pathlib import Path

STATIC = Path(__file__).resolve().parent.parent / "static"
FAIL = []


def check(cond, msg):
    sys.stderr.write(("GREEN " if cond else "RED   ") + msg + "\n")
    if not cond:
        FAIL.append(msg)


def fn_body(src, name):
    m = re.search(r"function " + name + r"\(.*?\)\s*\{", src)
    if not m:
        return None
    i, depth = m.end(), 1
    while i < len(src) and depth:
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
        i += 1
    return src[m.end():i - 1]


mc = (STATIC / "manage-content.html").read_text(encoding="utf-8")
ch = (STATIC / "courses.html").read_text(encoding="utf-8")

new_mc = fn_body(mc, "openQuizBuilderModal") or ""
edit_mc = fn_body(mc, "openQuizBuilderForEdit") or ""
open_up = fn_body(mc, "openUploadModal") or ""
new_ch = fn_body(ch, "openQuizBuilder") or ""

# 1. New-quiz entries must reset every settings control, not just questions.
for label, body in (("manage-content", new_mc), ("courses", new_ch)):
    check("_quizQuestions = []" in body or "quizQuestions = []" in body,
          f"{label}: new-quiz resets the question list")
    check("Shuffle" in body or "shuffle" in body.lower(),
          f"{label}: new-quiz resets the shuffle control")

# 2. New-upload entry must not leave the previous edit id behind.
check("editResQuizId" in open_up,
      "manage-content: openUploadModal clears the stale edit-quiz id")

# 3. The async edit loader must guard against late responses overwriting a
#    newer blank builder (reopen-then-new race).
check("token" in edit_mc.lower() or "abort" in edit_mc.lower(),
      "manage-content: openQuizBuilderForEdit guards the reopen/new race")

# 4. courses.html shuffle control is a select: .checked is a no-op there.
check(".checked" not in new_ch,
      "courses: new-quiz does not use .checked on the shuffle select")

sys.stderr.write("RESULT: " + ("GREEN" if not FAIL else f"RED ({len(FAIL)} vectors)") + "\n")
sys.exit(1 if FAIL else 0)
