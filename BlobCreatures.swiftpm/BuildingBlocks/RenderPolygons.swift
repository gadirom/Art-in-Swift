
import MetalBuilder
import MetalKit
import TransformGesture
import SwiftUI

protocol RenderableParticle{
    var coord: simd_float2 { get }
    var size: Float { get }
    var color: simd_float3 { get }
}

let polygonsRendererStencilTextureDescriptor = TextureDescriptor()
    .pixelFormat(.stencil8)
    .usage([.renderTarget, .shaderRead])

// Building block for rendering particles
struct RenderPolygons<T: RenderableParticle>: MetalBuildingBlock, Renderable {
    internal init(renderableData: RenderableData = RenderableData(),
                  renderTexturePixelFormat: MTLPixelFormat,
                  context: MetalBuilderRenderingContext,
                  particlesBuffer: MTLBufferContainer<T>,
                  uniforms: UniformsContainer,
                  fragmentShader: FragmentShader?=nil,
                  transform: MetalBinding<simd_float3x3>,
                  particlesCount: MetalBinding<Int>,
                  maxParticles: Int,
                  maxPolygons: Int) {
        self.renderableData = renderableData
        self.context = context
        self.particlesBuffer = particlesBuffer
        self.uniforms = uniforms
        self._transform = transform
        self._particlesCount = particlesCount
        self.maxParticles = maxParticles
        self.maxPolygons = maxPolygons
        
        if let fragmentShader = fragmentShader{
            self.fragmentShader = fragmentShader
        }else{
            self.fragmentShader = FragmentShader("polygonFragmentShader",
                                            body:
             """
                 return float4(in.color, 1);
             """)
        }
        
        self.renderTexturePixelFormat = renderTexturePixelFormat
    }
    
    
    
    var renderableData = RenderableData()
    
    //Descriptors for these textures will be determined later in just started section
    @MetalTexture(TextureDescriptor()) var renderTexture
    @MetalTexture(polygonsRendererStencilTextureDescriptor) var stencilTexture
    
    var pipColorDescPass1: MTLRenderPipelineColorAttachmentDescriptor{
        let desc = MTLRenderPipelineColorAttachmentDescriptor()
        desc.isBlendingEnabled = false
        desc.rgbBlendOperation = .add
        desc.alphaBlendOperation = .add
        desc.sourceRGBBlendFactor = .sourceAlpha
        desc.sourceAlphaBlendFactor = .one
        desc.destinationRGBBlendFactor = .one
        desc.destinationAlphaBlendFactor = .one
        desc.pixelFormat = renderTexturePixelFormat
        return desc
    }
    
    var renderTexturePixelFormat: MTLPixelFormat
    var stencilPass1: MTLDepthStencilDescriptor{
        let desc = MTLDepthStencilDescriptor()
        desc.isDepthWriteEnabled = false
        
        let stencilDesc = MTLStencilDescriptor()
        
        stencilDesc.stencilCompareFunction = .always
        stencilDesc.stencilFailureOperation = .zero
        
        stencilDesc.depthFailureOperation = .zero
        stencilDesc.depthStencilPassOperation = .invert
        
        desc.frontFaceStencil = stencilDesc
        desc.backFaceStencil = stencilDesc

        desc.frontFaceStencil.readMask = 0x1
        desc.frontFaceStencil.writeMask = 0x1
        return desc
    }
    var stencilPass2: MTLDepthStencilDescriptor{
        let desc = MTLDepthStencilDescriptor()

        let stencilDesc = MTLStencilDescriptor()
        stencilDesc.stencilCompareFunction = .equal
        stencilDesc.stencilFailureOperation = .keep
        
        stencilDesc.depthFailureOperation = .keep
        stencilDesc.depthStencilPassOperation = .keep
        
        desc.frontFaceStencil = stencilDesc
        desc.backFaceStencil = stencilDesc

        desc.frontFaceStencil.readMask = 0x1
        desc.frontFaceStencil.writeMask = 0x1
        return desc
    }
    
    var context: MetalBuilderRenderingContext
    var helpers = ""
    var librarySource = ""
    var compileOptions: MetalBuilderCompileOptions? = nil
    
    let particlesBuffer: MTLBufferContainer<T>
    let uniforms: UniformsContainer
    
    let fragmentShader: FragmentShader
    
    @MetalBinding var transform: simd_float3x3
    
    @MetalBinding var particlesCount: Int
    let maxParticles: Int
    let maxPolygons: Int
    
    @MetalState var indexNonZero = false
    @MetalState var indexZero = true
    
    @MetalState(metalName: "indexCount") var indexCount: Int = 0
    @MetalBuffer<UInt32>(
        BufferDescriptor(count: 1, metalType: "atomic_uint", metalName: "indexCounter")
    ) var counterBuffer
    
    @MetalBuffer<Int32>(
        BufferDescriptor(count: 1, metalType: "atomic_int", metalName: "polygonPoints")
    ) var polygonPoints  // contains ID of some point in a polygon of a given breed
    
