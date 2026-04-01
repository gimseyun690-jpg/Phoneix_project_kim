from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
ASSET_DIR = ROOT / "assets" / "branding"
WEB_ICON_DIR = ROOT / "web" / "icons"
ANDROID_RES_DIR = ROOT / "android" / "app" / "src" / "main" / "res"
WINDOWS_ICON_PATH = ROOT / "windows" / "runner" / "resources" / "app_icon.ico"

BASE_SIZE = 1024
WORK_SIZE = BASE_SIZE * 2

TRANSPARENT = (0, 0, 0, 0)
PRIMARY = (24, 63, 82, 255)
SECONDARY = (38, 122, 117, 255)
ACCENT = (231, 111, 81, 255)
ACCENT_SOFT = (245, 196, 138, 255)
WHITE = (255, 255, 255, 255)
MIST = (248, 244, 236, 255)
MOUNTAIN_BACK = (28, 84, 90, 120)
MOUNTAIN_FRONT = (18, 59, 69, 230)


def lerp(a, b, t):
    return a + (b - a) * t


def lerp_color(color_a, color_b, t):
    return tuple(round(lerp(a, b, t)) for a, b in zip(color_a, color_b))


def cubic_bezier(p0, p1, p2, p3, steps=48):
    points = []
    for index in range(steps + 1):
        t = index / steps
        one_minus_t = 1 - t
        x = (
            one_minus_t**3 * p0[0]
            + 3 * one_minus_t**2 * t * p1[0]
            + 3 * one_minus_t * t**2 * p2[0]
            + t**3 * p3[0]
        )
        y = (
            one_minus_t**3 * p0[1]
            + 3 * one_minus_t**2 * t * p1[1]
            + 3 * one_minus_t * t**2 * p2[1]
            + t**3 * p3[1]
        )
        points.append((x, y))
    return points


def scale_point(x, y):
    return (x * WORK_SIZE, y * WORK_SIZE)


def create_gradient_background():
    image = Image.new("RGBA", (WORK_SIZE, WORK_SIZE), TRANSPARENT)
    draw = ImageDraw.Draw(image)
    top = (28, 82, 102, 255)
    bottom = (39, 150, 140, 255)
    for y in range(WORK_SIZE):
        ratio = y / (WORK_SIZE - 1)
        color = lerp_color(top, bottom, ratio)
        draw.line((0, y, WORK_SIZE, y), fill=color)
    return image


def rounded_mask(radius):
    mask = Image.new("L", (WORK_SIZE, WORK_SIZE), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, WORK_SIZE, WORK_SIZE), radius=radius, fill=255)
    return mask


def build_canopy_paths():
    upper = cubic_bezier(
        scale_point(0.16, 0.47),
        scale_point(0.29, 0.24),
        scale_point(0.60, 0.11),
        scale_point(0.86, 0.28),
    )
    lower = cubic_bezier(
        scale_point(0.20, 0.55),
        scale_point(0.37, 0.43),
        scale_point(0.64, 0.40),
        scale_point(0.83, 0.34),
    )
    return upper, lower


def build_mark(
    canopy_color,
    accent_color,
    line_color,
    pilot_color,
    highlight_color=None,
):
    image = Image.new("RGBA", (WORK_SIZE, WORK_SIZE), TRANSPARENT)
    draw = ImageDraw.Draw(image)

    upper, lower = build_canopy_paths()
    canopy_polygon = upper + list(reversed(lower))
    draw.polygon(canopy_polygon, fill=canopy_color)

    accent_lower = []
    for up, low in zip(upper, lower):
        accent_lower.append(
            (
                lerp(up[0], low[0], 0.34),
                lerp(up[1], low[1], 0.34),
            )
        )
    accent_polygon = upper + list(reversed(accent_lower))
    draw.polygon(accent_polygon, fill=accent_color)

    if highlight_color is not None:
        highlight_path = cubic_bezier(
            scale_point(0.27, 0.41),
            scale_point(0.42, 0.30),
            scale_point(0.59, 0.28),
            scale_point(0.73, 0.33),
            steps=26,
        )
        draw.line(highlight_path, fill=highlight_color, width=26, joint="curve")

    left_anchor = scale_point(0.41, 0.46)
    right_anchor = scale_point(0.60, 0.43)
    center_anchor = scale_point(0.51, 0.44)
    pilot_top = scale_point(0.51, 0.66)
    pilot_bottom = scale_point(0.51, 0.73)

    line_width = 18
    for anchor in (left_anchor, center_anchor, right_anchor):
        draw.line((anchor, pilot_top), fill=line_color, width=line_width)

    draw.line((pilot_top, pilot_bottom), fill=line_color, width=22)

    head_center = scale_point(0.51, 0.76)
    head_radius = int(WORK_SIZE * 0.026)
    draw.ellipse(
        (
            head_center[0] - head_radius,
            head_center[1] - head_radius,
            head_center[0] + head_radius,
            head_center[1] + head_radius,
        ),
        fill=pilot_color,
    )

    harness = [
        scale_point(0.47, 0.69),
        scale_point(0.55, 0.69),
        scale_point(0.58, 0.74),
        scale_point(0.44, 0.74),
    ]
    draw.rounded_rectangle(
        (
            harness[0][0],
            harness[0][1],
            harness[2][0],
            harness[2][1],
        ),
        radius=36,
        fill=pilot_color,
    )

    sweep = Image.new("RGBA", (WORK_SIZE, WORK_SIZE), TRANSPARENT)
    sweep_draw = ImageDraw.Draw(sweep)
    sweep_draw.arc(
        (
            int(WORK_SIZE * 0.22),
            int(WORK_SIZE * 0.48),
            int(WORK_SIZE * 0.78),
            int(WORK_SIZE * 0.93),
        ),
        start=208,
        end=326,
        fill=SECONDARY,
        width=34,
    )
    sweep = sweep.filter(ImageFilter.GaussianBlur(radius=2))
    image.alpha_composite(sweep)

    return image


