
import MetalBuilder
import MetalKit
import TransformGesture
import SwiftUI

protocol RenderableParticle{
    var coord: simd_float2 { get }
    var size: Float { get }
    var color: simd_float3 { get }
}

// Building block for rendering particles
struct RenderParticles<T: RenderableParticle>: MetalBuildingBlock {
    
    var pipColorDesc: MTLRenderPipelineColorAttachmentDescriptor{
        let desc = MTLRenderPipelineColorAttachmentDescriptor()
        desc.isBlendingEnabled = false
        desc.rgbBlendOperation = .add
        desc.alphaBlendOperation = .add
        desc.sourceRGBBlendFactor = .sourceAlpha
        desc.sourceAlphaBlendFactor = .one
        desc.destinationRGBBlendFactor = .one
        desc.destinationAlphaBlendFactor = .one
        return desc
    }
    
    var context: MetalBuilderRenderingContext
    var helpers = ""
    var librarySource = ""
    var compileOptions: MetalBuilderCompileOptions? = nil
    
    let particlesBuffer: MTLBufferContainer<T>
    let toTexture: MTLTextureContainer? = nil
    let uniforms: UniformsContainer
    
    @ObservedObject var transform: TouchTransform
    
    var metalContent: MetalContent{
        Render(type: .point, count: particlesCount)
            .toTexture(toTexture)
            .vertexBuf(particlesBuffer, name: "particles")
            .vertexBytes($transform.matrix, type: "float3x3", name: "transform")
            .vertexBytes(context.$viewportToDeviceTransform)
            .vertexBytes($transform.floatScale, type: "float", name: "scale")
            .vertexBytes(context.$scaleFactor)
            .uniforms(uniforms, name: "u")
            .pipelineColorAttachment(pipColorDesc)
            .colorAttachement(
                loadAction: .clear,
                clearColor: .clear)
            .vertexShader(VertexShader("vertexShader", vertexOut:"""
            struct VertexOut{
                float4 position [[position]];
                float size [[point_size]];
                float3 color;
            };
            """, body:"""
              VertexOut out;
              Particle p = particles[vertex_id];
              float3 pos = float3(p.coord.xy, 1);
              pos *= transform;
        
              pos *= viewportToDeviceTransform;
        
              out.position = float4(pos.xy, 0, 1);
              out.size = p.size*scale*scaleFactor;
              out.color = p.color*pow(length(p.coord-p.prevCoord)*u.bright, u.brpow);
              return out;
        """))
            .fragmentShader(FragmentShader("fragmentShader",
                                           source:
        """
            fragment float4 fragmentShader(VertexOut in [[stage_in]],
                                           float2 p [[point_coord]]){
                float mask = smoothstep(.5, .45, length(p-.5));
                if (mask==0) discard_fragment();
                return float4((in.color+.5)*pow((0.5-length(p-.5))*2.,.5), mask);
            }
        """))
    }
}
