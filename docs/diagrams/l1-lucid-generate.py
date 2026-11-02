import json
WSO2="https://raw.githubusercontent.com/MinuraKariyawasam/alior-poc/main/docs/img/wso2-logo.png"
ARGO="https://raw.githubusercontent.com/cncf/artwork/master/projects/argo/icon/color/argo-icon-color.png"
HELM="https://raw.githubusercontent.com/cncf/artwork/master/projects/helm/icon/color/helm-icon-color.png"
GH="https://github.githubassets.com/images/modules/logos_page/GitHub-Mark.png"
S=[];L=[]
W,H=300,100
def t(title,sub,pad=False):
    return f'<p style="font-size:13px;text-align:center">{"<br>" if pad else ""}<b>{title}</b><br>{sub}</p>'
def named(i,cls,x,y,w,h,title,sub=""):
    S.append({"id":i,"type":"namedShape","className":cls,"boundingBox":{"x":x,"y":y,"w":w,"h":h},"text":t(title,sub)})
def img(i,url,x,y,w,h):
    S.append({"id":i,"type":"image","boundingBox":{"x":x,"y":y,"w":w,"h":h},"image":{"type":"image","url":url},"stroke":{"color":"#00000000","width":0,"style":"solid"}})
def box(i,x,y,title,sub,fill,stroke):
    S.append({"id":i,"type":"rectangle","boundingBox":{"x":x,"y":y,"w":W,"h":H},"text":t(title,sub,True),"style":{"fill":{"type":"color","color":fill},"stroke":{"color":stroke,"width":1.5,"style":"solid"},"textColor":"#222222"}})
def wso2box(i,x,y,title,sub,helm=False):
    box(i,x,y,title,sub,"#FFF3E8","#FF7300"); img(i+"_logo",WSO2,x+12,y+10,84,21)
    if helm: img(i+"_helm",HELM,x+W-36,y+8,24,24)
def argobox(i,x,y,title,sub):
    box(i,x,y,title,sub,"#F1EEFA","#6B4FBB"); img(i+"_logo",ARGO,x+12,y+8,24,30); img(i+"_helm",HELM,x+W-36,y+8,24,24)
def cont(i,x,y,w,h,title,fill):
    S.append({"id":i,"type":"roundedRectangleContainer","boundingBox":{"x":x,"y":y,"w":w,"h":h},"containerTitle":{"text":title},"assistedLayout":False,"style":{"fill":{"type":"color","color":fill},"stroke":{"color":"#8A8F98","width":1,"style":"dashed"}}})
def line(i,a,pa,b,pb,label,color="#4A4A4A",dashed=False,pos=0.5,side="top"):
    L.append({"id":i,"lineType":"elbow",
      "endpoint1":{"type":"shapeEndpoint","style":"none","shapeId":a,"position":{"x":pa[0],"y":pa[1]}},
      "endpoint2":{"type":"shapeEndpoint","style":"arrow","shapeId":b,"position":{"x":pb[0],"y":pb[1]}},
      "stroke":{"color":color,"width":1.5,"style":"dashed" if dashed else "solid"},
      "text":[{"text":f'<span style="font-size:11px">{label}</span>',"position":pos,"side":side}]})
