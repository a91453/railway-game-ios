"""Tests of frames.py on disassemblies written out here (decision 590).

Run: python3 -I -m unittest discover -s tools/stack-frames -p 'test_*.py'
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import frames  # noqa: E402

# objdump -d --no-show-raw-insn of x86_64 code: a frame taken in the
# prologue, one past a call (not the prologue's), and a small one.
X86 = """
Disassembly of section .text:

0000000000001000 <$s16GamePresentation11GameSessionC5applyyyF>:
    1000:	push   %rbp
    1001:	mov    %rsp,%rbp
    1004:	push   %r15
    1006:	sub    $0xf018,%rsp
    100d:	mov    %rdi,%r13
    1010:	call   2000 <swift_retain>

0000000000001100 <$s16GamePresentation11GameSessionC4tinyyyF>:
    1100:	push   %rbp
    1101:	sub    $0x28,%rsp
    1105:	ret

0000000000001200 <$s16GamePresentation11GameSessionC5laterSiyF>:
    1200:	push   %rbp
    1201:	call   2000 <swift_retain>
    1206:	sub    $0x9000,%rsp
"""

# otool -tV of arm64 code: a frame past a page (___chkstk_darwin with the
# size over 16 in x15), one in two parts (lsl #12), and a small one.
ARM = """
RailwayGame.debug.dylib:
(__TEXT,__text) section
_$s11RailwayGame7MapViewV9timedBodyQrvgyyXEfU_:
0000000000004000	stp	x28, x27, [sp, #-0x60]!
0000000000004004	mov	x29, sp
0000000000004008	mov	x15, #0x1a2c
000000000000400c	movk	x15, #0x1, lsl #16
0000000000004010	bl	___chkstk_darwin
0000000000004014	sub	sp, sp, x15, lsl #4
0000000000004018	bl	_swift_retain
_$s11RailwayGame15MapBuildConfirmV4bodyQrvg:
0000000000005000	stp	x29, x30, [sp, #-0x10]!
0000000000005004	sub	sp, sp, #0x2, lsl #12
0000000000005008	sub	sp, sp, #0x340
000000000000500c	bl	_swift_retain
_$s11RailwayGame4TinyV4bodyQrvg:
0000000000006000	sub	sp, sp, #0x30
0000000000006004	ret
"""


class FramesTests(unittest.TestCase):
    def test_x86_frames_are_read_from_the_prologue(self):
        found = frames.x86_frames(X86.splitlines())
        self.assertEqual(found["$s16GamePresentation11GameSessionC5applyyyF"], 0xF018)
        self.assertEqual(found["$s16GamePresentation11GameSessionC4tinyyyF"], 0x28)
        self.assertNotIn("$s16GamePresentation11GameSessionC5laterSiyF", found, "past a call is not the prologue")

    def test_arm_frames_count_chkstk_and_both_parts(self):
        found = frames.arm_frames(ARM.splitlines())
        self.assertEqual(found["_$s11RailwayGame7MapViewV9timedBodyQrvgyyXEfU_"], (0x1A2C | 0x10000) * 16)
        self.assertEqual(found["_$s11RailwayGame15MapBuildConfirmV4bodyQrvg"], 0x2000 + 0x340)
        self.assertEqual(found["_$s11RailwayGame4TinyV4bodyQrvg"], 0x30)

    def test_the_report_lists_new_frames_over_the_threshold_only(self):
        found = {"big": 40_000, "known": 50_000, "small": 1_000}
        text = frames.report(found, "Frames", {"known"}, 32 * 1024, 2)
        new, largest = text.split("largest frames:")
        self.assertIn("`big`", new)
        self.assertNotIn("`known`", new)
        self.assertNotIn("`small`", new)
        self.assertIn("`known`", largest)
        self.assertIn("`big`", largest)
        self.assertNotIn("`small`", largest, "only the top 2")
        self.assertIn("No new frame", frames.report(found, "Frames", {"big", "known"}, 32 * 1024, 2))


if __name__ == "__main__":
    unittest.main()
