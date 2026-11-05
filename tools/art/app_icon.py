"""Helriders app icon: a gold tyre badge with a steel hub and a stencil H.

Run from the repo root:  python3 tools/art/app_icon.py
Writes art/icon/: icon_512.png (project icon), icon_192.png (Android legacy),
adaptive_fg_432.png / adaptive_bg_432.png / adaptive_mono_432.png (Android
adaptive layers; the badge sits inside the 72dp visible circle) and
helriders.ico (Windows). Drawn at 2048 px and scaled down for clean edges.
Owner-approved design (option A1, refined), 2026-11-05.
"""
import math
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops

FONT = "art/ui/fonts/BlackOpsOne-Regular.ttf"
OUT = "art/icon/"
K = 4; S = 512 * K; C = S / 2
CHAR = (24, 29, 32)
GOLD_HI = (255, 224, 128); GOLD = (225, 180, 65); GOLD_LO = (140, 96, 24)


def font(n): return ImageFont.truetype(FONT, n)
def solid(c): return Image.new("RGBA", (S, S), c if len(c) == 4 else c + (255,))
def clip(img, mask):
    o = Image.new("RGBA", (S, S), (0, 0, 0, 0)); o.paste(img, (0, 0), mask); return o
def vgrad(top, bot, mid=None, mix=0.35):
    g = Image.composite(solid(bot), solid(top), Image.linear_gradient("L").resize((S, S)))
    return Image.blend(g, solid(mid), mix) if mid else g
def gold():
    g = vgrad(GOLD_HI, GOLD_LO, GOLD)
    sheen = Image.new("L", (S, S), 0)
    ImageDraw.Draw(sheen).polygon([(0, S * 0.30), (S * 0.30, 0), (S * 0.46, 0), (0, S * 0.46)], fill=70)
    return Image.composite(solid((255, 246, 214)), g, sheen.filter(ImageFilter.GaussianBlur(S * 0.03)))
