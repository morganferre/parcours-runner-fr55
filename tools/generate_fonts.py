"""
Generates the watch digit fonts (BMFont .fnt + .png format) from
Bahnschrift, the condensed DIN font shipped with Windows.

The FR55 only has 37 px (NUMBER_MILD) or 79 px (NUMBER_MEDIUM) digits:
nothing in between. These fonts fill the gap.

Usage: python tools/generate_fonts.py   (needs Pillow: pip install pillow)
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "resources" / "fonts"
TTF = Path("C:/Windows/Fonts/bahnschrift.ttf")
CHARS = "0123456789:.-/ "

# name, font size (px), Bahnschrift weight
FONTS = [
    ("digits_large", 66, b"Bold"),
    ("digits_medium", 40, b"SemiBold"),
]


def generate(name, size, weight):
    font = ImageFont.truetype(str(TTF), size)
    try:
        font.set_variation_by_name(weight)
    except Exception:
        pass
    ascent, descent = font.getmetrics()
    line_h = ascent + descent

    # Size of each character
    glyphs = []
    for ch in CHARS:
        l, t, r, b = font.getbbox(ch)
        adv = int(round(font.getlength(ch)))
        glyphs.append((ch, l, t, r, b, adv))

    # Sheet: one row, 2 px between characters
    width = sum(max(1, r - l) + 2 for _, l, t, r, b, _ in glyphs) + 2
    height = line_h + 2
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))

    lines = []
    x = 1
    for ch, l, t, r, b, adv in glyphs:
        w = max(1, r - l)
        h = max(1, b - t)
        if ch != " ":
            # No antialiasing: the FR55 only has 8 colors, half-tones would turn into blotches.
            mask = Image.new("L", (w, h), 0)
            ImageDraw.Draw(mask).text((-l, -t), ch, font=font, fill=255)
            mask = mask.point(lambda v: 255 if v >= 128 else 0)
            img.paste((255, 255, 255, 255), (x, 1), mask)
        lines.append(f"char id={ord(ch)} x={x} y=1 width={w} height={h} "
                     f"xoffset={l} yoffset={t} xadvance={adv} page=0 chnl=15")
        x += w + 2

    OUT.mkdir(parents=True, exist_ok=True)
    img.save(OUT / f"{name}.png")
    fnt = [
        f'info face="{name}" size={size} bold=0 italic=0 charset="" unicode=1 stretchH=100 '
        f'smooth=0 aa=1 padding=0,0,0,0 spacing=2,2 outline=0',
        f"common lineHeight={line_h} base={ascent} scaleW={width} scaleH={height} pages=1 packed=0 "
        f"alphaChnl=0 redChnl=4 greenChnl=4 blueChnl=4",
        f'page id=0 file="{name}.png"',
        f"chars count={len(lines)}",
    ] + lines
    (OUT / f"{name}.fnt").write_text("\n".join(fnt) + "\n", encoding="utf-8")
    l, t, r, b = font.getbbox("0")
    print(f"{name}: digits {b - t} px tall, line {line_h} px, sheet {width}x{height}")


for f in FONTS:
    generate(*f)

(OUT / "fonts.xml").write_text("""<fonts>
    <font id="DigitsLarge" filename="digits_large.fnt" antialias="false"/>
    <font id="DigitsMedium" filename="digits_medium.fnt" antialias="false"/>
</fonts>
""", encoding="utf-8")
