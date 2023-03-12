
import MetalBuilder
import MetalKit

struct Verlet<T: SimulatableParticle>: MetalBuildingBlock {
    
    static func addUniforms(_ desc: inout UniformsDescriptor){
        desc = desc
            .float("maxsp", range: 0...1, value: 1)
            .float("fric", range: 0...2, value: 0.42)
            .float("dist", range: 0...10, value: 0.25)
            .float("rfric", range: 0...2, value: 0.42)
            .float("rdist", range: 0...1, value: 0.25)
            .float("sfric", range: 0...2, value: 0.42)
            .float("sdist", range: 0...1, value: 0.25)
            .float("grav", range: 0...2, value: 0.47)
        
    }
    
    var context: MetalBuilderRenderingContext
    var helpers = """
    Particle verletForce(Particle p, Particle p1, float ufric, float udist){
      float2 axis = p1.coord - p.coord;
      float dist = length(axis);
      if (dist == 0) return p;
      float size = (p.size+p1.size)*udist;
      if (dist<size){
          float shift = size-dist;
          float2 n = axis/dist;
          p.coord.xy -= shift*n*ufric;
      }
      return p;
    }
    """
    var librarySource = ""
    var compileOptions: MetalBuilderCompileOptions? = nil
    
    var particlesBuffer: MTLBufferContainer<T>
    var particlesBuffer1: MTLBufferContainer<T>
    
    var uniforms: UniformsContainer
    
    @MetalBinding var particlesCount: Int
    
    var metalContent: MetalContent{
        let collisionSource = """
                  kernel void forces(uint id [[thread_position_in_grid]]){
                      if(id>=count) return;
                      auto p = particlesIn[id];
                      if(!p.moves) return;
                      for(uint id1=0; id1<count; id1++){
                          if (id==id1) continue;
                          if (p.p1==id1||p.p2==id1) continue;
                          auto p1 = particlesIn[id1];
                          if(p.connected){
                            if(p1.connected){
                                if(p.angular&&p1.angular){
                                  if(p.blobID==p1.blobID){
                                      p = verletForce(p, p1, u.rfric, u.rdist);
                                      continue;
                                  }
                                }else{
                                      p = verletForce(p, p1, u.rfric, u.rdist);
                                      continue;
                                }
                              }
                              p = verletForce(p, p1, u.fric, u.dist);
                              p.color+=p1.color*u.lAdd*max(0., u.lDist-length(p1.coord - p.coord));
                              continue;
                            }
                            p = verletForce(p, p1, u.sfric, u.sdist);
                      }
                      particlesOut[id] = p;
                  }
             """
            Compute("forces")
                .buffer(particlesBuffer, space: "constant", name: "particlesIn",
                        fitThreads: true)
                .buffer(particlesBuffer1, space: "device", name: "particlesOut")
                .uniforms(uniforms, name: "u")
                .bytes($particlesCount, name: "count")
                .source(collisionSource)
            Compute("forces")
                 .buffer(particlesBuffer1, space: "constant", name: "particlesIn",
                 fitThreads: true)
                 .buffer(particlesBuffer, space: "device", name: "particlesOut")
                 .uniforms(uniforms, name: "u")
                 .bytes($particlesCount, name: "count")
//                        BlitBuffer()
//                            .source(particlesBuffer1)
//                            .destination(particlesBuffer)
    }
}
