
import MetalBuilder
import MetalKit
import SwiftUI

// Building block for rendering a quad
struct QuadRenderer: MetalBuildingBlock {
    
    struct QuadVertex: MetalStruct{
        var coord: simd_float2 = [0, 0]
        var uv: simd_float2 = [0, 0]
    }
    
    var pipColorDesc: MTLRenderPipelineColorAttachmentDescriptor{
        let desc = MTLRenderPipelineColorAttachmentDescriptor()
        desc.isBlendingEnabled = true
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
    
    let toTexture: MTLTextureContainer?
    let sampleTexture: MTLTextureContainer
    
    @Binding var transformMatrix: simd_float3x3
    
    @MetalBuffer<QuadVertex>(count: 6, metalName: "quadBuffer") var quadBuffer
    
    @MetalState var firstRun = true
    
    func createQuad(){
        let p = quadBuffer.pointer!
        let c = canvasD
        p[0] = .init(coord: [-c.x, -c.y], uv: [0,0])
        p[1] = .init(coord: [c.x, -c.y], uv: [1,0])
        p[2] = .init(coord: [c.x, c.y], uv: [1,1])
        
        p[3] = .init(coord: [-c.x, c.y], uv: [0,1])
        p[4] = .init(coord: [-c.x, -c.y], uv: [0,0])
        p[5] = .init(coord: [c.x, c.y], uv: [1,1])
    }
    
    var metalContent: MetalContent{
        CPUCompute{_ in
            if firstRun{
                createQuad()
                firstRun = false
            }
        }
        Render(type: .triangle, count: 6)
            .vertexBuf(quadBuffer)
            .toTexture(toTexture)
            .fragTexture(sampleTexture, argument: .init(type: "float", access: "sample", name: "inTexture"))
            .vertexBytes($transformMatrix, type: "float3x3", name: "transform")
            .vertexBytes(context.$viewportToDeviceTransform)
            .pipelineColorAttachment(pipColorDesc)
            .colorAttachement(
                loadAction: .load,
                clearColor: .clear)
            .vertexShader(VertexShader("quadVertexShader", vertexOut:"""
            struct QuadVertexOut{
                float4 position [[position]];
                float2 uv;
            };
            """, body:"""
              QuadVertexOut out;
              QuadVertex p = quadBuffer[vertex_id];
              float3 pos = float3(p.coord.xy, 1);
              pos *= transform;
              pos *= viewportToDeviceTransform;
        
              out.position = float4(pos.xy, 0, 1);
              out.uv = p.uv;
              return out;
        """))
            .fragmentShader(FragmentShader("quadFragmentShader",
                                           returns: "float4",
                                           body:
        """
            constexpr sampler s(address::clamp_to_zero, filter::linear);
            float4 color = inTexture.sample(s, in.uv);
            return color;
        """))
    }
}
