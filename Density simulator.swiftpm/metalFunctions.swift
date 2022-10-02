let metalFunctions = """
struct VertexOut{
    float4 position [[position]];
    float size [[point_size]];
    float4 color; 
};
vertex VertexOut
vertexShader(uint id [[vertex_id]]){
  VertexOut out;
  Particle p = particles[id];
  out.position = float4(p.coord.xy, 0, 1);
  out.size = p.size*float(viewportSize.x)*0.3;
  out.color = p.color;
  return out;
}
fragment float4 fragmentShader(VertexOut in [[stage_in]],
                               float2 p [[point_coord]]){
    float mask = smoothstep(.5, .4, length(p-.5));
    if (mask==0) discard_fragment();
    return in.color;
}
kernel void integration(uint id [[thread_position_in_grid]]){
   //Integration
   Particle p = particles[id];
   float2 velo = p.coord.xy-p.coord.zw;
   p.coord.zw = p.coord.xy;
   velo += float2(0, -gravity);
   velo += p.force;
   //velo *= -1*(ceil(max(0., abs(p.coord.xy)-1.))*2-1);
   float fric2 = 1./(1.+pow(length(velo), 2));
   p.coord.xy += velo*fric*fric2;//*0.99;

   //Edge constraint
   if (p.coord.x>1) p.coord.x=1;
   if (p.coord.x<-1) p.coord.x=-1;
   if (p.coord.y>1) p.coord.y=1;
   if (p.coord.y<-1) p.coord.y=-1;

   particles[id] = p;
}

kernel void collision(uint id [[thread_position_in_grid]],
                      uint count [[threads_per_grid]]){
  Particle p = particlesIn[id];
  if(p.size==0) return;
  p.force = 0;
  for(uint id1=0; id1<count; id1++){
      if (id==id1) continue;
      Particle p1 = particlesIn[id1];
      if(p1.size==0) continue;
      float2 axis = p1.coord.xy - p.coord.xy;
      float dist = length(axis);
       if (dist == 0) continue;
      float size = p.size+p1.size;
      float br1 = breedIDs[int(p1.breed)].id;
      float br = breedIDs[int(p.breed)].id;
      if(dist<size*mul){
          if(br>br1) p.force -= float2(0, force);
          if(br<br1) p.force += float2(0, force);
       }
       //p.force = 0.02;
      if (dist<size){
        float shift = size-dist;
        float2 n = axis/dist;
        p.coord.xy -= (p.size/size)*shift*n*fric;
        //p1.coord.xy -= 0.5*shift*n;
        //particlesIn[id1] = p1;
      }
   }
   particlesOut[id] = p;
}
kernel void threshold(uint2 gid [[thread_position_in_grid]]){
     float3 in = blur.read(gid).rgb;
     float3 hue = normalize(in);
     //float light = smoothstep(threshold, threshold+0.01, length(in));
     float3 color = hue*brightness;
     out.write(float4(color, 1), gid);
}
"""