    @MetalBuffer<UInt32>(
        BufferDescriptor(count: 1, metalName: "indices")
    ) var indexBuffer
    
    func setup() {
        var renderTextureDesc: TextureDescriptor
        var stencilTextureDesc: TextureDescriptor
        
        if let toTexture = renderableData.passColorAttachments[0]?.texture,
           case let .fixed(size) = toTexture.descriptor.size{
            renderTextureDesc = toTexture.descriptor
                //.usage([.renderTarget, .shaderRead])
            stencilTextureDesc = polygonsRendererStencilTextureDescriptor
                .fixedSize(size)
        }else{
            renderTextureDesc = TextureDescriptor()
                .sizeFromViewport()
                .pixelFormatFromDrawable()
            
            stencilTextureDesc = polygonsRendererStencilTextureDescriptor
                .sizeFromViewport()
        }
        
        renderTexture.descriptor = renderTextureDesc
        stencilTexture.descriptor = stencilTextureDesc
       
        indexBuffer.count = maxParticles*3
        polygonPoints.count = maxPolygons
    }
    
    var metalContent: MetalContent{
        ManualEncode{_,_,_ in
            for i in 0..<maxPolygons{
                polygonPoints.pointer![i] = -1
            }
            counterBuffer.pointer![0] = 0
        }
        Compute("findPolygonPoints")
            .buffer(particlesBuffer, name: "particles", fitThreads: true)
            .buffer(polygonPoints, space: "device")
            .bytes($particlesCount, name: "count")
            .source("""
              kernel void findPolygonPoints(uint id [[thread_position_in_grid]]){
                if(id>=count) return;
                auto p = particles[id];
                if(!p.angular) return;
                auto breed = p.blobID;
                auto pid0 = atomic_load_explicit(&polygonPoints[breed], memory_order_relaxed);
                //if no point for this breed - set the point and return
                if(pid0==-1){
                    atomic_store_explicit(&polygonPoints[breed], id, memory_order_relaxed);
                    return;
                }
              }
              """)
        Compute("createIndices")
            .buffer(particlesBuffer, name: "particles", fitThreads: true)
            .buffer(polygonPoints, space: "device")
            .buffer(counterBuffer, space: "device")
            .buffer(indexBuffer, space: "device")
            .bytes($particlesCount, name: "count")
            .source("""
              kernel void createIndices(uint id [[thread_position_in_grid]]){
                if(id>=count) return;
                auto p = particles[id];
                if(!p.angular) return;
                auto breed = p.blobID;
                auto pid0 = atomic_load_explicit(&polygonPoints[breed], memory_order_relaxed);
                //if no point for this breed - it means there is no points of this breed
                if(pid0==-1||id==pid0||pid0==p.p1){
                    return;
                }
                //if there is a point, create indices for triangle
                auto index = atomic_fetch_add_explicit(&indexCounter[0], 3, memory_order_relaxed);
                auto pid1 = id;
                auto pid2 = p.p1;
                indices[index] = pid0;
                indices[index+1] = pid1;
                indices[index+2] = pid2;
              }
              """)
        CPUCompute{_ in
            indexCount = Int(counterBuffer.pointer![0])
            indexNonZero = indexCount > 0
            indexZero = !indexNonZero
        }
        EncodeGroup(active: $indexNonZero){
            Render(type: .triangle,
                   indexBuffer: indexBuffer,
                   indexCount: $indexCount)
            .vertexBuf(particlesBuffer, name: "particles")
            .vertexBytes($transform, type: "float3x3", name: "transform")
            //.vertexBytes(context.$viewportToDeviceTransform)
            .uniforms(uniforms, name: "u")
            .pipelineColorAttachment(pipColorDescPass1)
            .colorAttachement(
                texture: renderTexture,
                loadAction: .clear,
                clearColor: .clear)
            .stencilAttachment(texture: stencilTexture,
                               loadAction: .clear,
                               storeAction: .store,
                               clearStencil: 0)
            .depthDescriptor(stencilPass1)
            .vertexShader(VertexShader("polygonVertexShader", vertexOut:"""
            struct PolygonVertexOut{
                float4 position [[position]];
                uint breed;
                float3 color;
            };
            """, body:"""
              PolygonVertexOut out;
              Particle p = particles[vertex_id];
              float3 pos = float3(p.coord.xy, 1);
              pos *= transform;
              //pos *= viewportToDeviceTransform;
        
              out.position = float4(pos.xy, 0, 1);
              out.color = p.color*pow(length(p.coord-p.prevCoord)*u.bright, u.brpow);
              return out;
        """))
            .fragmentShader(fragmentShader)
            FullScreenQuad(renderableData: renderableData,
                           context: context,
                           sampleTexture: renderTexture)
            .stencilAttachment(texture: stencilTexture,
                               loadAction: .load,
                               storeAction: .dontCare)
            .depthDescriptor(stencilPass2, stencilReferenceValue: 0x1)
        }
        EncodeGroup(active: $indexZero){
            ClearRender()
                .texture(renderableData.passColorAttachments[0]!.texture!)
                .color(.white)
        }
    }
}