def create_logo_mark():
    mark = build_mark(
        canopy_color=PRIMARY,
        accent_color=ACCENT,
        line_color=PRIMARY,
        pilot_color=ACCENT,
        highlight_color=ACCENT_SOFT,
    )
    return mark.resize((BASE_SIZE, BASE_SIZE), Image.Resampling.LANCZOS)


def create_launcher_card():
    background = create_gradient_background()
    sun_layer = Image.new("RGBA", (WORK_SIZE, WORK_SIZE), TRANSPARENT)
    sun_draw = ImageDraw.Draw(sun_layer)

    sun_draw.ellipse(
        (
            int(WORK_SIZE * 0.60),
            int(WORK_SIZE * 0.12),
            int(WORK_SIZE * 0.88),
            int(WORK_SIZE * 0.40),
        ),
        fill=(255, 227, 168, 78),
    )
    sun_draw.ellipse(
        (
            int(WORK_SIZE * 0.64),
            int(WORK_SIZE * 0.16),
            int(WORK_SIZE * 0.84),
            int(WORK_SIZE * 0.36),
        ),
        fill=(247, 194, 121, 160),
    )
    background.alpha_composite(sun_layer)

    mountains = Image.new("RGBA", (WORK_SIZE, WORK_SIZE), TRANSPARENT)
    mountain_draw = ImageDraw.Draw(mountains)
    mountain_draw.polygon(
        [
            scale_point(0.00, 0.88),
            scale_point(0.18, 0.62),
            scale_point(0.38, 0.78),
            scale_point(0.56, 0.58),
            scale_point(0.76, 0.77),
            scale_point(1.00, 0.56),
            scale_point(1.00, 1.00),
            scale_point(0.00, 1.00),
        ],
        fill=MOUNTAIN_BACK,
    )
    mountain_draw.polygon(
        [
            scale_point(0.00, 0.98),
            scale_point(0.28, 0.72),
            scale_point(0.44, 0.84),
            scale_point(0.64, 0.68),
            scale_point(0.84, 0.86),
            scale_point(1.00, 0.74),
            scale_point(1.00, 1.00),
            scale_point(0.00, 1.00),
        ],
        fill=MOUNTAIN_FRONT,
    )
    background.alpha_composite(mountains)

    mark = build_mark(
        canopy_color=WHITE,
        accent_color=ACCENT,
        line_color=WHITE,
        pilot_color=MIST,
        highlight_color=ACCENT_SOFT,
    )

    shadow = Image.new("RGBA", (WORK_SIZE, WORK_SIZE), TRANSPARENT)
    shadow.alpha_composite(mark, (0, 0))
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=34))
    shadow_layer = Image.new("RGBA", (WORK_SIZE, WORK_SIZE), TRANSPARENT)
    shadow_layer.alpha_composite(shadow, (0, 56))
    background.alpha_composite(
        Image.new("RGBA", (WORK_SIZE, WORK_SIZE), (0, 0, 0, 0))
    )
    background.alpha_composite(shadow_layer)
    background.alpha_composite(mark)

    mask = rounded_mask(radius=WORK_SIZE // 4)
    background.putalpha(mask)
    return background.resize((BASE_SIZE, BASE_SIZE), Image.Resampling.LANCZOS)


def save_android_icons(icon_image):
    size_by_density = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }

    for folder_name, size in size_by_density.items():
        target_dir = ANDROID_RES_DIR / folder_name
        target_dir.mkdir(parents=True, exist_ok=True)
        target_path = target_dir / "ic_launcher.png"
        icon_image.resize((size, size), Image.Resampling.LANCZOS).save(target_path)


def save_web_icons(icon_image):
    WEB_ICON_DIR.mkdir(parents=True, exist_ok=True)
    icon_image.resize((32, 32), Image.Resampling.LANCZOS).save(ROOT / "web" / "favicon.png")
    icon_image.resize((192, 192), Image.Resampling.LANCZOS).save(WEB_ICON_DIR / "Icon-192.png")
    icon_image.resize((512, 512), Image.Resampling.LANCZOS).save(WEB_ICON_DIR / "Icon-512.png")


def save_windows_icon(icon_image):
    WINDOWS_ICON_PATH.parent.mkdir(parents=True, exist_ok=True)
    icon_image.save(
        WINDOWS_ICON_PATH,
        format="ICO",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )


def main():
    ASSET_DIR.mkdir(parents=True, exist_ok=True)

    mark_image = create_logo_mark()
    launcher_card = create_launcher_card()

    mark_image.save(ASSET_DIR / "app_logo_mark.png")
    launcher_card.save(ASSET_DIR / "app_logo_card.png")

    save_android_icons(launcher_card)
    save_web_icons(launcher_card)
    save_windows_icon(launcher_card)

    print("logo assets generated")


if __name__ == "__main__":
    main()
