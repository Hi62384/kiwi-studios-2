// Single structural evaluator for Image Workspace, generated maps and scene materials.
// Coordinates are measured in 1/16th of a texture repeat, independent of brush size.
float h(vec2 p){return fract(sin(dot(p+vec2(seed*.031,seed*.073),vec2(127.1,311.7)))*43758.5453);}
float n(vec2 p){return texture(noise_map,p/128.).r;}
float line(float v,float width){return 1.-smoothstep(width,width+.04,abs(v));}
float nm_fbm(vec2 p){return (n(p)+n(p*2.03)*.5+n(p*4.07)*.25)/1.75;}
vec3 cell(vec2 p){
 vec2 g=floor(p),f=fract(p); float d=10.,d2=10.,id=0.;
 for(int y=-1;y<=1;y++){for(int x=-1;x<=1;x++){
  vec2 q=g+vec2(float(x),float(y));vec2 r=vec2(h(q),h(q+13.))-f+vec2(float(x),float(y));
  float v=dot(r,r);if(v<d){d2=d;d=v;id=h(q+27.);}else if(v<d2){d2=v;}
 }}return vec3(sqrt(d),sqrt(d2)-sqrt(d),id);
}
float nm_threads(vec2 p,float twill){
 vec2 grid=floor(p),f=fract(p)-.5;
 float parity=mod(grid.x+grid.y,2.);
 if(twill>.5){parity=step(1.5,mod(grid.x-grid.y,4.));}
 float width=mix(.16,.49,thickness);
 float warp=sqrt(max(0.,1.-pow(f.x/width,2.)));
 float weft=sqrt(max(0.,1.-pow(f.y/width,2.)));
 float top=mix(warp,weft,parity),under=mix(weft,warp,parity);
 // The upper thread crosses the lower thread. Longitudinal fibrils follow each yarn.
 float fibril=mix(sin(p.x*65.),sin(p.y*65.),parity)*.03*detail;
 return .1+.65*max(top,under*.52)+fibril+.07*h(grid);
}
float nm_wood(vec2 p){
 float bend=(nm_fbm(vec2(p.x*.6,p.y*.13))-.5)*distortion*5.;
 vec2 knotcell=floor(p/vec2(5.,11.)); vec2 k=p-(knotcell+.5)*vec2(5.,11.);
 vec2 boundary=1.-smoothstep(vec2(.28),vec2(.5),abs(k/vec2(5.,11.)));
 k-=vec2(h(knotcell)-.5,h(knotcell+11.)-.5)*vec2(2.,5.);
 float weight=knots*exp(-dot(k*vec2(.8,.24),k*vec2(.8,.24)))*boundary.x*boundary.y;
 float ringcoord=p.x+bend+weight*k.x*2./(.3+dot(k*vec2(.65,.2),k*vec2(.65,.2)));
 float annual=.5+.5*sin(ringcoord*7.);
 float knot_rings=.5+.5*sin(length(k*vec2(1.,.3))*11.);
 annual=mix(annual,knot_rings,weight*.8);
 float latewood=pow(annual,8.);
 float fibers=n(vec2(p.x*40.,p.y*.55));
 float v=.74-latewood*.44+(annual-.5)*.16+(fibers-.5)*detail*.24;
 v-=weight*.36;
 if(variant==5){v-=line(fract(p.y*.2)-.5,.025)*.25;v+=line(fract(p.x*.4)-.5,.015)*.16;}
 if(variant==6){v=.5+.32*sin((p.x+bend)*12.)*sin(p.x*.7)+(fibers-.5)*detail*.2;}
 if(variant==7){v=.22+pow(annual,.4)*.46-line(fract(p.x*1.5+bend)-.5,.045)*.25+n(p*8.)*detail*.2;}
 if(variant==8||variant==12||variant==13){v-=line(fract(p.x*3.+bend)-.5,.035)*step(.4,n(p*.6))*.35;}
 if(variant==9){v=mix(.8,v,step(.65,n(p*3.)));}
 if(variant==10){float seam=1.-smoothstep(.03,.12,abs(fract(p.x*.25)-.5));v-=seam*.5;v+=(h(vec2(floor(p.x*.25),0.))-.5)*.18;}
 return v;
}
float nm_metal(vec2 p){
 float brush=n(vec2(p.x*48.,p.y*.25));
 float scratches=line(fract(p.x*(3.+detail*16.))-.5,.035)*step(.55,n(vec2(p.x*4.,p.y*.22)));
 float v=.52+(brush-.5)*(.12+roughness*.42)-scratches*detail*.3;
 if(variant==2||variant==8||variant==9){v=.6+(brush-.5)*.07+(n(p*3.)-.5)*.04;}
 if(variant==3||variant==4){vec3 c=cell(p*2.);v=.45+c.z*.25-pow(1.-smoothstep(.02,.22,c.x),2.)*distortion*.6;}
 if(variant==10){vec3 c=cell(p*.8);v=.38+c.z*.4+line(c.y,.04)*.08;}
 if(variant==11){float rust=smoothstep(.36,.68,nm_fbm(p*3.)+distortion*.2);v=mix(v,.1+n(p*40.)*.4,rust);}
 if(variant==12){v-=scratches*.4;}
 if(variant==13){vec3 c=cell(p*1.25);v=.8-pow(max(0.,1.-c.x*1.5),1.5)*(.25+distortion*.5);}
 if(variant==14){vec2 q=p*.55;float parity=mod(floor(q.x)+floor(q.y),2.);vec2 f=fract(q)-.5;float diagonal=mix(f.x+f.y,f.x-f.y,parity);float tread=line(diagonal,.06)* (1.-smoothstep(.22,.42,length(f)));v=.25+tread*.55;}
 float damage=pow(n(p*4.),4.)*distortion;
 return v-damage*.28+(n(p*12.)-.5)*detail*.12;
}
float nm_fabric(vec2 p){
 vec2 q=p*(1.+detail*.25);q+=vec2(n(vec2(p.y*.3,0.)),n(vec2(0.,p.x*.3)))*distortion*.25;
 float v=nm_threads(q,variant==1?1.:0.);
 if(variant==2||variant==8){v*=.8+.2*n(q*10.);}
 if(variant==3||variant==13){
  // Curled wool fibers, rather than an isotropic noise field.
  vec2 fibers=q*2.+vec2(n(p)*3.,n(p+17.)*3.);
  float curl=line(sin(fibers.x*4.+sin(fibers.y*3.)*2.),.07+thickness*.22);
  float crosscurl=line(sin(fibers.y*7.+sin(fibers.x*4.)*1.4),.07+thickness*.2);
  v=.19+max(curl,crosscurl*.7)*.5+n(p*22.)*detail*.16;
 }
 if(variant==4){v=.62+.11*pow(.5+.5*sin(q.x*30.),.3+thickness*3.)+.06*sin(q.y*4.+n(p)*4.)+detail*(n(p*40.)-.5)*.06;}
 if(variant==5||variant==7){v=.4+detail*.2*n(p*(20.+thickness*40.))+.2*pow(n(q*3.),2.);}
 if(variant==6){vec3 c=cell(q*2.);v=.42+.22*c.z-(.15+distortion*.35)*line(c.y,.008+thickness*.055)+(n(p*30.)-.5)*detail*.1;}
 if(variant==9){
  vec2 f=fract(q*.5)-.5;
  float path=abs(f.x)-(.11+.25*(f.y+.5)+.035*cos(f.y*6.283185));
  float radius=.035+thickness*.065;
  float yarn=sqrt(max(0.,1.-pow(path/radius,2.)));
  v=.12+yarn*.65+sin((f.y-abs(f.x))*75.)*detail*.04*yarn;
 }
 if(variant==12){v=.2+.58*pow(.5+.5*cos(q.x*6.283185),.4+thickness*2.)+n(p*30.)*detail*.12;}
 if(variant==14){vec2 f=abs(fract(q)-.5);v=.08+.8*step(.5-thickness*.35,max(f.x,f.y))+detail*(n(p*18.)-.5)*.12;}
 return v;
}
float nm_stone(vec2 p){
 p+=(vec2(n(p*.8),n(p*.8+19.))-.5)*distortion;
 float coarse=nm_fbm(p*.9),fine=n(p*25.);
 float v=.4+coarse*.24+(fine-.5)*detail*.18;
 if(variant==0){
  vec3 mineral=cell(p*3.5);float quartz=smoothstep(.48,.57,mineral.z),mica=1.-smoothstep(.12,.2,mineral.z);
  v=.38+quartz*.43-mica*.3+(fine-.5)*detail*.3;
 }
 if(variant==1){
  float warp=(nm_fbm(p*1.7)-.5)*distortion*10.+(n(p*6.)-.5)*distortion*4.;
  float veins=pow(1.-abs(sin(p.x*.72+p.y*.28+warp)),6.+thickness*20.);
  float hair=pow(1.-abs(sin(p.x*1.43+p.y*.56+warp*2.)),18.);
  v=.88-veins*.68-hair*.12+(fine-.5)*detail*.12;
 }
 if(variant==2){vec3 fossil=cell(p*.55);v=.62+(coarse-.5)*.25-line(fossil.x-.22,.012)*detail*.15;}
 if(variant==3){v=.47+.17*sin(p.y*5.+coarse*distortion*5.)+(fine-.5)*detail*.28;}
 if(variant==4){v=.4+n(vec2(p.x*.8,p.y*15.))*.25+line(fract(p.y*.7+coarse*distortion)-.5,.02)*.12;}
 if(variant==5||variant==6){vec3 pore=cell(p*4.);float pit=1.-smoothstep(.015,.11*max(.15,thickness*3.),pore.x);v=.55+(coarse-.5)*.18+(fine-.5)*detail*.2-pit*(variant==6?.45:.28);v-=step(.87,pore.z)*.13;}
 if(variant==7||variant==8||variant==14){vec2 q=p*vec2(.32,.62);if(variant!=14){q.x+=mod(floor(q.y),2.)*.5;}vec2 f=fract(q);float edge=min(min(f.x,f.y),min(1.-f.x,1.-f.y));float face=smoothstep(thickness*.12,thickness*.12+.035,edge);v=mix(.18,.53+h(floor(q))*.24,face)+(fine-.5)*.1*face;}
 if(variant==9||variant==13){vec3 c=cell(p*.9);float face=smoothstep(thickness*.08,thickness*.08+.055,c.y);v=mix(.14,.42+c.z*.38,face)+min(c.y,.2)*.5;}
 if(variant==10){v=.12+fine*.15+step(.78,cell(p*5.).z)*detail*.4;}
 if(variant==11){vec3 c=cell(p*.65+vec2(coarse)*distortion);v-=line(c.y,thickness*.1)*.5;}
 if(variant==12){v=.6+(coarse-.5)*.4+pow(abs(sin(p.x*.4+coarse*4.)),12.)*.15;}
 return v+(n(p*18.)-.5)*detail*.12;
}
float nm_ground(vec2 p){
 p+=(vec2(n(p*.7),n(p*.7+17.))-.5)*distortion*2.;
 float coarse=nm_fbm(p),fine=n(p*35.);float v=.3+coarse*.35+(fine-.5)*detail*.25;
 if(variant==0){
  v=.12+coarse*.18;
  // Three staggered blade beds prevent an obvious rectangular grass grid.
  for(int k=0;k<3;k++){vec2 q=p*vec2(1.4,.55)+float(k)*vec2(.37,.63);q.x+=q.y*.17*float(k);vec2 id=floor(q),f=fract(q)-.5;f.x+=(h(id)-.5)*.35;float bend=(h(id+float(k))-.5)*distortion*2.;float width=(.5-f.y)*(.015+thickness*.14);float blade=line(f.x+f.y*f.y*bend,width)*smoothstep(.5,.25,abs(f.y));v=max(v,blade*(.35+h(id)*.5));}
 }
 if(variant==1){vec3 c=cell(p*2.);float tuft=pow(max(0.,1.-c.x),2.);v=.2+tuft*.58+(fine-.5)*detail*.2;}
 if(variant==2||variant==13){vec3 c=cell(p*3.);v=.25+coarse*.32+c.z*.18-line(c.y,.015)*.15;}
 if(variant==3){v=.48+(coarse-.5)*.25+sin(p.y*2.+coarse*distortion*5.)*.07;}
 if(variant==4||variant==12){vec3 c=cell(p*.65+vec2(coarse)*distortion);v=.55+coarse*.2-line(c.y,thickness*.12)*.6;}
 if(variant==5){float dunes=.5+.5*sin(p.y*1.9+nm_fbm(p*.4)*distortion*7.);v=.46+dunes*.28+(fine-.5)*detail*.25+step(.9,h(floor(p*25.)))*.09;}
 if(variant==6||variant==7||variant==10){vec3 c=cell(p*(variant==7?1.1:1.8));float edge=smoothstep(.005,.08+thickness*.15,c.y);v=.12+edge*(.2+c.z*.3+pow(max(0.,1.-c.x),.5)*.28);}
 if(variant==8){v=.78+coarse*.13+pow(fine,5.)*.14;}
 if(variant==9){v=.82-line(cell(p*.5).y,.012+thickness*.035)*.5+coarse*.1;}
 if(variant==11||variant==14||variant==15){vec2 q=p*.7;q.x+=mod(floor(q.y),2.)*.5;vec2 id=floor(q);vec2 f=fract(q)-.5;float turn=h(id)*6.283185;f=mat2(vec2(cos(turn),sin(turn)),vec2(-sin(turn),cos(turn)))*f;float leaf=1.-smoothstep(.22+thickness*.3,.3+thickness*.3,length(f*vec2(1.,1.9)));v=.12+leaf*(.35+h(id+4.)*.42);v-=line(f.y,.013)*leaf*.17;}
 return v+(n(p*22.)-.5)*detail*.2;
}
float nm_organic(vec2 p){
 p+=(vec2(n(p*.6),n(p*.6+17.))-.5)*distortion*2.;
 vec3 c=cell(p*2.);float v=.65-line(c.x-.035,.02+thickness*.035)*.3;
 if(variant==1||variant==2){vec2 q=p*.65;q.x+=mod(floor(q.y),2.)*.5;vec2 f=fract(q)-.5;float plate=1.-smoothstep(.1+thickness*.3,.3+thickness*.3,length(f*vec2(1.,1.5)));v=.15+plate*.66+plate*sin(f.y*5.)*.1;}
 if(variant==3||variant==4){v=.2+line(fract(p.x*4.+sin(p.y*.8)*distortion)-.5,.08)*.58;if(variant==4){v-=line(fract(p.x*.5)-.5,.025)*.2;}}
 if(variant==5||variant==6){float stem=line(p.x,.05);float veins=line(fract(p.y*.55-abs(p.x)*.45)-.5,.025);v=.64-stem*.3-veins*(variant==6?.32:.15)+n(p*15.)*.08;}
 if(variant==7){v=.2+.5*pow(.5+.5*sin(p.x*4.+n(p)*distortion*7.),.6)-line(c.y,.035)*.2;}
 if(variant==8){v=.7+n(p)*.15-line(c.x-.04,.025)*.23;}
 if(variant==9){float r=length(p);v=.5+.27*sin(r*3.+atan(p.y,p.x)*2.)+line(fract(atan(p.y,p.x)*16.)-.5,.07)*.1;}
 if(variant==10){v=.75-line(c.y,.03+thickness*.2)*.35;}
 return v+(n(p*22.)-.5)*detail*.2;
}
float nm_weather(vec2 p){
 p+=(vec2(n(p*.6),n(p*.6+17.))-.5)*distortion*3.;
 float coarse=nm_fbm(p*2.),fine=n(p*30.);vec3 c=cell(p*.9);float v=smoothstep(.4,.72,coarse+distortion*.15);
 if(variant==0||variant==10){v*=.4+fine*.6;}
 if(variant==1){v=pow(fine,3.)*.7;}
 if(variant==2||variant==9){v*=fine;}
 if(variant==3){v=line(fract(p.x*(2.+detail*10.))-.5,thickness*.12)*step(.48,n(vec2(p.x,p.y*.2)));}
 if(variant==4){v=line(c.y,thickness*.14);}
 if(variant==5||variant==6){v=step(.5,c.z)*smoothstep(.01,.09,c.y);}
 if(variant==7){v=line(c.x-.3,thickness*.18)*.75+coarse*.1;}
 if(variant==8){v=smoothstep(.5,.63,n(p*.5));}
 if(variant==11){v=line(c.y,thickness*.3)*coarse;}
 if(variant==12){v=pow(smoothstep(.2,.8,n(p*.8)),3.);}
 if(variant==13){v=pow(1.-cell(p*3.).x,3.);}
 if(variant==14){v=1.-smoothstep(.01,.08+thickness*.15,c.x);}
 return v*(.5+detail)+detail*pow(fine,3.)*.12;
}
float nm_illustration(vec2 p){
 p+=(vec2(n(p*.6),n(p*.6+17.))-.5)*distortion;
 vec2 q=p*.8;float ink=1.-smoothstep(thickness,thickness+.035,length(fract(q)-.5));
 if(variant==0){float radius=thickness*(.5+nm_fbm(p)*2.);ink=1.-smoothstep(radius,radius+.025,length(fract(q)-.5));}
 if(variant==2||variant==10){vec3 c=cell(p*3.);ink=1.-smoothstep(.015,.05+thickness*.15,c.x);}
 if(variant==3||variant==4){ink=line(fract(q.x+q.y)-.5,thickness*.2);if(variant==3){ink=max(ink,line(fract(q.x-q.y)-.5,thickness*.2));}}
 if(variant==5){ink=line(fract(q.x+q.y+n(p*.7)*distortion)-.5,thickness*.45)*(.35+n(p*25.)*.65);}
 if(variant==6){ink=smoothstep(.4,.8,n(p*20.))*detail;}
 if(variant==7||variant==8){ink=line(sin(q.y*6.+sin(q.x*3.)*(1.+distortion*5.)),thickness*.5);}
 if(variant==9){ink=.15+n(p*30.)*.2+line(fract(p.x*8.)-.5,.03)*detail*.15;}
 if(variant==11){ink=pow(nm_fbm(p*4.),2.)*.8+(1.-cell(p*3.).x)*detail*.2;}
 if(variant==12){ink=smoothstep(.35,.65,n(p*4.))*(.5+n(p*35.)*.5);}
 if(variant==13){ink=.3+.28*pow(.5+.5*sin(q.x*4.+n(p*.5)*distortion),5.);}
 return 1.-ink-(n(p*22.)-.5)*detail*.14;
}
float nm_geometry(vec2 p){
 vec2 q=p*.4+vec2(n(p)-.5)*distortion,f=fract(q)-.5;float v=step(0.,sin(q.y*6.283185));
 if(variant==1){v=mod(floor(q.x)+floor(q.y),2.);}
 if(variant==2||variant==9){v=variant==2?1.-smoothstep(thickness,thickness+.02,length(f)):line(length(f)-.3,thickness*.2);}
 if(variant==3){v=max(line(f.x,thickness*.2),line(f.y,thickness*.2));}
 if(variant==11){float edge=.5-max(abs(f.x),abs(f.y));v=smoothstep(thickness*.08,thickness*.08+.08,edge);}
 if(variant==4||variant==12){vec2 z=q*vec2(1.,1.1547);z.x+=mod(floor(z.y),2.)*.5;vec2 c=abs(fract(z)-.5);float edge=max(c.x*.866+c.y*.5,c.y);v=variant==4?1.-smoothstep(.35-thickness*.1,.43-thickness*.1,edge):line(edge-.45,thickness*.2);}
 if(variant==5){v=step(fract(q.x)+fract(q.y),1.);}
 if(variant==6){v=step(abs(f.x)+abs(f.y),.35);}
 if(variant==7){v=.5+.5*sin(q.y*6.283185+sin(q.x*6.283185));}
 if(variant==8){v=step(fract(q.y)+abs(f.x),.5);}
 if(variant==10){q.x+=mod(floor(q.y),2.)*.5;f=fract(q);v=step(thickness,min(min(f.x,f.y),min(1.-f.x,1.-f.y)));}
 if(variant==13){v=max(step(abs(f.x),thickness)*step(abs(f.y),.35),step(abs(f.y),thickness)*step(abs(f.x),.35));}
 return v;
}
float nm_noise(vec2 p){
  float v=n(p*4.);
  if(variant==0){v=h(floor(p*8.));}
  if(variant==1){vec2 g=floor(p),f=fract(p);v=mix(mix(h(g),h(g+vec2(1.,0.)),f.x),mix(h(g+vec2(0.,1.)),h(g+vec2(1.)),f.x),f.y);}
  if(variant==5||variant==6||variant==12){vec3 c=cell(p*.7);v=variant==6?c.z:(variant==12?c.y:c.x);}
  if(variant==7||variant==13){v=nm_fbm(p*4.);}
  if(variant==8){v=1.-abs(v*2.-1.);}
  if(variant==9){v=abs(v*2.-1.);}
  if(variant==10){v=(abs(n(p)*2.-1.)+.5*abs(n(p*2.03)*2.-1.)+.25*abs(n(p*4.07)*2.-1.))/1.75;}
  if(variant==11){v=n(p*4.+vec2(n(p),n(p+27.))*distortion*30.);}
 return v;
}
float raw_pattern(vec2 p){
 p*=max(.01,density);float v=0.;
 if(family==0){v=nm_metal(p);}else if(family==1){v=nm_wood(p);}else if(family==2){v=nm_fabric(p);}
 else if(family==3){v=nm_stone(p);}else if(family==4){v=nm_ground(p);}else if(family==5){v=nm_organic(p);}
 else if(family==6){v=nm_weather(p);}else if(family==7){v=nm_illustration(p);}else if(family==8){v=nm_geometry(p);}else{v=nm_noise(p);}
 return clamp((v-.5)*contrast+.5+brightness,0.,1.);
}
float pattern(vec2 p){
 if(!seamless){return raw_pattern(p);}
 // Only the edge band evaluates neighbours. Values meet exactly at repeat edges.
 vec2 q=mod(p+8.,16.)-8.;vec2 a=abs(q);vec2 w=smoothstep(vec2(6.4),vec2(8.),a)*.5;
 float v=raw_pattern(q);
 if(w.x>0.){v=mix(v,raw_pattern(q-vec2(sign(q.x)*16.,0.)),w.x);}
 if(w.y>0.){float b=raw_pattern(q-vec2(0.,sign(q.y)*16.));if(w.x>0.){b=mix(b,raw_pattern(q-sign(q)*16.),w.x);}v=mix(v,b,w.y);}
 return v;
}
vec4 natural_color(vec2 p,float height){return mix(primary,secondary,height);}
vec2 natural_surface(vec2 p,float height){
 float r=clamp(roughness+(height-.5)*.22, .035,1.);
 float m=family==0?.92:0.;
 if(family==0&&variant==11){m*=smoothstep(.2,.65,height);r=mix(.93,r,m);}
 if(family==2){r=max(.7,r);if(variant==4){r=.26+height*.12;}}
 if(family==4&&variant==3){r=.18+height*.16;}
 if(family==4&&variant==9){r=.08+height*.1;}
 return vec2(r,m);
}