GREEN,ORANGE,PURPLE,GREY="#1B7F3B","#FF7300","#6B4FBB","#4A4A4A"
C2,C3,C4=700,1100,1500
# containers
S.append({"id":"rg","type":"namedContainer","className":"ResourceGroupContainerAzure2024","boundingBox":{"x":320,"y":140,"w":1600,"h":1120},"text":"Azure: rg-Alior-POC-minura (presales-001)"})
cont("regA",620,250,1280,400,"Region A: pod-a-aks, polandcentral (cloud)","#F2F6FC")
cont("regB",620,720,1280,400,"Region B: pod-b-aks, westeurope (on-prem stand-in)","#F4F9F3")
S.append({"id":"legend","type":"text","boundingBox":{"x":40,"y":1215,"w":260,"h":110},"text":'<p style="font-size:12px"><b>Alior PoD, L1</b><br><span style="color:#1B7F3B">green</span>: API traffic<br><span style="color:#FF7300">orange</span>: WSO2 control<br><span style="color:#6B4FBB">purple</span>: GitOps (Argo CD + Helm)<br>grey: people, az CLI, database</p>'})
# people + git
named("consumer","UsersAzure2024",40,290,110,120,"API consumer","app or tester")
named("developer","UsersAzure2024",1685,10,110,120,"API developer","Publisher UI / REST API, via Front Door")
named("infra","UsersAzure2024",40,600,110,120,"Infra engineer","Git + az CLI")
img("gh",GH,200,615,90,90); S.append({"id":"ghT","type":"text","boundingBox":{"x":170,"y":710,"w":150,"h":40},"text":t("GitHub","alior-poc, main")})
# azure shared
named("fd","FrontDoorAndCDNProfilesAzure2024",380,300,120,106,"Front Door Premium","TLS + WAF, only public door")
named("kv","KeyVaultsAzure2024",380,1130,90,90,"Key Vault","AES key, CP token")
# region A
named("aksA","KubernetesServicesAzure2024",1810,258,70,70,"AKS","")
wso2box("gwA",C3,280,"API Platform Gateway A","controller + Envoy router")
wso2box("cp",C4,280,"APIM 4.7 control plane","Publisher, Dev Portal, Admin")
argobox("argoA",C2,460,"Argo CD A","pulls main, runs Helm")
wso2box("opA",C3,460,"WSO2 gateway operator","applies gateway chart 1.2.5",helm=True)
named("pg","VirtualMachineAzure2024",C4+90,455,120,111,"pod-a-db","PostgreSQL 16 (APIM only)")
# region B
named("aksB","KubernetesServicesAzure2024",1810,728,70,70,"AKS","")
wso2box("gwB",C3,780,"API Platform Gateway B","controller + Envoy router")
argobox("argoB",C2,960,"Argo CD B","pulls main, runs Helm")
wso2box("opB",C3,960,"WSO2 gateway operator","applies gateway chart 1.2.5",helm=True)
named("vm","VirtualMachineAzure2024",C4+90,955,120,111,"pod-b-vm","mock backends v1 / v2 / legacy")
# lines
line("l1","consumer",(1,0.5),"fd",(0,0.5),"API calls, HTTPS")
line("l2","developer",(0.5,1),"cp",(0.8,0),"deploys APIs",pos=0.6)
line("l3","fd",(1,0.5),"gwA",(0,0.5),"HTTP 8080 (A)",GREEN)
line("l4","fd",(0.5,1),"gwB",(0,0.5),"HTTP 8080 (B)",GREEN,pos=0.75)
line("l5","fd",(0.5,0),"cp",(0.5,0),"portals + Argo UIs via ingress",pos=0.3)
line("l6","cp",(0,0.5),"gwA",(1,0.5),"WebSocket",ORANGE)
line("l7","cp",(0,0.8),"gwB",(1,0.5),"WebSocket (B)",ORANGE,pos=0.6)
line("l8","cp",(0.5,1),"pg",(0.5,0),"JDBC")
line("l9","gwA",(1,0.8),"vm",(0,0.5),"cross-region, ~25 ms",GREEN,dashed=True,pos=0.45,side="bottom")
line("l10","gwB",(0.8,1),"vm",(0.5,0),"backend calls",GREEN,pos=0.75)
line("l11","infra",(0.5,0),"rg",(0,0.375),"az scripts: make infra / idle / lockdown",pos=0.7)
line("l12","infra",(1,0.5),"gh",(0,0.5),"git push")
line("l13","gh",(1,0.5),"argoA",(0,0.5),"pull main (A)",PURPLE)
line("l14","gh",(1,0.5),"argoB",(0,0.5),"pull main (B)",PURPLE)
line("l15","argoA",(1,0.3),"opA",(0,0.3),"Helm chart",PURPLE)
line("l16","argoA",(0.5,0),"cp",(0.15,1),"Helm: helm-apim chart 4.7.0-5",PURPLE,pos=0.25)
line("l17","opA",(0.5,0),"gwA",(0.5,1),"APIGateway CR",ORANGE,pos=0.15,side="bottom")
line("l18","argoB",(1,0.3),"opB",(0,0.3),"Helm chart",PURPLE)
line("l19","opB",(0.5,0),"gwB",(0.5,1),"APIGateway CR",ORANGE,pos=0.15,side="bottom")
doc={"version":1,"pages":[{"id":"p1","title":"L1 user flow","shapes":S,"lines":L}]}
open("l1-lucid-import.json","w").write(json.dumps(doc)); print(len(json.dumps(doc)))
