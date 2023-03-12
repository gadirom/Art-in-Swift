
import MetalBuilder
import MetalKit

struct Simulation<T: SimulatableParticle>: MetalBuildingBlock {
    
    static func addUniforms(_ desc: inout UniformsDescriptor){
        Verlet<T>.addUniforms(&desc)
        VerletRope<T>.addUniforms(&desc)
        Integration<T>.addUniforms(&desc)
        desc = desc
            .float("passes", range: 0...30, value: 1)
            .float("lDist", range: 0...10, value: 2)
            .float("lAdd", range: 0...1, value: 0.01)
            .float("lSub", range: 0...1, value: 0.02)
            .float("lArea", range: 0...1000, value: 0.02)
    }
    
    var context: MetalBuilderRenderingContext
    var helpers = ""
    var librarySource = ""
    var compileOptions: MetalBuilderCompileOptions? = nil
    
    var particlesBuffer: MTLBufferContainer<T>
    var particlesBuffer1: MTLBufferContainer<T>

    @MetalBinding var particlesCount: Int
    
    var uniforms: UniformsContainer
    
    @MetalBinding var canvas: simd_float2
    
    @MetalState var passes: Int = 0
    
    var metalContent: MetalContent{
        ManualEncode{_, _, _ in
            passes = Int(uniforms.getFloat("passes")!)
        }
        EncodeGroup(){
            VerletRope.init(context: context,
                            particlesBuffer: particlesBuffer,
                            particlesBuffer1: particlesBuffer1,
                            uniforms: uniforms,
                            particlesCount: $particlesCount)
            Verlet.init(context: context,
                        particlesBuffer: particlesBuffer,
                        particlesBuffer1: particlesBuffer1,
                        uniforms: uniforms,
                        particlesCount: $particlesCount)
            Integration(context: context,
                        particlesBuffer: particlesBuffer,
                        uniforms: uniforms,
                        canvas: $canvas,
                        particlesCount: $particlesCount)
        }
    }
}
