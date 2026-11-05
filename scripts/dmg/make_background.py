"""Draws the DMG window background. Icons sit at (165, 170) and (495, 170), so keep those areas clear.

Usage: python3 make_background.py <folder with handdrawn.py> <output.svg>
"""
import sys

sys.path.insert(0, sys.argv[1])
from handdrawn import PALETTE as P, hand_shape, svg_doc, tilt, wave_bands, wobbly_circle, wobbly_poly

W, H = 660, 400

arrow = hand_shape(
    wobbly_poly(
        [(-62, -10), (26, -13), (22, -31), (66, 0), (22, 31), (26, 13), (-62, 10)],
        jitter=1.6,
        seed=11,
    ),
    P["butter"],
    width=3.2,
    offset=(2.5, 2.5),
)

caption = (
    f'<text x="{W / 2}" y="292" text-anchor="middle" fill="{P["ink"]}" font-size="17" font-weight="700" '
    "font-family=\"'Avenir Next','Nunito','Quicksand',sans-serif\">Drag Spacera to Applications</text>"
)

body = (
    wave_bands(W, H, [336, 368], [P["band4"], P["band3"]], seed=7, amp=7)
    + tilt(arrow, W / 2, 170, -3)
    + tilt(hand_shape(wobbly_circle(0, 0, 9, jitter=0.8, seed=21), P["sage"], width=2.4, offset=(1.5, 1.5)), 58, 58, 0)
    + tilt(hand_shape(wobbly_circle(0, 0, 6, jitter=0.6, seed=22), P["slate"], width=2.2, offset=(1.2, 1.2)), 606, 74, 0)
    + tilt(hand_shape(wobbly_circle(0, 0, 5, jitter=0.5, seed=23), P["peach"], width=2.0, offset=(1.0, 1.0)), 330, 58, 0)
    + caption
)

with open(sys.argv[2], "w") as f:
    f.write(svg_doc(W, H, body, bg=P["cream"]))
