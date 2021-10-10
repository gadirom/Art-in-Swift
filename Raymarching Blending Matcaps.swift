
// Just copy and paste the code into a blank playground template
// in Swift Playgrounds app on an iPad or a Mac
// !!! Turn off Enable Results in the settings, otherwise you'll get an error !!!
// Created by Roman Gaditskiy: https://GitHub.com/gadirom/Art-in-Swift

import MetalKit
import SwiftUI
import PlaygroundSupport
import Combine
import simd

var light: Float = 0
var dist: Float = 0

struct Uniforms {
    //object position
    var x: Float = 0
    var y: Float = 0
    var z: Float = 6
    
    //morph Position
    var lx: Float = 5
    var ly: Float = 5
    var lz: Float = 0
    
    var last: Int32 = 0
    var next: Int32 = 1
    var blend: Float = 1
    
    var r: Float = 1 // corner radius
    var k: Float = 1 // smooth coefficient 
    
    // angle
    var a: Float = 0
}

let metalFunctions = """

#include <metal_stdlib>

using namespace metal;

typedef struct
{
   float x;
   float y;
   float z;

   float lx;
   float ly;
   float lz;

   int l;
   int n;
   float b;

   float r;
   float k;

   float a;

} Uniforms;

#define MAX_STEPS 100
#define MAX_DIST 100
#define SURF_DIST 0.001

 //distance for softmin:

#define K_Dist 0.2

float4x4 rotationMatrix(float3 axis, float angle) {
    axis = normalize(axis);
    float s = sin(angle);
    float c = cos(angle);
    float oc = 1.0 - c;
    
    return float4x4(oc * axis.x * axis.x + c,           oc * axis.x * axis.y - axis.z * s,  oc * axis.z * axis.x + axis.y * s,  0.0,
                oc * axis.x * axis.y + axis.z * s,  oc * axis.y * axis.y + c,           oc * axis.y * axis.z - axis.x * s,  0.0,
                oc * axis.z * axis.x - axis.y * s,  oc * axis.y * axis.z + axis.x * s,  oc * axis.z * axis.z + c,           0.0,
                0.0,                                0.0,                                0.0,                                1.0);
}

float3 rotate(float3 v, float3 axis, float angle) {
    float4x4 m = rotationMatrix(axis, angle);
    return (m * float4(v, 1.0)).xyz;
}

float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5*(a-b)/k, 0.0, 1.0);
    return mix(a, b, h) - k*h*(1.0-h);
}

float2 matcap(float3 eye, float3 normal) {
    float3 reflected = reflect(eye, normal);
    float m = 2.8284271247461903 * sqrt( reflected.z+1.0 );
    return reflected.xy / m + 0.5;
}

float sdSphere( float3 p, float3 c, float r ) {
    return length(p - c) - r;
}

float sdRoundBox( float3 p, float3 c, float3 b, float r )
{
  float3 q = abs(p - c) - b;
  return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0) - r;
}

float sdPlane( float3 p, float height ) {
    return -p.z + 7.;
}

float getDist( float3 p, constant Uniforms *u ) {

    float3 c = float3(u->x, u->y, u->z);
    float3 c1 = float3(u->x, u->y + u->lx, u->z);
    float3 c2 = float3(u->x, u->y - u->lx, u->z);
    float3 c3 = float3(u->x - u->lx, u->y, u->z);
    float3 c4 = float3(u->x + u->lx, u->y, u->z);
    float3 p1 = rotate(p - c1, float3(1), -u->ly + u->a);
    float3 p2 = rotate(p - c2, float3(-1), -u->ly + u->a);
    float3 p3 = rotate(p - c3, float3(-1, -1, 1), -u->ly + u->a);
    float3 p4 = rotate(p - c4, float3(1, -1, 1), -u->ly + u->a);
     p = rotate(p - c, float3(-1, 1, 1), -u->ly + u->a);

    float box = sdRoundBox(p, float3(0), float3(0.5), -u->r);
    float box1 = sdRoundBox(p1, float3(0), float3(0.04, .01, .4), u->r);
    float box2 = sdRoundBox(p2, float3(0), float3(0.01, 0.4, 0.1), u->r);
    float box3 = sdRoundBox(p3, float3(0), float3(0.4, .02, .05), u->r);
    float box4 = sdRoundBox(p4, float3(0), float3(0.2, .05, .06), u->r);


    float d = smin(box1, box2, u->k);
    d = smin(d, box3, u->k);
    d = smin(d, box4, u->k);

    return smin(d, box, 1.-u->k/7);
}

float castRay( float3 ro, float3 rd, constant Uniforms *u) {
    float d0 = 0.0;
    
    for (int i = 0; i < MAX_STEPS; i++) {
        float3 p = ro + d0 * rd;
        float dS = getDist(p, u);
        
        d0 += dS;
        if ( dS <= SURF_DIST || d0 >= MAX_DIST ) break;
    }
    
    return d0;
}

float3 getNormal ( float3 p, constant Uniforms *u) {
  float d = getDist(p, u);
  float2 e = float2(0.01, 0.);
  
  float3 n = d - float3( getDist(p - e.xyy, u),
                         getDist(p - e.yxy, u),
                         getDist(p - e.yyx, u) );
                     
  return normalize(n);
}

float3 getLight( float3 p, constant Uniforms *u, texture2d<float, access::sample> m, float3 rd, float3 bg) {
  //float3 lightPos = float3(u->lx, u->ly, u->lz);
  //float3 l = normalize( lightPos - p );
  float3 n = getNormal(p, u);
  
  //float diff = dot(l, n);

  constexpr sampler s(address::clamp_to_edge, filter::linear);

  float3 diff = float3(m.sample(s, matcap(-rd, n)));
  
  //float ls = castRay(p + n * (SURF_DIST*2.), l, u);
  //float dl = length(lightPos - p);
  
  //if (ls < dl) { diff *= 0.5;}

  float frensel = pow(1. + dot(rd, n), 3);
  diff = mix(diff, bg, frensel);
  
  return diff;
}

kernel void ray_march(texture2d<float, access::write> output [[texture(0)]],
                      texture2d<float, access::sample> m [[texture(1)]],
                   constant Uniforms *u [[buffer(0)]],
                   uint2 gid [[thread_position_in_grid]])

{
    int width = output.get_width();
    int height = output.get_height();
    float2 uv = (float2(width, height) * 0.5 - float2(gid) ) / height;
    
    float3 ro = float3(0.0, 0.0, 0.0);
    float3 rd = normalize (float3(uv, 1.0));
    
    float d = castRay(ro, rd, u);
    
    float cdist = 1 - (length(uv));
    float3 bg = mix(.1, .0, pow(cdist, 3.));

    float3 light = bg;
    
    if (d < MAX_DIST) {
       float3 p = ro + d * rd;
       light = getLight(p, u, m, rd, bg);
     }

    float3 col = light;
   
    output.write(float4(col, 1.0), gid);
}

kernel void blend (texture2d<float, access::read> tex [[ texture(0) ]],
                   texture2d<float, access::read> tex1 [[ texture(1) ]],
                   texture2d<float, access::write> tex2 [[ texture(2) ]],
                                constant float &blend_state [[ buffer(0) ]],
                             uint2               id [[ thread_position_in_grid ]]) {
float4 color;
 
color = mix(tex.read(id), tex1.read(id), blend_state);

tex2.write(color, id);

}

"""

