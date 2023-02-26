
import MetalBuilder
import MetalKit

struct Integration<T: SimulatableParticle>: MetalBuildingBlock {
    
    static func addUniforms(_ desc: inout UniformsDescriptor){
        desc = desc
            .float("maxsp", range: 0...1, value: 1)
            .float("grav", range: 0...2, value: 0.47)
    }
    
    var context: MetalBuilderRenderingContext
    var helpers = ""
    var librarySource = ""
    var compileOptions: MetalBuilderCompileOptions? = nil
    
    var particlesBuffer: MTLBufferContainer<T>
    
    var uniforms: UniformsContainer
    
    @MetalBinding var gravity: simd_float2
    @MetalBinding var canvas: simd_float2
    
    let obstacleTexture: MTLTextureContainer
    
    @MetalBinding var particlesCount: Int
    
    var metalContent: MetalContent{
        Compute("integration")
            .texture(obstacleTexture, argument: .init(type: "float", access: "sample", name: "obstacle"))
            .bytes($gravity, name: "gravity")
             .buffer(particlesBuffer, space: "device", name: "particles",
             fitThreads: true)
             .uniforms(uniforms, name: "u")
             .bytes($canvas, name: "canvas")
             .bytes($particlesCount, name: "count")
             .source("""
             kernel void integration(uint id [[thread_position_in_grid]]){
                 if(id>=count) return;
                 //Integration
                 auto p = particles[id];
                 if(!p.moves) return;
                 float2 velo = p.coord-p.prevCoord;
                 p.prevCoord = p.coord;
                 velo += gravity*0.01;
                 //velo *= -0.01*(ceil(max(0., abs(p.coord)-100))*2-100);
                 float l = length(velo);
                 if(l>0){
                    velo = min(l, u.maxsp*10)*velo/l;
                 }
                 p.coord += velo;
             
                 constexpr sampler s(address::clamp_to_zero, filter::linear);
             
                 float2 uv = p.coord/canvas+0.5;
                 float d = obstacle.sample(s, uv).r;
                 if (d == 1){
                     p.coord = p.prevCoord;
                 }
                 
                 //Edge constraint
                 //if (p.coord.x>canvas.x/2) {p.coord.x-=canvas.x; p.prevCoord.x-=canvas.x;}
                 //if (p.coord.x<-canvas.x/2){p.coord.x+=canvas.x; p.prevCoord.x+=canvas.x;}
                 //if (p.coord.y>canvas.y/2) {p.coord.y-=canvas.y; p.prevCoord.y-=canvas.y;}
                 //if (p.coord.y<-canvas.y/2){p.coord.y+=canvas.y; p.prevCoord.y+=canvas.y;}
                 float2 pc = p.prevCoord;
                 if (p.coord.x>canvas.x/2) {p.prevCoord.x=p.coord.x; p.coord.x=canvas.x/2;}
                 if (p.coord.x<-canvas.x/2){p.prevCoord.x=p.coord.x; p.coord.x=-canvas.x/2;}
                 if (p.coord.y>canvas.y/2) {p.prevCoord.y=p.coord.y; p.coord.y=canvas.y/2;}
                 if (p.coord.y<-canvas.y/2){p.prevCoord.y=p.coord.y; p.coord.y=-canvas.y/2;}
                              
                 
                 particles[id] = p;
             }
             """)
    }
}
