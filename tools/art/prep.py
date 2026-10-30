from PIL import Image, ImageDraw, ImageFilter
import base64, io, json
I='../../images/'
def mask_ellipse(size, box, feather):
    m=Image.new('L',size,0); d=ImageDraw.Draw(m); d.ellipse(box,fill=255)
    return m.filter(ImageFilter.GaussianBlur(feather))
def mul_alpha(im, m):
    a=im.getchannel('A'); from PIL import ImageChops
    im.putalpha(ImageChops.multiply(a,m)); return im
# head1
c1=Image.open('cut1.png').crop((240,600,780,1130))
m=mask_ellipse(c1.size,(25,25,525,515),6)
d=ImageDraw.Draw(m); d.polygon([(350,0),(540,0),(540,104),(470,108),(400,120),(356,128),(344,98)],fill=0)
h1=mul_alpha(c1,m); h1=h1.crop(h1.getbbox()); print('h1',h1.size, c1.getbbox())
# head2
c2=Image.open('cut2.png').crop((670,540,870,800))
m=mask_ellipse(c2.size,(5,8,195,242),3)
h2=mul_alpha(c2,m); h2=h2.crop(h2.getbbox()); print('h2',h2.size)
# busts
cu=Image.open('cut1.png'); mm=Image.new('L',cu.size,255); ImageDraw.Draw(mm).polygon([(x+240,y+600) for x,y in [(350,0),(540,0),(540,104),(470,108),(400,120),(356,128),(344,98)]],fill=0)
from PIL import ImageChops
cu.putalpha(ImageChops.multiply(cu.getchannel('A'),mm))
b1=cu.crop((40,600,1240,1700)); b1=b1.resize((b1.width*36//100,b1.height*36//100),Image.LANCZOS)
b2=Image.open('cut2.png').crop((560,540,1060,1300)); b2=b2.resize((b2.width*60//100,b2.height*60//100),Image.LANCZOS)
p1=Image.open(I+'1.jpg').convert('RGB'); p2=Image.open(I+'2.jpg').convert('RGB')
camo=p1.crop((120,1300,330,1560)).resize((105,130),Image.LANCZOS)
tee=p2.crop((800,1020,900,1150)).resize((60,78),Image.LANCZOS)
jeans=p2.crop((780,1280,850,1480)).resize((42,120),Image.LANCZOS)
st=Image.open(I+'3.jpg').convert('RGB').crop((0,150,2000,1275)).resize((1280,720),Image.LANCZOS)
def uri(im,fmt,q):
    b=io.BytesIO(); im.save(b,fmt,quality=q); return 'data:image/%s;base64,'%fmt.lower()+base64.b64encode(b.getvalue()).decode()
h1s=h1.resize((h1.width//2,h1.height//2),Image.LANCZOS)
A={'head1':uri(h1s,'WEBP',88),'head2':uri(h2,'WEBP',90),'bust1':uri(b1,'WEBP',82),'bust2':uri(b2,'WEBP',82),
 'camo':uri(camo,'JPEG',85),'tee':uri(tee,'JPEG',85),'jeans':uri(jeans,'JPEG',85),'stage1':uri(st,'JPEG',78)}
print({k:len(v)//1024 for k,v in A.items()}, h1s.size)
# skin sample
print('skin1',p1.crop((700,1000,760,1040)).resize((1,1)).getpixel((0,0)),'skin2',p2.crop((870,950,900,980)).resize((1,1)).getpixel((0,0)))
json.dump(A,open('assets.json','w'))
for n,im in [('h1',h1s),('h2',h2),('b1',b1),('b2',b2),('camo',camo),('tee',tee),('jeans',jeans)]:
    bg=Image.new('RGBA',im.size,(255,0,255,255)); bg.alpha_composite(im.convert('RGBA')); bg.convert('RGB').save('a/'+n+'.png')