func animationFunc(_ uniforms: inout Uniforms){
    
    light += 0.02354
    if light > .pi*2 {light = 0}
    
    //if isOn{
        dist += 0.0141
        if dist > .pi*2 {dist = 0}
    
    //uniforms.lx = sin((uniforms.blend+Float(uniforms.last)+1) * .pi * (Float(uniforms.next)+1))
    uniforms.lx = 3*sin((uniforms.blend+1) * .pi)
    uniforms.ly = -uniforms.lx
    uniforms.lz = 0
    
    uniforms.k = 0.0001-uniforms.lx/3*5
    uniforms.r = 1 + uniforms.lx/3
    
    if uniforms.blend < 0.999 { uniforms.blend += 0.02}
    
    uniforms.z = 7
    
    uniforms.a = dist
    
}

let urls = [
    "https://raw.githubusercontent.com/nidorx/matcaps/master/1024/167E76_36D6D2_23B2AC_27C1BE.png",
    "https://raw.githubusercontent.com/nidorx/matcaps/master/1024/17395A_7EBCC7_4D8B9F_65A1B5.png",
    "https://raw.githubusercontent.com/nidorx/matcaps/master/1024/1C70C6_09294C_0F3F73_52B3F6.png",
    "https://raw.githubusercontent.com/nidorx/matcaps/master/1024/2E763A_78A0B7_B3D1CF_14F209.png",
    "https://raw.githubusercontent.com/nidorx/matcaps/master/1024/254FB0_99AFF0_6587D8_1D3279.png",
    "https://raw.githubusercontent.com/nidorx/matcaps/master/1024/27222B_677491_484F6A_5D657A.png",
    "https://raw.githubusercontent.com/nidorx/matcaps/master/1024/281813_604233_4B3426_442B22.png",
    "https://raw.githubusercontent.com/nidorx/matcaps/master/1024/293534_B2BFC5_738289_8A9AA7.png",
    "https://raw.githubusercontent.com/nidorx/matcaps/master/1024/293D21_ABC692_73B255_667C5C.png",
    "https://raw.githubusercontent.com/nidorx/matcaps/master/1024/2E2E2D_7D7C76_A3A39F_949C94.png",
    "https://raw.githubusercontent.com/nidorx/matcaps/master/1024/FBB82D_FBEDBF_FBDE7D_FB7E05.png",
    "https://raw.githubusercontent.com/nidorx/matcaps/master/1024/EA783E_6D4830_905837_FCDC6C.png"
].map { URL(string: $0)! }

