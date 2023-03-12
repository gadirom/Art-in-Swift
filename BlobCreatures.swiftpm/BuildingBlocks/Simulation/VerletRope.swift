
import MetalBuilder
import MetalKit
import SwiftUI

let maxBlobCount = 100

struct VerletRope<T: SimulatableParticle>: MetalBuildingBlock {
    
    static func addUniforms(_ desc: inout UniformsDescriptor){
        desc = desc
            .float("cfric", range: 0...2, value: 0.42)
            .float("cdist", range: 0...10, value: 1)
            .float("afric", range: 0...5, value: 0.01)
            .float("adist", range: 0...10, value: 0.5)
            .float("area", range: 0...500, value: 10)
    }
    
    var context: MetalBuilderRenderingContext
    var helpers = """
    Particle constrain(Particle p, Particle p1, Particle p2,
                       constant Uniforms& u,
                       float dif){
          if(!p1.connected) return p;
          float2 axis = p1.coord - p.coord;
          float dist = length(axis);
          if (dist == 0) return p;
          float size = (p.size+p1.size)*u.cdist;
          if (dist!=size){
              float shift = dist-size;
              float2 n = axis/dist;
              p.coord += shift*n*u.cfric;
          }
          if(!p.angular) return p;
          auto n = float2(p2.coord.y - p1.coord.y, -(p2.coord.x - p1.coord.x));
          auto ln = length(n);
          if(ln==0) return p;
          p.coord -= n*u.afric*dif*0.001/ln;
          
          p.color = (p1.color+p2.color+p.color)/3.;
          
          return p;
    }
    """
    var librarySource = ""
    var compileOptions: MetalBuilderCompileOptions? = nil
    
    var particlesBuffer: MTLBufferContainer<T>
    var particlesBuffer1: MTLBufferContainer<T>
    
    var uniforms: UniformsContainer
    
    @MetalBinding var particlesCount: Int
    
    @MetalBuffer<Float>(
        BufferDescriptor(count: maxBlobCount, metalName: "blobsDefaultAreas")
    ) var blobDefaultAreas
    
    @MetalBuffer<Float>(
        BufferDescriptor(count: maxBlobCount, metalType: "atomic_float", metalName: "blobAreas")
    ) var blobAreas
    
    var metalContent: MetalContent{
        ManualEncode{_, _, _ in
            for i in 0..<maxBlobCount{
                blobAreas.pointer![i] = 0
            }
        }
        Compute("countBlobArea")
            .buffer(particlesBuffer, name: "particles",
                    fitThreads: true)
            .buffer(blobDefaultAreas)
            .buffer(blobAreas, space: "device")
            .uniforms(uniforms, name: "u")
            .bytes($particlesCount, name: "count")
            .source("""
              kernel void countBlobArea(uint id [[thread_position_in_grid]]){
                if(id>=count) return;
                auto p = particles[id];
                if(!p.angular) return;
                float areasum = p.coord.x * (particles[p.p1].coord.y - particles[p.p2].coord.y);
                atomic_fetch_add_explicit(&blobAreas[p.blobID], areasum, memory_order_relaxed);
              }
              """)
            Compute("collision1")
                .buffer(particlesBuffer, space: "constant", name: "particlesIn",
                        fitThreads: true)
                .buffer(particlesBuffer1, space: "device", name: "particlesOut")
                .buffer(blobDefaultAreas)
                .buffer(blobAreas, space: "device")
                .uniforms(uniforms, name: "u")
                .bytes($particlesCount, name: "count")
                .source("""
                  kernel void collision1(uint id [[thread_position_in_grid]]){
                    if(id>=count) return;
                    auto p = particlesIn[id];
                  
                    if(!p.moves||!p.connected) return;
                    auto dif = u.area - atomic_load_explicit(&blobAreas[p.blobID], memory_order_relaxed);
                    dif = min(max(0., dif+length(p.color)*u.lArea), u.area);
                    p = constrain(p, particlesIn[p.p1], particlesIn[p.p2], u, dif);
                    p = constrain(p, particlesIn[p.p2], particlesIn[p.p1], u, -dif);
                  
                    particlesOut[id] = p;
                  }
                  """)
            Compute("collision2")
                 .buffer(particlesBuffer1, space: "constant", name: "particlesIn",
                            fitThreads: true)
                 .buffer(particlesBuffer, space: "device", name: "particlesOut")
                 .buffer(blobDefaultAreas)
                 .buffer(blobAreas, space: "device")
                 .uniforms(uniforms, name: "u")
                 .bytes($particlesCount, name: "count")
                 .source("""
                  kernel void collision2(uint id [[thread_position_in_grid]]){
                    if(id>=count) return;
                    auto p = particlesIn[id];
                                        
                    if(!p.moves||!p.connected) return;
                    auto dif = u.area - atomic_load_explicit(&blobAreas[p.blobID], memory_order_relaxed);
                    dif = min(max(0., dif+length(p.color)*u.lArea), u.area);
                    p = constrain(p, particlesIn[p.p2], particlesIn[p.p1], u, -dif);
                    p = constrain(p, particlesIn[p.p1], particlesIn[p.p2], u, dif);
                    
                    particlesOut[id] = p;
                  }
                  """)
//                        BlitBuffer()
//                            .source(particlesBuffer1)
//                            .destination(particlesBuffer)
    }
}
