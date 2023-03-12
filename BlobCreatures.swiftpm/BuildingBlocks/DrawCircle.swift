
import MetalBuilder
import MetalKit

// Building block for drawing a circle on a texture
struct DrawCircle: MetalBuildingBlock {
    
    struct CircleStruct: MetalStruct{
        var coord: simd_float2 = [0, 0]
    }
    
    var pipColorDesc: MTLRenderPipelineColorAttachmentDescriptor{
        let desc = MTLRenderPipelineColorAttachmentDescriptor()
        desc.isBlendingEnabled = true
        desc.rgbBlendOperation = .max
        desc.alphaBlendOperation = .max
        desc.sourceRGBBlendFactor = .blendAlpha
        desc.sourceAlphaBlendFactor = .sourceAlpha
        desc.destinationRGBBlendFactor = .oneMinusBlendColor
        desc.destinationAlphaBlendFactor = .oneMinusBlendAlpha
        desc.pixelFormat = .rgba16Float
        return desc
    }
    
    var context: MetalBuilderRenderingContext
    var helpers = ""
    var librarySource = ""
    var compileOptions: MetalBuilderCompileOptions? = nil
    
    let texture: MTLTextureContainer
    
    @MetalBinding var touchCoord: simd_float2
    @MetalBinding var circleSize: Float
    @MetalBinding var canvasSize: simd_float2
    
    @MetalBuffer<CircleStruct>(count: 1, metalName: "circles") var circleBuffer
    
    var metalContent: MetalContent{
        CPUCompute{_ in
            let coord: simd_float2 = [touchCoord.x, -touchCoord.y] / canvasSize * 2
            circleBuffer.pointer![0] = .init(coord: coord)
        }
        Render(vertex: "circleVertexShader", fragment: "circleFragmentShader", type: .point, count: 1)
            .vertexBuf(circleBuffer)
            .vertexBytes($circleSize, name: "size")
            .pipelineColorAttachment(self.pipColorDesc)
            .colorAttachement(
                texture: texture,
                loadAction: .load,
                clearColor: .black)
            .vertexShader(VertexShader("circleVertexShader", vertexOut:"""
            struct CircleVertexOut{
                float4 position [[position]];
                float size [[point_size]];
                float3 color;
            };
            """, body:"""
              CircleVertexOut out;
              out.position = float4(circles[vertex_id].coord, 0, 1);
              out.size = size;
              out.color = 1;
              return out;
        """))
            .fragmentShader(FragmentShader("circleFragmentShader",
                                           source:
        """
            fragment float4 circleFragmentShader(CircleVertexOut in [[stage_in]],
                                           float2 p [[point_coord]]){
                float mask = smoothstep(.5, .45, length(p-.5));
                if (mask==0) discard_fragment();
                return float4(in.color, mask*0.5);
            }
        """))
    }
}