var images: [UIImage] = []

class ImageLoader {
    
    private static func loadPublisher(url: URL) ->AnyCancellable{
        URLSession.shared.dataTaskPublisher(for: url)
            .map { UIImage(data: $0.data) }
            .sink(receiveCompletion:
                    { print($0) },
                  receiveValue: 
                    { images.append($0!) })
    }
    
    static func load() {
        
        let cancallables = urls.map{ ImageLoader.loadPublisher(url: $0)}
        
        while images.count<urls.count {}
    }
}

struct MetalView: UIViewRepresentable {
    
    init(_ uniforms: Binding<Uniforms>){
        _uniforms = uniforms
    }
    
    @Binding var uniforms: Uniforms
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    func makeUIView(context: UIViewRepresentableContext<MetalView>) -> MTKView {
        let mtkView = MTKView()
        mtkView.delegate = context.coordinator
        mtkView.preferredFramesPerSecond = 60
        mtkView.enableSetNeedsDisplay = true
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            mtkView.device = metalDevice
        }
        mtkView.framebufferOnly = false
        //mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        mtkView.drawableSize = mtkView.frame.size
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false
        
        return mtkView
    }
    func updateUIView(_ uiView: MTKView, context: UIViewRepresentableContext<MetalView>) {
    }
    class Coordinator: NSObject, MTKViewDelegate {
        
        var parent: MetalView
        
        var device: MTLDevice!
        var rayMarchPass: MTLComputePipelineState!
        var blendPass: MTLComputePipelineState!
        var commandQueue: MTLCommandQueue!
        
        var matcaps: [MTLTexture] = []
        var matcap: MTLTexture?
        
        init(_ parent: MetalView) {
            self.parent = parent
            if let metalDevice = MTLCreateSystemDefaultDevice() {
                self.device = metalDevice
            }
            self.commandQueue = device.makeCommandQueue()!
            
            var library: MTLLibrary!
            
            do{ library = try self.device?.makeLibrary(source: metalFunctions, options: nil)
            }catch{print(error)}
            
            let rayMarchFunc = library?.makeFunction(name: "ray_march")
            
            do{ rayMarchPass = try self.device?.makeComputePipelineState(function: rayMarchFunc!)
            }catch{print(error)}
            
            let blendFunc = library?.makeFunction(name: "blend")
            
            do{ blendPass = try self.device?.makeComputePipelineState(function: blendFunc!)
            }catch{print(error)}
            
            ImageLoader.load()
            
            let textureLoader = MTKTextureLoader(device: device)
            
            let options = [
                MTKTextureLoader.Option.textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue | MTLTextureUsage.shaderWrite.rawValue | MTLTextureUsage.renderTarget.rawValue),
                MTKTextureLoader.Option.SRGB: false
            ]
            
            matcaps = images.map{ try! textureLoader.newTexture(cgImage: $0.cgImage!, options: options) }
            images = []
            
            let colorPixelFormat = matcaps[0].pixelFormat
            let texDescriptor = MTLTextureDescriptor()
            texDescriptor.textureType = MTLTextureType.type2D
            texDescriptor.width = 1024
            texDescriptor.height = 1024
            texDescriptor.pixelFormat = colorPixelFormat
            texDescriptor.usage = [MTLTextureUsage.shaderWrite]
            
            matcap = try device?.makeTexture(descriptor: texDescriptor)
            
            super.init()
        }
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        }
    }
}

