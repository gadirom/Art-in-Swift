
import MetalBuilder
import MetalKit

struct Verlet<T: SimulatableParticle>: MetalBuildingBlock {
    
    static func addUniforms(_ desc: inout UniformsDescriptor){
        desc = desc
            .float("maxsp", range: 0...1, value: 1)
            .float("fric", range: 0...2, value: 0.42)
            .float("dist", range: 0...1, value: 0.25)
            .float("grav", range: 0...2, value: 0.47)
            .float("passes", range: 0...30, value: 1)
    }
    
    var context: MetalBuilderRenderingContext
    var helpers = ""
    var librarySource = ""
    var compileOptions: MetalBuilderCompileOptions? = nil
    
    var particlesBuffer: MTLBufferContainer<T>
    var particlesBuffer1: MTLBufferContainer<T>
    
    var uniforms: UniformsContainer
    
    @MetalBinding var particlesCount: Int
    
    @MetalState var passes: Int = 0
    
    var metalContent: MetalContent{
        ManualEncode{_, _, _ in
            passes = Int(uniforms.getFloat("passes")!)
        }
        let collisionSource = """
                  kernel void forces(uint id [[thread_position_in_grid]]){
                      if(id>=count) return;
                      auto p = particlesIn[id];
                      if(!p.moves) return;
                      for(uint id1=0; id1<count; id1++){
                          if (id==id1) continue;
                          auto p1 = particlesIn[id1];
                          //if(p.connected && p1.connected) return;
                          float2 axis = p1.coord - p.coord;
                          float dist = length(axis);
                          if (dist == 0) continue;
                          float size = (p.size+p1.size)*u.dist;
                          if (dist<size){
                              float shift = size-dist;
                              float2 n = axis/dist;
                              p.coord.xy -= shift*n*u.fric;
                          }
                      }
                      particlesOut[id] = p;
                  }
             """
        EncodeGroup(){
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
        }.repeating($passes)
    }
}
