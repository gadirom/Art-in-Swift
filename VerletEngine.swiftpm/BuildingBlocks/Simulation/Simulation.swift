
import MetalBuilder
import MetalKit

struct Simulation<T: SimulatableParticle>: MetalBuildingBlock {
    
    static func addUniforms(_ desc: inout UniformsDescriptor){
        Verlet<T>.addUniforms(&desc)
        VerletRope<T>.addUniforms(&desc)
        Integration<T>.addUniforms(&desc)
    }
    
    var context: MetalBuilderRenderingContext
    var helpers = ""
    var librarySource = ""
    var compileOptions: MetalBuilderCompileOptions? = nil
    
    var particlesBuffer: MTLBufferContainer<T>
    var particlesBuffer1: MTLBufferContainer<T>

    @MetalBinding var particlesCount: Int
    
    var obstacleTexture: MTLTextureContainer
    
    var uniforms: UniformsContainer
    
    @MetalBinding var gravity: simd_float2
    
    @MetalBinding var canvas: simd_float2
    
    var metalContent: MetalContent{
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
                    gravity: $gravity,
                    canvas: $canvas,
                    obstacleTexture: obstacleTexture,
                    particlesCount: $particlesCount)
    }
}
