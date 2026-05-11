"""Wordie app icon generator — pure Pillow, no system deps."""
import os, math

try:
    from PIL import Image, ImageDraw
except ImportError:
    os.system("pip install Pillow")
    from PIL import Image, ImageDraw

BASE = os.path.dirname(os.path.abspath(__file__))

# ── colour palette ──────────────────────────────────────────
BG_START  = (0x3B, 0x82, 0xF6)    # bright blue
BG_MID    = (0x63, 0x66, 0xF1)    # indigo
BG_END    = (0xA8, 0x55, 0xF7)    # purple
WHITE     = (255, 255, 255)
W_STROKE_END = (0xE0, 0xE7, 0xFF)
STAR_START   = (0xFD, 0xE0, 0x47)
STAR_END     = (0xF5, 0x9E, 0x0B)
LINE_ALPHA   = 64   # 0.25 * 255
SHADOW_COLOR = (0, 0, 0, 64)


def lerp_colour(a, b, t):
    """Linear interpolate between two RGB tuples."""
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def draw_gradient(draw, w, h):
    """Vertical + horizontal gradient hybrid — diagonal from top-left."""
    for y in range(h):
        t = y / (h - 1) if h > 1 else 0
        if t < 0.5:
            c = lerp_colour(BG_START, BG_MID, t * 2)
        else:
            c = lerp_colour(BG_MID, BG_END, (t - 0.5) * 2)
        draw.line([(0, y), (w - 1, y)], fill=c)


def draw_w_path(draw, w, h, stroke_w):
    """Draw the stylised 'W' check-mark path."""
    scale_x = w / 512.0
    scale_y = h / 512.0

    points = [
        (120, 230),
        (190, 350),
        (256, 260),
        (310, 350),
        (410, 160),
    ]
    pts = [(p[0] * scale_x, p[1] * scale_y) for p in points]

    # draw shadow first (offset down by stroke_w * 0.15)
    shadow_pts = [(x, y + 12 * scale_y) for x, y in pts]
    draw.line(shadow_pts, fill=(0, 0, 0, 48), width=max(1, int(stroke_w)),
              joint='curve')

    # draw main W
    draw.line(pts, fill=WHITE, width=max(1, int(stroke_w)),
              joint='curve')


def draw_star(draw, cx, cy, size, fill, outer_fill, scale):
    """Draw a 4-point sparkle star."""
    cx *= scale
    cy *= scale
    size *= scale

    outer = size
    inner = size * 0.5

    points = [
        (cx, cy - outer),        # top
        (cx + inner * 0.4, cy - inner),   # inner right top
        (cx + outer, cy),        # right
        (cx + inner * 0.4, cy + inner),   # inner right bottom
        (cx, cy + outer),        # bottom
        (cx - inner * 0.4, cy + inner),   # inner left bottom
        (cx - outer, cy),        # left
        (cx - inner * 0.4, cy - inner),   # inner left top
    ]

    # --- 修复位置：确保 gc 永远只有 4 位 (RGBA) ---
    for i in range(3, 0, -1):
        r = int(size * (0.6 + i * 0.13))
        alpha = int(40 / i)
        # 即使 outer_fill 传进来已经带了 alpha，我们也只取前 3 位 (RGB) 再拼上新的 alpha
        gc = outer_fill[:3] + (alpha,) 
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=gc)

    draw.polygon(points, fill=fill)


def draw_bg_lines(draw, w, h, scale_x, scale_y):
    """Decorative text lines."""
    line_alpha = 64
    lw = max(1, int(16 * scale_x))

    lines = [
        (110, 140, 300, 140),
        (110, 190, 200, 190),
        (350, 140, 400, 140),
        (110, 400, 250, 400),
    ]
    for x1, y1, x2, y2 in lines:
        draw.line([(x1 * scale_x, y1 * scale_y), (x2 * scale_x, y2 * scale_y)],
                  fill=(255, 255, 255, line_alpha), width=lw)


def make_icon(size):
    """Render the icon at <size> × <size> pixels."""
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    scale = size / 512.0

    # 1. rounded-rect clip mask
    mask = Image.new('L', (size, size), 0)
    mask_draw = ImageDraw.Draw(mask)
    r = int(115 * scale)
    mask_draw.rounded_rectangle([(0, 0), (size - 1, size - 1)], r, fill=255)

    # 2. gradient background
    draw_gradient(draw, size, size)

    # 3. bg lines
    draw_bg_lines(draw, size, size, scale, scale)

    # 4. W-mark
    stroke_w = 52 * scale
    draw_w_path(draw, size, size, stroke_w)

    # 5. big star (top-right)
    draw_star(draw, 430, 90, 40, STAR_START + (255,), STAR_END + (120,), scale)

    # 6. small star (bottom-left)
    draw_star(draw, 90, 330, 25, WHITE + (204,), WHITE + (60,), scale)

    # apply rounded mask
    img.putalpha(mask)
    return img


def main():
    icon_sizes = {
        # Android logo + ic_launcher
        'mipmap-mdpi':    48,
        'mipmap-hdpi':    72,
        'mipmap-xhdpi':   96,
        'mipmap-xxhdpi':  144,
        'mipmap-xxxhdpi': 192,
    }

    for density, size in icon_sizes.items():
        d = os.path.join(BASE, 'android', 'app', 'src', 'main', 'res', density)
        os.makedirs(d, exist_ok=True)
        img = make_icon(size)

        img.save(os.path.join(d, 'logo.png'), 'PNG')
        img.save(os.path.join(d, 'ic_launcher.png'), 'PNG')
        print(f'  {density}: {size}×{size} — logo.png + ic_launcher.png')

    # iOS 1024×1024
    ios_d = os.path.join(BASE, 'ios', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset')
    os.makedirs(ios_d, exist_ok=True)
    img = make_icon(1024)
    img.save(os.path.join(ios_d, 'Icon-App-1024x1024@1x.png'), 'PNG')
    print(f'  iOS: 1024×1024 — AppIcon')

    # also save a 512px preview at project root
    preview = make_icon(512)
    preview.save(os.path.join(BASE, 'icon_preview.png'), 'PNG')
    print(f'  Preview: icon_preview.png')
    print('\nDone.  flutter clean && flutter pub get && flutter run')


if __name__ == '__main__':
    main()
