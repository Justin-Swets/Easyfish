"""EasyFish logo: writes two SVGs (icon-only avatar and with wordmark) and renders them to PNG with Edge.

Original artwork (no game assets): a red-and-white bobber in rippling water at sunset, inside a gold frame.
Run from the repo root:  python branding/make_logo.py
"""
import os
import subprocess
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
S = 1024           # design size; exported PNGs are downscaled from this for clean edges
HORIZON = 560


def sparkle(x, y, r, opacity):
    """Four-point star."""
    t = r * 0.22
    return (f'<path d="M{x},{y - r} Q{x + t},{y - t} {x + r},{y} Q{x + t},{y + t} {x},{y + r} '
            f'Q{x - t},{y + t} {x - r},{y} Q{x - t},{y - t} {x},{y - r}Z" fill="#fff6d8" opacity="{opacity}"/>')


def svg(wordmark: bool) -> str:
    # With the wordmark the scene moves up a little to leave room for the name
    lift = 70 if wordmark else 0
    hz = HORIZON - lift
    bx, by = 512, hz + 50            # bobber centre, just below the horizon
    r = 118                          # bobber size
    rx, ry = 100, 128                # egg-shaped like a real float, not a ball

    ripples = "".join(
        f'<ellipse cx="{bx}" cy="{by + 58}" rx="{rx}" ry="{ry}" fill="none" stroke="#bdefff" '
        f'stroke-width="{w}" opacity="{o}"/>'
        for rx, ry, w, o in [(175, 36, 9, 0.75), (265, 56, 7, 0.45), (360, 78, 6, 0.25)])

    glints = "".join(
        f'<rect x="{512 - w / 2}" y="{hz + dy}" width="{w}" height="7" rx="3.5" fill="#ffcf73" opacity="{o}"/>'
        for dy, w, o in [(150, 230, 0.55), (180, 170, 0.45), (208, 110, 0.35), (232, 56, 0.25)])

    word = ""
    if wordmark:
        word = f'''
  <rect x="24" y="{S - 250}" width="{S - 48}" height="226" fill="url(#shade)"/>
  <text x="512" y="{S - 92}" text-anchor="middle" font-family="Georgia, 'Times New Roman', serif"
        font-weight="bold" font-size="170" letter-spacing="2"
        fill="url(#goldText)" stroke="#2a1606" stroke-width="10" paint-order="stroke fill">EasyFish</text>'''

    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{S}" height="{S}" viewBox="0 0 {S} {S}">
  <defs>
    <linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#0d1730"/>
      <stop offset="0.55" stop-color="#26406e"/>
      <stop offset="0.85" stop-color="#9c5a52"/>
      <stop offset="1" stop-color="#f09a4e"/>
    </linearGradient>
    <linearGradient id="water" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#1a7a9c"/>
      <stop offset="0.45" stop-color="#0c4a68"/>
      <stop offset="1" stop-color="#051e30"/>
    </linearGradient>
    <radialGradient id="sun" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="#fff0b0"/>
      <stop offset="0.6" stop-color="#ffc85a"/>
      <stop offset="1" stop-color="#f28c38"/>
    </radialGradient>
    <radialGradient id="glow" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="#ffb566" stop-opacity="0.55"/>
      <stop offset="1" stop-color="#ffb566" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="red" cx="0.38" cy="0.3" r="0.8">
      <stop offset="0" stop-color="#ff5a5f"/>
      <stop offset="0.6" stop-color="#d11f35"/>
      <stop offset="1" stop-color="#7d0f1e"/>
    </radialGradient>
    <radialGradient id="white" cx="0.38" cy="0.2" r="0.9">
      <stop offset="0" stop-color="#ffffff"/>
      <stop offset="0.7" stop-color="#e3e8ee"/>
      <stop offset="1" stop-color="#9aa6b3"/>
    </radialGradient>
    <linearGradient id="gold" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#ffe29a"/>
      <stop offset="0.5" stop-color="#d49a2f"/>
      <stop offset="1" stop-color="#8a5a14"/>
    </linearGradient>
    <linearGradient id="goldText" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#fff1b8"/>
      <stop offset="0.55" stop-color="#f2c04d"/>
      <stop offset="1" stop-color="#b87a1c"/>
    </linearGradient>
    <linearGradient id="shade" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#03111c" stop-opacity="0"/>
      <stop offset="0.45" stop-color="#03111c" stop-opacity="0.75"/>
      <stop offset="1" stop-color="#03111c" stop-opacity="0.9"/>
    </linearGradient>
    <clipPath id="frame"><rect x="24" y="24" width="{S - 48}" height="{S - 48}" rx="120"/></clipPath>
    <clipPath id="aboveWater"><rect x="0" y="0" width="{S}" height="{hz}"/></clipPath>
    <clipPath id="bobber"><ellipse cx="{bx}" cy="{by}" rx="{rx}" ry="{ry}"/></clipPath>
    <clipPath id="bobberTop"><rect x="0" y="0" width="{S}" height="{by - 4}"/></clipPath>
    <clipPath id="bobberDry"><rect x="0" y="0" width="{S}" height="{by + 62}"/></clipPath>
  </defs>

  <rect width="{S}" height="{S}" fill="#0a1222"/>
  <g clip-path="url(#frame)">
    <rect width="{S}" height="{hz}" fill="url(#sky)"/>
    <circle cx="512" cy="{hz}" r="330" fill="url(#glow)"/>
    <circle cx="512" cy="{hz + 10}" r="205" fill="url(#sun)" clip-path="url(#aboveWater)"/>
    {sparkle(215, 150 - lift / 2, 22, 0.9)}{sparkle(820, 230 - lift / 2, 16, 0.75)}{sparkle(300, 300 - lift / 2, 10, 0.6)}
    <rect y="{hz}" width="{S}" height="{S - hz}" fill="url(#water)"/>
    <rect y="{hz}" width="{S}" height="6" fill="#ffd27a" opacity="0.55"/>
    {glints}
    {ripples}

    <!-- fishing line from the top-right corner to the bobber stem -->
    <path d="M 1010 -10 Q 820 150 {bx + 4} {by - ry - 42}" fill="none" stroke="#f4f8ff" stroke-width="6" opacity="0.9"/>

    <!-- bobber: shadow, then body above the waterline -->
    <ellipse cx="{bx}" cy="{by + 64}" rx="{rx + 26}" ry="22" fill="#021019" opacity="0.55"/>
    <g clip-path="url(#bobberDry)">
      <ellipse cx="{bx}" cy="{by}" rx="{rx}" ry="{ry}" fill="url(#white)"/>
      <g clip-path="url(#bobber)">
        <path d="M0 0 H{S} V{by + 6} Q{bx} {by + 26} 0 {by + 6} Z" fill="url(#red)"/>
      </g>
      <ellipse cx="{bx}" cy="{by}" rx="{rx}" ry="{ry}" fill="none" stroke="#1b0c10" stroke-width="7"/>
      <ellipse cx="{bx - 36}" cy="{by - 70}" rx="26" ry="42" fill="#ffffff" opacity="0.55"
               transform="rotate(20 {bx - 36} {by - 70})"/>
    </g>
    <!-- waterline across the bobber -->
    <path d="M {bx - rx - 14} {by + 62} Q {bx} {by + 80} {bx + rx + 14} {by + 62}" fill="none" stroke="#bdefff" stroke-width="7" opacity="0.85"/>
    <!-- stem -->
    <rect x="{bx - 11}" y="{by - ry - 44}" width="22" height="54" rx="8" fill="#3a1d12" stroke="#1b0c10" stroke-width="5"/>
    <circle cx="{bx}" cy="{by - ry - 44}" r="14" fill="#f2c04d" stroke="#1b0c10" stroke-width="5"/>
    {word}
  </g>

  <!-- gold frame -->
  <rect x="24" y="24" width="{S - 48}" height="{S - 48}" rx="120" fill="none" stroke="url(#gold)" stroke-width="18"/>
  <rect x="40" y="40" width="{S - 80}" height="{S - 80}" rx="106" fill="none" stroke="#1a1004" stroke-width="4" opacity="0.7"/>
</svg>
'''


def render(name: str, wordmark: bool):
    svg_path = os.path.join(HERE, name + ".svg")
    with open(svg_path, "w", encoding="utf-8") as f:
        f.write(svg(wordmark))
    big = os.path.join(HERE, name + "-1024.png")
    subprocess.run([EDGE, "--headless=new", "--disable-gpu", "--hide-scrollbars", f"--window-size={S},{S}",
                    f"--screenshot={big}", "file:///" + svg_path.replace("\\", "/")],
                   check=True, capture_output=True, timeout=60)
    img = Image.open(big).convert("RGB")
    assert img.size == (S, S), img.size
    for size in (512, 400):
        img.resize((size, size), Image.LANCZOS).save(os.path.join(HERE, f"{name}-{size}.png"), optimize=True)
    print(name, "->", svg_path, "+ PNG 1024/512/400")


if __name__ == "__main__":
    render("easyfish-logo", wordmark=False)
    render("easyfish-logo-wordmark", wordmark=True)
