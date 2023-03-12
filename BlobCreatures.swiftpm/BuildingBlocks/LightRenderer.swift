
import MetalBuilder
import MetalKit
import SwiftUI

protocol LightProtocol: MetalStruct{
    var coord: simd_float2 {get set}
    var color: simd_float3 {get set}
}

struct Light: LightProtocol{
    var coord: simd_float2 = [0,0]
    var color: simd_float3 = [0,0,0]
}

// Building block for rendering light with SDF
struct LightRenderer<T: LightProtocol>: MetalBuildingBlock, Renderable {
    
    static func addUniforms(_ desc: inout UniformsDescriptor){
        desc = desc
            .float("lSteps", range: 0...200, value: 16)
            .float("lSpeed", range: 0...10, value: 0.5)
            .float("lHard", range: 0...50, value: 2)
            .float("l", range: 0...0.02, value: 0.01)
    }
    
    internal var renderableData = RenderableData()
    
    struct QuadVertex: MetalStruct{
        var coord: simd_float2 = [0, 0]
        var uv: simd_float2 = [0, 0]
    }
    
    var context: MetalBuilderRenderingContext
    var helpers = """
            
            #define LIGHTS_COUNT \(maxLights)

            struct ray {
                float2 t;
                float2 p;
                float2 d;
            };

            ray newRay (float2 origin, float2 target, constant Uniforms &u) {
                ray r;
                
                r.t = target;
                r.p = origin;
                r.d = (target - origin) / float (u.lSteps);
                
                return r;
            }
            
            float scene(float2 uv, texture2d<float, access::sample> sdf){
                constexpr sampler s(address::clamp_to_zero, filter::linear);
                float f = sdf.sample(s, uv).r;
                return 1/f;
            };

            void rayMarch (thread ray &r, texture2d<float, access::sample> sdf, constant Uniforms &u) {
                r.p += r.d * clamp (u.lHard - scene (r.p, sdf) * u.lHard  * 2.0, 0.0, u.lSpeed);
            }

            float3 light (ray r, float3 color) {
                return color / (dot (r.p, r.p) + color);
            }
            """
    var librarySource = ""
    var compileOptions: MetalBuilderCompileOptions? = nil
    
    let particlesBuffer: MTLBufferContainer<T>
    
    @MetalBuffer<Light>(count: maxLights, metalName: "lights") var lightsBuffer
    
    let sdfTexture: MTLTextureContainer
    let colorTexture: MTLTextureContainer
    
    @Binding var transformMatrix: simd_float3x3
    @MetalBinding var toTextureTransform: simd_float3x3
    
    @MetalBinding var center: simd_float2
    @MetalBinding var size: simd_float2
    
    var uniforms: UniformsContainer
    
    @MetalBuffer<QuadVertex>(count: 6, metalName: "quadBuffer") var quadBuffer
    
    @MetalState var firstRun = true
    
    func startup(){
        //create quad
        let p = quadBuffer.pointer!
        let s = size
        let c = center
        p[0] = .init(coord: [-s.x, -s.y]+c, uv: [0,0])
        p[1] = .init(coord: [s.x, -s.y]+c, uv: [1,0])
        p[2] = .init(coord: [s.x, s.y]+c, uv: [1,1])
        
        p[3] = .init(coord: [-s.x, s.y]+c, uv: [0,1])
        p[4] = .init(coord: [-s.x, -s.y]+c, uv: [0,0])
        p[5] = .init(coord: [s.x, s.y]+c, uv: [1,1])
    }
    
    var metalContent: MetalContent{
        ManualEncode{_,_,_ in
            for i in 0..<maxLights{
                let p = particlesBuffer.pointer![i+firstLightID]
                var coord = toTextureTransform.transformed2D(p.coord)
                coord = [coord.x/2+0.5, -coord.y/2+0.5]
                let l = Light(coord: coord, color: p.color)
                lightsBuffer.pointer![i] = l
            }
        }
        Render(type: .triangle, count: 6, renderableData: renderableData)
            .vertexBuf(quadBuffer)
            .uniforms(uniforms, name: "u")
            .fragTexture(sdfTexture, argument: .init(type: "float", access: "sample", name: "sdf"))
            .fragTexture(colorTexture, argument: .init(type: "float", access: "sample", name: "colorTexture"))
            .fragBuf(lightsBuffer)
            .vertexBytes($transformMatrix, type: "float3x3", name: "transform")
            .vertexBytes(context.$viewportToDeviceTransform)
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
        
           float3 l = 0;
            
            for (int i = 0; i < LIGHTS_COUNT; i++) {
               ray r = newRay(in.uv, lights[i].coord, u);
               for (int j = 0; j < u.lSteps; j++) {
                    rayMarch (r, sdf, u);
               }
               r.p -= r.t;
               l += light(r, lights[i].color*u.l*0.1);
            }
            
            float f = clamp (scene (in.uv, sdf) * 200.0 - 100.0, 0.0, 3.0);
            
            float3 lightColor = float3(l * (1.0 + f));
                    
            constexpr sampler s(address::clamp_to_zero, filter::linear);
            float3 color = colorTexture.sample(s, in.uv).rgb;
            return float4(pow(color*lightColor, .2), 1.);
        """))
    }
}
