"""EasyFish logo, fantasy-MMO style: writes two SVGs (icon-only avatar and with wordmark) and renders PNGs with Edge.

Original artwork, no game assets: a hand-painted style float with a riveted brass band and feather plume, at a
fantasy sunset, in a bevelled bronze frame with corner gems. Lettering is Cinzel (SIL Open Font License,
branding/fonts/OFL.txt), embedded in the SVG so it renders the same anywhere.

Run from the repo root:  python branding/make_logo.py
"""
import base64
import math
import os
import subprocess
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
S = 1024            # design size; PNGs are downscaled from this for clean edges
IN = 50             # inner edge of the frame
HORIZON = 560

with open(os.path.join(HERE, "fonts", "Cinzel.ttf"), "rb") as f:
    FONT = base64.b64encode(f.read()).decode("ascii")


def sparkle(x, y, r, opacity, color="#fff4cc"):
    t = r * 0.2
    return (f'<path d="M{x},{y - r} Q{x + t},{y - t} {x + r},{y} Q{x + t},{y + t} {x},{y + r} '
            f'Q{x - t},{y + t} {x - r},{y} Q{x - t},{y - t} {x},{y - r}Z" fill="{color}" opacity="{opacity}"/>')


def feather(x, y, angle, length, width, grad):
    """A feather pointing up from (x, y), rotated by angle degrees."""
    L, w = length, width
    barbs = "".join(
        f'<path d="M0,{-L * k} L{side * w * 0.8},{-L * k - 16}" stroke="#12303a" stroke-width="3" opacity="0.5"/>'
        for k in (0.35, 0.5, 0.65, 0.8) for side in (-1, 1))
    return f'''<g transform="translate({x} {y}) rotate({angle})">
      <path d="M0,0 C{w},{-L * 0.25} {w * 1.1},{-L * 0.7} 0,{-L} C{-w * 1.1},{-L * 0.7} {-w},{-L * 0.25} 0,0 Z"
            fill="url(#{grad})" stroke="#140a06" stroke-width="7"/>
      {barbs}
      <path d="M0,0 L0,{-L * 0.96}" stroke="#fff3d6" stroke-width="5" stroke-linecap="round" opacity="0.9"/>
    </g>'''