extension MetalView.Coordinator{
    
    func draw(in view: MTKView) {
        
        animationFunc(&parent.uniforms)
        
        guard let drawable = view.currentDrawable else { return }
        
        let commandbuffer = commandQueue.makeCommandBuffer()
        
        var w = blendPass.threadExecutionWidth
        var h = blendPass.maxTotalThreadsPerThreadgroup / w
        var threadsPerThreadGroup = MTLSize(width: w, height: h, depth: 1)
        var threadgroupsPerGrid = MTLSize(width: 1024 / w, height: 1024 / h, depth: 1)
        
        //Blend matcaps
        let computeCommandEncoderBlend = commandbuffer?.makeComputeCommandEncoder()
        
        var b = pow(parent.uniforms.blend, 5) 
        
        computeCommandEncoderBlend?.setComputePipelineState(blendPass)
        computeCommandEncoderBlend?.setTexture(matcaps[Int(parent.uniforms.last)], index: 0)
        computeCommandEncoderBlend?.setTexture(matcaps[Int(parent.uniforms.next)], index: 1)
        computeCommandEncoderBlend?.setTexture(matcap, index: 2)
        computeCommandEncoderBlend?.setBytes(&b, length: MemoryLayout<Float>.stride, index: 0)
        
        computeCommandEncoderBlend?.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadGroup)
        
        computeCommandEncoderBlend?.endEncoding()
 
        //Render
        let computeCommandEncoder = commandbuffer?.makeComputeCommandEncoder()
        
        computeCommandEncoder?.setComputePipelineState(rayMarchPass)
        computeCommandEncoder?.setTexture(drawable.texture, index: 0)
        computeCommandEncoder?.setTexture(matcap, index: 1)
        computeCommandEncoder?.setBytes(&parent.uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        
        w = rayMarchPass.threadExecutionWidth
        h = rayMarchPass.maxTotalThreadsPerThreadgroup / w
        
        threadsPerThreadGroup = MTLSize(width: w, height: h, depth: 1)
        
        threadgroupsPerGrid = MTLSize(width: drawable.texture.width / w, height: drawable.texture.height / h, depth: 1)
        
        computeCommandEncoder?.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadGroup)
        
        computeCommandEncoder?.endEncoding()
        commandbuffer?.present(drawable)
        commandbuffer?.commit()
    }
}

struct RMView: View {
    
    init(_ uniforms: Binding<Uniforms>){
        _uniforms = uniforms
    }
    
    @Binding var uniforms: Uniforms
    
    var body: some View{
        MetalView($uniforms)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .frame(width: 512, height: 512)
            .shadow(radius: 5)
            .onAppear(){
                
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.5){
                }
                light = 0
            }
            }
    }


struct ContentView:View {
    
    @State var uniforms = Uniforms()
    
    var body: some View{
        VStack{
            RMView($uniforms)
        }.onTapGesture {
            if uniforms.blend > 0.99{ 
                uniforms.last = uniforms.next
                uniforms.next += Int32(uniforms.next < urls.count-1 ? 1 : -urls.count + 1)
                uniforms.blend = 0
            }
        }
    }
}

PlaygroundPage.current.setLiveView(ContentView())