def shadow(mask, off, blur, a):
    sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sh.paste((0, 0, 0, 255), (off, off), mask.point(lambda v: v * a // 255))
    return sh.filter(ImageFilter.GaussianBlur(blur))
def shift(mask, dx, dy): return ImageChops.offset(mask, dx, dy)
def bevel(img, mask, w, hi=(255, 250, 225, 150), lo=(60, 35, 5, 150)):
    h = ImageChops.subtract(mask, shift(mask, w, w)); l = ImageChops.subtract(mask, shift(mask, -w, -w))
    img.alpha_composite(clip(solid(hi), h.filter(ImageFilter.GaussianBlur(w / 2))))
    img.alpha_composite(clip(solid(lo), l.filter(ImageFilter.GaussianBlur(w / 2))))
def outline(mask, w): return ImageChops.subtract(mask.filter(ImageFilter.MaxFilter(w * 2 + 1)), mask)


def render(with_background=True):
    """The badge at S x S. Returns (image, monochrome mask: tyre + H)."""
    img=Image.composite(solid((9,11,12)),solid(CHAR),Image.radial_gradient("L").resize((S,S)).point(lambda x:min(255,int(x*0.95)))) if with_background else Image.new("RGBA",(S,S),(0,0,0,0))

    # tyre
    ring=Image.new("L",(S,S),0); d=ImageDraw.Draw(ring)
    ro,ri=0.41*S,0.30*S; rm=(ro+ri)/2; n=18
    d.ellipse((C-ro,C-ro,C+ro,C+ro),fill=255); d.ellipse((C-ri,C-ri,C+ri,C+ri),fill=0)
    d.ellipse((C-rm-2*K,C-rm-2*K,C+rm+2*K,C+rm+2*K),outline=0,width=4*K)
    for i in range(n):
        for (r0,r1,off) in ((ri,rm,0.0),(rm,ro+2*K,0.5)):
            a=(i+off)*math.tau/n
            d.line([(C+math.cos(a-0.035)*r0,C+math.sin(a-0.035)*r0),(C+math.cos(a+0.035)*r1,C+math.sin(a+0.035)*r1)],fill=0,width=6*K)
    for i in range(n*2):
        a=(i+0.25)*math.tau/(n*2); x,y=C+math.cos(a)*ro,C+math.sin(a)*ro
        d.ellipse((x-7*K,y-7*K,x+7*K,y+7*K),fill=0)
    img.alpha_composite(shadow(ring,7*K,9*K,190))
    img.alpha_composite(clip(solid((12,10,6)),outline(ring,2*K)))
    img.alpha_composite(clip(gold(),ring))
    bevel(img,ring,3*K)

    # hub: brushed steel, bevelled rim
    rh=0.265*S
    hub=Image.new("L",(S,S),0); ImageDraw.Draw(hub).ellipse((C-rh,C-rh,C+rh,C+rh),fill=255)
    img.alpha_composite(shadow(hub,5*K,7*K,220))
    steel=vgrad((58,63,68),(20,23,26))
    # brushed: faint concentric rings
    br=Image.new("L",(S,S),0); bd=ImageDraw.Draw(br)
    for r in range(int(rh*0.2),int(rh),3*K): bd.ellipse((C-r,C-r,C+r,C+r),outline=26,width=K)
    steel=Image.composite(solid((90,96,102)),steel,br)
    img.alpha_composite(clip(steel,hub))
    rim=Image.new("L",(S,S),0); ImageDraw.Draw(rim).ellipse((C-rh,C-rh,C+rh,C+rh),outline=255,width=7*K)
    img.alpha_composite(clip(vgrad((150,156,162),(40,44,48)),rim))
    inner=Image.new("L",(S,S),0); r2=rh-7*K; ImageDraw.Draw(inner).ellipse((C-r2,C-r2,C+r2,C+r2),outline=255,width=2*K)
    img.alpha_composite(clip(solid((8,9,10,200)),inner))

    # lug nuts
    nuts=Image.new("L",(S,S),0); nd=ImageDraw.Draw(nuts)
    for i in range(5):
        a=-math.pi/2+math.pi/5+i*math.tau/5; x,y=C+math.cos(a)*0.215*S,C+math.sin(a)*0.215*S
        nd.regular_polygon((x,y,0.021*S),6,fill=255)
    img.alpha_composite(shadow(nuts,2*K,2*K,200))
    img.alpha_composite(clip(vgrad((200,204,208),(70,74,78)),nuts))
    bevel(img,nuts,2*K,(255,255,255,170),(0,0,0,170))

    # H
    H=Image.new("L",(S,S),0); Hd=ImageDraw.Draw(H); f=font(int(0.43*S))
    bb=Hd.textbbox((0,0),"H",font=f); Hd.text((C-(bb[2]+bb[0])/2,C-(bb[3]+bb[1])/2),"H",font=f,fill=255)
    img.alpha_composite(shadow(H,6*K,5*K,240))
    img.alpha_composite(clip(solid((14,11,6)),outline(H,2*K)))
    img.alpha_composite(clip(gold(),H))
    bevel(img,H,3*K)

    return img, ImageChops.lighter(ring, H)


def background():
    return Image.composite(solid((9, 11, 12)), solid(CHAR),
        Image.radial_gradient("L").resize((S, S)).point(lambda x: min(255, int(x * 0.95))))


def main():
    full, _ = render(True)
    full.resize((512, 512), Image.LANCZOS).save(OUT + "icon_512.png")
    full.resize((192, 192), Image.LANCZOS).save(OUT + "icon_192.png")
    full.resize((256, 256), Image.LANCZOS).save(OUT + "helriders.ico", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    badge, mono = render(False)
    # Adaptive layers: 432 px = 108dp; the launcher shows the middle 72dp (288 px).
    # The badge (0.83 of the canvas wide) is scaled to about 276 px across.
    inner = int(432 * 0.77)
    def layer(im):
        out = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
        out.alpha_composite(im.resize((inner, inner), Image.LANCZOS), ((432 - inner) // 2, (432 - inner) // 2))
        return out
    layer(badge).save(OUT + "adaptive_fg_432.png")
    background().resize((432, 432), Image.LANCZOS).convert("RGB").save(OUT + "adaptive_bg_432.png")
    white = Image.new("RGBA", (S, S), (255, 255, 255, 0)); white.putalpha(mono)
    layer(white).save(OUT + "adaptive_mono_432.png")


if __name__ == "__main__":
    main()
