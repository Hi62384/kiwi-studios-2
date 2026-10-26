#[compute]
#version 450
layout(local_size_x=64) in;
layout(set=0,binding=0,std430) buffer P { vec4 p[]; };
layout(set=0,binding=1,std430) buffer O { vec4 old[]; };
layout(set=0,binding=2,std430) buffer V { vec4 v[]; };
layout(set=0,binding=3,std430) buffer D { vec4 delta[]; };
layout(set=0,binding=4,std430) buffer L { vec4 ld[]; };
layout(set=0,binding=5,std430) buffer H { int heads[]; };
layout(set=0,binding=6,std430) buffer K { int links[]; };
layout(set=0,binding=7,std430) readonly buffer C { float c[]; };
layout(push_constant,std430) uniform Push { uint stage; uint count; uint spare1; uint spare2; } pc;
uint cell_hash(ivec3 a) { return (uint(a.x)*73856093u ^ uint(a.y)*19349663u ^ uint(a.z)*83492791u)&4095u; }
float kernel(float d2) { float h=c[4]; float q=max(0.0,1.0-d2/(h*h)); return 315.0/(64.0*3.141592654*h*h*h)*q*q*q; }
vec3 gradient(vec3 d) { float r=length(d); float h=c[4]; if(r<0.000001 || r>=h) return vec3(0); return d*(-45.0/(3.141592654*pow(h,4.0))*pow(1.0-r/h,2.0)/r); }
vec3 limited(vec3 a,float maximum) { float r=length(a); return a*min(1.0,maximum/max(r,0.0000001)); }
void main() {
 uint i=gl_GlobalInvocationID.x; uint stage=pc.stage;
 if(stage==0u) { if(i<4096u) heads[i]=-1; return; }
 if(i>=pc.count) return;
 if(stage==1u) { old[i]=p[i]; v[i].xyz=limited(v[i].xyz+vec3(c[0],c[1],c[2])*c[3],c[11]); p[i].xyz+=v[i].xyz*c[3]; return; }
 ivec3 cell=ivec3(floor(p[i].xyz/c[4]));
 if(stage==2u) { links[i]=atomicExchange(heads[cell_hash(cell)],int(i)); return; }
 if(stage==5u) { p[i].xyz+=delta[i].xyz; return; }
 if(stage==6u) { v[i].xyz=(p[i].xyz-old[i].xyz)/c[3]; return; }
 if(stage==8u) { v[i]=delta[i]; return; }
 float density=c[5]*kernel(0.0); float denominator=c[6]/(c[10]*c[10]); vec3 sum_g=vec3(0); vec3 correction=vec3(0); vec3 weighted=vec3(0); float weight=0.0; vec3 attraction=vec3(0);
 int found=0; int neighbors[128];
 for(int x=-1;x<=1;x++) for(int y=-1;y<=1;y++) for(int z=-1;z<=1;z++) {
  ivec3 at=cell+ivec3(x,y,z); int j=heads[cell_hash(at)]; int guard=0;
  while(j>=0 && guard++<512) {
   int next=links[j];
   if(j!=int(i) && all(equal(ivec3(floor(p[j].xyz/c[4])),at))) {
    vec3 d=p[i].xyz-p[j].xyz; float d2=dot(d,d);
    if(d2<c[4]*c[4]) {
     // Atomic hash insertion order varies across runs. Keep the lowest IDs in
     // sorted order so floating-point reductions and replay are reproducible.
     int slot=min(found,127);
     if(found<128 || j<neighbors[127]) {
      while(slot>0 && neighbors[slot-1]>j) { if(slot<128) neighbors[slot]=neighbors[slot-1]; slot--; }
      neighbors[slot]=j; found=min(found+1,128);
     }
    }
   }
   j=next;
  }
 }
 for(int k=0;k<found;k++) {
  int j=neighbors[k]; vec3 d=p[i].xyz-p[j].xyz; float d2=dot(d,d); float w=c[5]*kernel(d2);
  if(stage==3u) { density+=w; vec3 g=c[5]*gradient(d); sum_g+=g; denominator+=dot(g,g); }
  if(stage==4u) { float artificial=-0.00005*pow(kernel(d2)/kernel(c[4]*c[4]*0.09),4.0)*c[10]*c[10]; correction+=(ld[i].x+ld[j].x+artificial)*c[5]*gradient(d); }
  if(stage==7u) { weighted+=(v[j].xyz-v[i].xyz)*w; weight+=w; if(d2>c[10]*c[10]) attraction-=d*w*c[8]; attraction-=d*w*c[9]*0.2; }
 }
 if(stage==3u) { denominator+=dot(sum_g,sum_g); ld[i]=vec4(-max(density-1.0,0.0)/max(0.000001,denominator),density,0,0); }
 if(stage==4u) delta[i]=vec4(limited(correction,c[10]*0.25),0);
 if(stage==7u) delta[i]=vec4(v[i].xyz+weighted/max(1.0,weight)*(1.0-exp(-c[7]*c[3]))+attraction*c[3],0);
}
