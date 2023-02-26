
import MetalBuilder
import MetalKit
import SwiftUI

struct VerletRope<T: SimulatableParticle>: MetalBuildingBlock {
    
    static func addUniforms(_ desc: inout UniformsDescriptor){
        desc = desc
            .float("cfric", range: 0...2, value: 0.42)
            .float("cdist", range: 0...10, value: 1)
            .float("cpasses", range: 0...30, value: 1)
    }
    
    var context: MetalBuilderRenderingContext
    var helpers = """
    Particle constrain(Particle p, Particle p1, constant Uniforms& u){
          if(!p1.connected) return p;
          float2 axis = p1.coord - p.coord;
          float dist = length(axis);
          if (dist == 0) return p;
          float size = (p.size+p1.size)*u.cdist;
          if (dist>size){
              float shift = dist-size;
              float2 n = axis/dist;
              p.coord += shift*n*u.cfric;
          }
          return p;
    }
    """
    var librarySource = ""
    var compileOptions: MetalBuilderCompileOptions? = nil
    
    var particlesBuffer: MTLBufferContainer<T>
    var particlesBuffer1: MTLBufferContainer<T>
    
    var uniforms: UniformsContainer
    
    @MetalState var passes: Int = 0
    
    @MetalBinding var particlesCount: Int
    
    var metalContent: MetalContent{
        ManualEncode{_, _, _ in
            passes = Int(uniforms.getFloat("cpasses")!)
        }
            EncodeGroup(){
            Compute("collision1")
                .buffer(particlesBuffer, space: "constant", name: "particlesIn",
                        fitThreads: true)
                .buffer(particlesBuffer1, space: "device", name: "particlesOut")
                .uniforms(uniforms, name: "u")
                .bytes($particlesCount, name: "count")
                .source("""
                  kernel void collision1(uint id [[thread_position_in_grid]]){
                      if(id>=count) return;
                      auto p = particlesIn[id];
                      if(!p.moves||!p.connected) return;
                      if (id>=0&&id<count-1){
                         p = constrain(p, particlesIn[p.p1], u);
                         p = constrain(p, particlesIn[p.p2], u);
                      }
                      particlesOut[id] = p;
                  }
                  """)
            Compute("collision2")
                 .buffer(particlesBuffer1, space: "constant", name: "particlesIn",
                 fitThreads: true)
                 .buffer(particlesBuffer, space: "device", name: "particlesOut")
                 .uniforms(uniforms, name: "u")
                 .bytes($particlesCount, name: "count")
                 .source("""
                  kernel void collision2(uint id [[thread_position_in_grid]]){
                    if(id>=count) return;
                    auto p = particlesIn[id];
                    if(!p.moves||!p.connected) return;
                    if (id>=0&&id<count-1){
                       p = constrain(p, particlesIn[p.p2], u);
                       p = constrain(p, particlesIn[p.p1], u);
                    }
                    particlesOut[id] = p;
                  }
                  """)
//                        BlitBuffer()
//                            .source(particlesBuffer1)
//                            .destination(particlesBuffer)
        }.repeating($passes)
    }
}
