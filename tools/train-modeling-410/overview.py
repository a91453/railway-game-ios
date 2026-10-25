import sys
from PIL import Image, ImageDraw, ImageFont
font = ImageFont.truetype('/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc', 26)
rows=[("通勤電聯車","style-commuter","front"),("城際特急（長鼻）","set-emu3000","front"),("紅臉特急","set-puyuma","front"),("區間車","set-emu800","front"),("捷運","set-metroC381","front"),("機車牽引的客車（側面）","set-BLUE","side"),("柴油客車單節","set-dieselRailcar","front"),("高鐵（程序樣式）","style-highSpeed","front")]
W=640;H=230;pad=12
sheet=Image.new('RGB',(pad+2*(W+pad),40+len(rows)*(H+44)),(236,238,246))
d=ImageDraw.Draw(sheet)
d.text((pad,6),"之前",fill='black',font=font);d.text((2*pad+W,6),"之後（決策 410）",fill='black',font=font)
for r,(label,key,view) in enumerate(rows):
    y=40+r*(H+44); d.text((pad,y+4),label,fill='black',font=font)
    for c,tag in enumerate(["before","after"]):
        im=Image.open(f"{sys.argv[1]}/png/{key}-{tag}-{view}.png").convert('RGBA')
        if view=="side": im=im.crop((int(im.width*0.42),0,im.width,im.height))
        im=im.crop(im.getbbox())
        s=min((W-20)/im.width,(H-10)/im.height); im=im.resize((int(im.width*s),int(im.height*s)),Image.LANCZOS)
        cell=Image.new('RGBA',(W,H),'white'); cell.alpha_composite(im,((W-im.width)//2,(H-im.height)//2))
        sheet.paste(cell,(pad+c*(W+pad),y+38),cell)
sheet.save(sys.argv[2],optimize=True); print(sheet.size)
