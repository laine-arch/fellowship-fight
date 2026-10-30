from PIL import Image, ImageDraw, ImageFilter, ImageChops
import numpy as np, json, base64, io, cv2
from sty import stylize2 as stylize, boost, kmeans_q
I='../../images/'
def pad(im,p): o=Image.new('RGBA',(im.width+2*p,im.height+2*p),(0,0,0,0)); o.paste(im,(p,p)); return o
def ell(size, box, fe): m=Image.new('L',size,0); ImageDraw.Draw(m).ellipse(box,fill=255); return m.filter(ImageFilter.GaussianBlur(fe))
LOGO=[(350,0),(540,0),(540,104),(470,108),(400,120),(356,128),(344,98)]
cu1=Image.open('cut1.png'); mm=Image.new('L',cu1.size,255); ImageDraw.Draw(mm).polygon([(x+240,y+600) for x,y in LOGO],fill=0)
cu1.putalpha(ImageChops.multiply(cu1.getchannel('A'),mm))
cu2=Image.open('cut2.png')
def hard(im):  # crisp alpha edge for clean outlines
    a=np.array(im.getchannel('A')); a=np.where(a>110,255,0).astype(np.uint8); im=im.copy(); im.putalpha(Image.fromarray(a)); return im
# heads: crop -> elliptical head mask -> stylize
h1=cu1.crop((240,600,780,1130)); h1.putalpha(ImageChops.multiply(h1.getchannel('A'),ell(h1.size,(25,25,525,515),1)))
h1=hard(h1); P=10; h1=pad(h1,P)
s1=stylize(h1,outline=7,line_w=2,min_edge=18,levels=5,sr=0.3,passes=1,edge_lo=60,edge_hi=140)
anc1=(210+P,490+P)
h2=cu2.crop((670,540,870,800)); h2.putalpha(ImageChops.multiply(h2.getchannel('A'),ell(h2.size,(5,8,195,242),1)))
h2=h2.resize((h2.width*3,h2.height*3),Image.LANCZOS); h2=hard(h2); h2=pad(h2,P)
s2=stylize(h2,outline=7,line_w=2,min_edge=18,levels=5,sr=0.3,passes=1,edge_lo=60,edge_hi=140)
anc2=(100*3+P,236*3+P)
def fin(im,anc,H):
    bb=im.getbbox(); im=im.crop(bb); anc=(anc[0]-bb[0],anc[1]-bb[1]); f=H/im.height
    return im.resize((round(im.width*f),H),Image.LANCZOS),(round(anc[0]*f),round(anc[1]*f))
H1,A1=fin(s1,anc1,260); H2,A2=fin(s2,anc2,250)
print('anchors',A1,H1.size,A2,H2.size)
# busts
b1=cu1.crop((40,600,1240,1700)); b1=hard(b1.resize((b1.width*6//10,b1.height*6//10),Image.LANCZOS)); b1=stylize(pad(b1,8),outline=5,line_w=2,min_edge=18,levels=5,sr=0.3,passes=1,edge_lo=60,edge_hi=140)
b2=cu2.crop((560,540,1060,1300)); b2=hard(b2); b2=stylize(pad(b2,8),outline=5,line_w=2,min_edge=18,levels=5,sr=0.3,passes=1,edge_lo=60,edge_hi=140)
b1=b1.crop(b1.getbbox()); b1=b1.resize((b1.width*62//100,b1.height*62//100),Image.LANCZOS)
b2=b2.crop(b2.getbbox()); b2=b2.resize((b2.width*62//100,b2.height*62//100),Image.LANCZOS)
# textures: posterise
def tex(im,K):
    a=np.array(im.convert('RGB')); f=a
    f=cv2.bilateralFilter(f,5,25,4)
    f=boost(f,1.5,contrast=1.35); q=kmeans_q(f,np.ones(f.shape[:2],bool),K); return Image.fromarray(q)
p1=Image.open(I+'1.jpg').convert('RGB'); p2=Image.open(I+'2.jpg').convert('RGB')
camo=tex(p1.crop((120,1300,330,1560)).resize((105,130),Image.LANCZOS),9)
tee=tex(p2.crop((800,1020,900,1150)).resize((60,78),Image.LANCZOS),3)
jeans=tex(p2.crop((780,1280,850,1480)).resize((42,120),Image.LANCZOS),5)
# stage: painted look
st=Image.open(I+'3.jpg').convert('RGB').crop((0,150,2000,1275)).resize((1600,900),Image.LANCZOS)
from sty import stylize2
sti=st.convert('RGBA')
q=np.array(stylize2(sti,levels=7,ss=60,sr=0.35,passes=2,chromaK=12,outline=1,min_edge=60,line_w=2,sat=1.55,edge_lo=50,edge_hi=120,lmin=0.08,feat_c=40).convert('RGB'))
stage=Image.fromarray(q).resize((1280,720),Image.LANCZOS)
def uri(im,fmt,q):
    b=io.BytesIO(); im.save(b,fmt,quality=q); return 'data:image/%s;base64,'%fmt.lower()+base64.b64encode(b.getvalue()).decode()
A={'head1':uri(H1,'WEBP',90),'head2':uri(H2,'WEBP',90),'bust1':uri(b1,'WEBP',86),'bust2':uri(b2,'WEBP',86),
 'camo':uri(camo,'PNG',0),'tee':uri(tee,'PNG',0),'jeans':uri(jeans,'PNG',0),'stage1':uri(stage,'JPEG',84)}
print({k:len(v)//1024 for k,v in A.items()})
json.dump(A,open('assets.json','w')); json.dump({'a1':A1,'a2':A2,'h1':H1.size,'h2':H2.size},open('anchors.json','w'))
for n,im in [('H1',H1),('H2',H2),('B1',b1),('B2',b2)]:
    bg=Image.new('RGBA',im.size,(120,60,170,255)); bg.alpha_composite(im); bg.convert('RGB').save('a/'+n+'.png')
stage.save('a/stage.jpg')