def svg(wordmark: bool) -> str:
    lift = 80 if wordmark else 0
    hz = HORIZON - lift
    bx, by = 512, hz + 36           # float centre, sitting in the water
    rx, ry = 112, 134               # egg-shaped body
    band = 15                       # half-height of the brass band
    dry = by + 104                  # waterline: low enough that the pale lower half shows

    def curve_y(dx):                # band centre line: dips 10px in the middle
        t = (dx / (rx + 10) + 1) / 2
        return by + 40 * t * (1 - t)

    rivets = "".join(
        f'<circle cx="{bx + dx}" cy="{curve_y(dx):.1f}" r="6.5" fill="url(#rivet)" stroke="#2a1504" stroke-width="2.5"/>'
        for dx in (-78, -39, 0, 39, 78))

    ripples = "".join(
        f'<ellipse cx="{bx}" cy="{dry + 4}" rx="{a}" ry="{b}" fill="none" stroke="#c9fbff" stroke-width="{w}" opacity="{o}"/>'
        for a, b, w, o in [(170, 32, 10, 0.85), (262, 52, 7, 0.5), (360, 74, 6, 0.28)])

    glints = "".join(
        f'<rect x="{512 - w / 2}" y="{hz + dy}" width="{w}" height="7" rx="3.5" fill="#ffd98a" opacity="{o}"/>'
        for dy, w, o in [(150, 240, 0.6), (180, 176, 0.5), (208, 112, 0.38), (232, 56, 0.26)])

    rays = "".join(
        f'<path d="M512,{hz} L{512 + 900 * math.cos(math.radians(a - 3)):.0f},{hz - 900 * math.sin(math.radians(a - 3)):.0f} '
        f'L{512 + 900 * math.cos(math.radians(a + 3)):.0f},{hz - 900 * math.sin(math.radians(a + 3)):.0f} Z" '
        f'fill="#ffe2a8" opacity="0.07"/>'
        for a in (28, 52, 76, 104, 128, 152))

    # Mountains and pines on the horizon, leaving the sun open in the middle
    back = (f'<path d="M{IN},{hz} L{IN},{hz - 150} L140,{hz - 205} L230,{hz - 130} L300,{hz - 175} L380,{hz - 80} '
            f'L420,{hz} Z M{S - IN},{hz} L{S - IN},{hz - 140} L890,{hz - 195} L800,{hz - 120} L730,{hz - 165} '
            f'L650,{hz - 70} L610,{hz} Z" fill="#3a2a66"/>')
    front = (f'<path d="M{IN},{hz} L{IN},{hz - 90} L110,{hz - 120} L190,{hz - 70} L260,{hz - 95} L330,{hz - 30} '
             f'L360,{hz} Z M{S - IN},{hz} L{S - IN},{hz - 80} L910,{hz - 112} L840,{hz - 62} L770,{hz - 88} '
             f'L700,{hz - 26} L670,{hz} Z" fill="#1c1538"/>')
    pines = "".join(
        f'<path d="M{x},{hz - h} L{x + h * 0.28},{hz - h * 0.45} L{x + h * 0.18},{hz - h * 0.45} L{x + h * 0.34},{hz} '
        f'L{x - h * 0.34},{hz} L{x - h * 0.18},{hz - h * 0.45} L{x - h * 0.28},{hz - h * 0.45} Z" fill="#120d26"/>'
        for x, h in [(80, 150), (130, 110), (175, 135), (245, 95), (300, 70),
                     (944, 145), (895, 105), (850, 130), (780, 90), (725, 66)])

    word = ""
    if wordmark:
        text = ('font-family="EF Cinzel" font-weight="900" font-size="160" text-anchor="middle" '
                f'textLength="800" lengthAdjust="spacingAndGlyphs" x="512" y="{S - 118}"')
        word = f'''
    <rect x="{IN}" y="{S - 300}" width="{S - 2 * IN}" height="{300 - IN}" fill="url(#shade)"/>
    <path d="M150,{S - 88} H874" stroke="url(#goldLine)" stroke-width="5"/>
    <path d="M512,{S - 100} l14,12 l-14,12 l-14,-12 Z" fill="#ffd25a" stroke="#2a1504" stroke-width="3"/>
    <text {text} fill="#ff9a2e" filter="url(#glow)" opacity="0.7">EasyFish</text>
    <text {text} fill="#140a02" stroke="#140a02" stroke-width="26" stroke-linejoin="round" filter="url(#drop)">EasyFish</text>
    <text {text} fill="#6e3a0a" transform="translate(0 6)">EasyFish</text>
    <text {text} fill="url(#goldText)" stroke="#3a1f05" stroke-width="3">EasyFish</text>
    <text {text} fill="url(#gloss)">EasyFish</text>'''

    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{S}" height="{S}" viewBox="0 0 {S} {S}">
  <defs>
    <style>@font-face {{ font-family: "EF Cinzel"; font-weight: 400 900;
      src: url(data:font/ttf;base64,{FONT}) format("truetype"); }}</style>
    <linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#0a1238"/>
      <stop offset="0.45" stop-color="#3a2a80"/>
      <stop offset="0.75" stop-color="#b33f7c"/>
      <stop offset="1" stop-color="#ff9a3c"/>
    </linearGradient>
    <linearGradient id="water" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#34c6cf"/>
      <stop offset="0.3" stop-color="#138aa6"/>
      <stop offset="0.7" stop-color="#0a4368"/>
      <stop offset="1" stop-color="#051a33"/>
    </linearGradient>
    <radialGradient id="sun" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="#fff7c8"/>
      <stop offset="0.55" stop-color="#ffcf5a"/>
      <stop offset="1" stop-color="#ff7a2a"/>
    </radialGradient>
    <radialGradient id="halo" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="#ffb35a" stop-opacity="0.65"/>
      <stop offset="1" stop-color="#ff5aa0" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="red" cx="0.35" cy="0.25" r="0.85">
      <stop offset="0" stop-color="#ff6a4a"/>
      <stop offset="0.45" stop-color="#d81e2c"/>
      <stop offset="1" stop-color="#5c0712"/>
    </radialGradient>
    <radialGradient id="ivory" cx="0.35" cy="0.1" r="1">
      <stop offset="0" stop-color="#fff6de"/>
      <stop offset="0.6" stop-color="#e6cfa0"/>
      <stop offset="1" stop-color="#8f6d3e"/>
    </radialGradient>
    <linearGradient id="brass" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#fff0b0"/>
      <stop offset="0.45" stop-color="#e2a53a"/>
      <stop offset="1" stop-color="#7a4510"/>
    </linearGradient>
    <radialGradient id="rivet" cx="0.35" cy="0.3" r="0.7">
      <stop offset="0" stop-color="#fff6d0"/>
      <stop offset="1" stop-color="#a8691a"/>
    </radialGradient>
    <linearGradient id="featherTeal" x1="0" y1="1" x2="0" y2="0">
      <stop offset="0" stop-color="#0c5e6e"/>
      <stop offset="0.6" stop-color="#2fd6c4"/>
      <stop offset="1" stop-color="#c8fff4"/>
    </linearGradient>
    <linearGradient id="featherGold" x1="0" y1="1" x2="0" y2="0">
      <stop offset="0" stop-color="#8a4e0c"/>
      <stop offset="0.6" stop-color="#ffc43d"/>
      <stop offset="1" stop-color="#fff2b8"/>
    </linearGradient>
    <linearGradient id="frameGold" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#fff2c0"/>
      <stop offset="0.25" stop-color="#f0b84a"/>
      <stop offset="0.6" stop-color="#9a5e18"/>
      <stop offset="0.8" stop-color="#d89a38"/>
      <stop offset="1" stop-color="#4a2a08"/>
    </linearGradient>
    <radialGradient id="gem" cx="0.35" cy="0.3" r="0.8">
      <stop offset="0" stop-color="#d6fffa"/>
      <stop offset="0.4" stop-color="#2fd6c4"/>
      <stop offset="1" stop-color="#064a52"/>
    </radialGradient>
    <linearGradient id="goldText" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#fffbe0"/>
      <stop offset="0.35" stop-color="#ffd760"/>
      <stop offset="0.7" stop-color="#e0901c"/>
      <stop offset="1" stop-color="#8e4e0a"/>
    </linearGradient>
    <linearGradient id="gloss" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#ffffff" stop-opacity="0.55"/>
      <stop offset="0.42" stop-color="#ffffff" stop-opacity="0.1"/>
      <stop offset="0.43" stop-color="#ffffff" stop-opacity="0"/>
    </linearGradient>
    <linearGradient id="goldLine" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#ffd25a" stop-opacity="0"/>
      <stop offset="0.5" stop-color="#ffd25a"/>
      <stop offset="1" stop-color="#ffd25a" stop-opacity="0"/>
    </linearGradient>
    <linearGradient id="shade" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#030a14" stop-opacity="0"/>
      <stop offset="0.4" stop-color="#030a14" stop-opacity="0.7"/>
      <stop offset="1" stop-color="#030a14" stop-opacity="0.92"/>
    </linearGradient>
    <filter id="glow" x="-20%" y="-50%" width="140%" height="200%"><feGaussianBlur stdDeviation="16"/></filter>
    <filter id="drop" x="-10%" y="-30%" width="120%" height="170%">
      <feDropShadow dx="0" dy="8" stdDeviation="7" flood-color="#000" flood-opacity="0.85"/>
    </filter>
    <clipPath id="inner"><rect x="{IN}" y="{IN}" width="{S - 2 * IN}" height="{S - 2 * IN}" rx="84"/></clipPath>
    <clipPath id="aboveWater"><rect x="0" y="0" width="{S}" height="{hz}"/></clipPath>
    <clipPath id="egg"><ellipse cx="{bx}" cy="{by}" rx="{rx}" ry="{ry}"/></clipPath>
    <clipPath id="dry"><rect x="0" y="0" width="{S}" height="{dry}"/></clipPath>
  </defs>

  <rect width="{S}" height="{S}" fill="#06080e"/>

  <!-- bevelled bronze frame -->
  <rect x="14" y="14" width="{S - 28}" height="{S - 28}" rx="116" fill="url(#frameGold)" stroke="#1a0e02" stroke-width="6"/>
  <rect x="26" y="26" width="{S - 52}" height="{S - 52}" rx="104" fill="none" stroke="#fff3c8" stroke-width="3" opacity="0.55"/>
  <rect x="{IN - 6}" y="{IN - 6}" width="{S - 2 * IN + 12}" height="{S - 2 * IN + 12}" rx="90" fill="#1a0e02"/>

  <g clip-path="url(#inner)">
    <rect width="{S}" height="{hz}" fill="url(#sky)"/>
    {rays}
    <circle cx="512" cy="{hz}" r="360" fill="url(#halo)"/>
    <circle cx="512" cy="{hz + 12}" r="190" fill="url(#sun)" clip-path="url(#aboveWater)"/>
    {sparkle(200, 170 - lift * 0.4, 24, 0.95)}{sparkle(830, 240 - lift * 0.4, 17, 0.85)}{sparkle(300, 310 - lift * 0.4, 11, 0.7)}{sparkle(700, 140 - lift * 0.4, 9, 0.6)}
    {back}{front}{pines}
    <rect y="{hz}" width="{S}" height="{S - hz}" fill="url(#water)"/>
    <rect y="{hz}" width="{S}" height="5" fill="#ffe1a0" opacity="0.7"/>
    {glints}
    {ripples}
    {sparkle(250, hz + 120, 14, 0.8, "#c9fbff")}{sparkle(790, hz + 150, 11, 0.7, "#c9fbff")}

    <!-- fishing line -->
    <path d="M 1000 40 Q 820 160 {bx + 6} {by - ry - 52}" fill="none" stroke="#f6fbff" stroke-width="6" opacity="0.9"/>

    <!-- float -->
    <ellipse cx="{bx}" cy="{dry + 2}" rx="{rx + 30}" ry="22" fill="#021019" opacity="0.6"/>
    <g clip-path="url(#dry)">
      <ellipse cx="{bx}" cy="{by}" rx="{rx}" ry="{ry}" fill="url(#ivory)"/>
      <g clip-path="url(#egg)">
        <path d="M{bx - rx - 10},0 H{bx + rx + 10} V{by - band} Q{bx},{by + 20 - band} {bx - rx - 10},{by - band} Z" fill="url(#red)"/>
        <path d="M{bx - rx - 10},{by - band} Q{bx},{by + 20 - band} {bx + rx + 10},{by - band} V{by + band} Q{bx},{by + 20 + band} {bx - rx - 10},{by + band} Z"
              fill="url(#brass)" stroke="#2a1504" stroke-width="4"/>
        {rivets}
        <ellipse cx="{bx - 16}" cy="{by}" rx="{rx}" ry="{ry}" fill="none" stroke="#ffb45a" stroke-width="12" opacity="0.8"/>
        <ellipse cx="{bx + 16}" cy="{by}" rx="{rx}" ry="{ry}" fill="none" stroke="#ff7ab0" stroke-width="8" opacity="0.35"/>
        <path d="M{bx - 72},{by - 30} Q{bx - 78},{by - 100} {bx - 22},{by - 120}" fill="none" stroke="#fff" stroke-width="16"
              stroke-linecap="round" opacity="0.65"/>
        <circle cx="{bx - 8}" cy="{by - 118}" r="8" fill="#fff" opacity="0.7"/>
      </g>
      <ellipse cx="{bx}" cy="{by}" rx="{rx}" ry="{ry}" fill="none" stroke="#140806" stroke-width="12"/>
    </g>
    <path d="M{bx - rx - 18},{dry} Q{bx},{dry + 20} {bx + rx + 18},{dry}" fill="none" stroke="#c9fbff" stroke-width="8" opacity="0.9"/>

    <!-- feathers, brass cap and eyelet -->
    {feather(bx - 6, by - ry - 12, -38, 170, 30, "featherTeal")}
    {feather(bx + 2, by - ry - 12, -12, 130, 24, "featherGold")}
    <path d="M{bx - 30},{by - ry + 10} L{bx + 30},{by - ry + 10} L{bx + 13},{by - ry - 34} L{bx - 13},{by - ry - 34} Z"
          fill="url(#brass)" stroke="#140806" stroke-width="7" stroke-linejoin="round"/>
    <circle cx="{bx}" cy="{by - ry - 50}" r="15" fill="none" stroke="#140806" stroke-width="14"/>
    <circle cx="{bx}" cy="{by - ry - 50}" r="15" fill="none" stroke="#ffd25a" stroke-width="6"/>
    {word}
  </g>

  <!-- inner rim shadow, then corner gems -->
  <rect x="{IN}" y="{IN}" width="{S - 2 * IN}" height="{S - 2 * IN}" rx="84" fill="none" stroke="#000" stroke-width="10" opacity="0.45"/>
  {"".join(f'<g transform="translate({x} {y}) rotate(45)"><rect x="-24" y="-24" width="48" height="48" rx="6" fill="url(#frameGold)" stroke="#1a0e02" stroke-width="5"/><rect x="-14" y="-14" width="28" height="28" rx="4" fill="url(#gem)" stroke="#06282c" stroke-width="3"/></g>' for x, y in [(62, 62), (S - 62, 62), (62, S - 62), (S - 62, S - 62)])}
</svg>
'''


def render(name: str, wordmark: bool):
    svg_path = os.path.join(HERE, name + ".svg")
    with open(svg_path, "w", encoding="utf-8") as f:
        f.write(svg(wordmark))
    big = os.path.join(HERE, name + "-1024.png")
    subprocess.run([EDGE, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--virtual-time-budget=4000",
                    f"--window-size={S},{S}", f"--screenshot={big}", "file:///" + svg_path.replace("\\", "/")],
                   check=True, capture_output=True, timeout=90)
    img = Image.open(big).convert("RGB")
    assert img.size == (S, S), img.size
    for size in (512, 400):
        img.resize((size, size), Image.LANCZOS).save(os.path.join(HERE, f"{name}-{size}.png"), optimize=True)
    print(name, "-> SVG + PNG 1024/512/400")


if __name__ == "__main__":
    render("easyfish-logo", wordmark=False)
    render("easyfish-logo-wordmark", wordmark=True)
