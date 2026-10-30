import json
s=open('src.html').read(); A=json.load(open('assets.json'))
open('fellowship-fighter.html','w').write(s.replace('/*ASSETS*/',json.dumps(A)))
