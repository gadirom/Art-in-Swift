// Just copy and paste the code into a blank playground template
// in Swift Playgrounds app on an iPad or a Mac
// !!! Turn off Enable Results in the settings, otherwise you'll get an error !!!
// Created by Roman Gaditskiy: https://GitHub.com/gadirom/Art-in-Swift

import MetalKit
import SwiftUI
import PlaygroundSupport
import Combine

let refreshRate = 30
let refreshInterval = 1 / refreshRate
let timer = Timer.publish(every: TimeInterval(refreshInterval), tolerance: 0, on: .main, in: .default).autoconnect()
var startTime = Date()

struct Uniforms {
    //Sphere position
    var x: Float = 0
    var y: Float = 0
    var z: Float = 0
    
    //Light Position
    var lx: Float = 0
    var ly: Float = 0
    var lz: Float = 0
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

} Uniforms;

#define MAX_STEPS 100
#define MAX_DIST 100.0
#define SURF_DIST 0.01

 //distance for softmin:

#define K_Dist 0.5

float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5*(a-b)/k, 0.0, 1.0);
    return mix(a, b, h) - k*h*(1.0-h);
}

float sdSphere( float3 p, float3 c, float r ) {
    return length(p - c) - r;
}

float sdPlane( float3 p, float height ) {
    return p.y - height;
}

float getDist( float3 p, constant Uniforms *u ) {
    float sphere = sdSphere(p, float3(u->x, u->y, u->z), 1.0);
    float plane = sdPlane(p, -1.0);
    return smin(sphere, plane, K_Dist);
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

float getLight( float3 p, constant Uniforms *u ) {
  float3 lightPos = float3(u->lx, u->ly, u->lz);
  float3 l = normalize( lightPos - p );
  float3 n = getNormal(p, u);
  
  float diff = dot(l, n);
  
  float ls = castRay(p + n * (SURF_DIST*2.), l, u);
  float dl = length(lightPos - p);
  
  if (ls < dl) { diff *= .1;}
  
  return diff;
}

kernel void ray_march(texture2d<float, access::write> output [[texture(0)]],
                   constant Uniforms& uniforms [[buffer(0)]],
                   uint2 gid [[thread_position_in_grid]])

{
    constant Uniforms *u = &uniforms;

    int width = output.get_width();
    int height = output.get_height();
    float2 uv = (float2(width, height) * 0.5 - float2(gid) ) / height;
    
    float3 ro = float3(0.0, 0.0, 0.0);
    float3 rd = normalize (float3(uv, 1.0));
    
    float d = castRay(ro, rd, u);
    
    float3 p = ro + d * rd;
    float light = getLight(p, u);
    

    float3 col = float3(light);
   
    output.write(float4(col, 1.0), gid);
}

"""

struct MetalView: UIViewRepresentable {
    
    init(uniforms: Binding<Uniforms>){
        self._uniforms = uniforms
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
        var commandQueue: MTLCommandQueue!
        
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
            
            super.init()
        }
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        }
    }
}

extension MetalView.Coordinator{
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable else { return }
        
        let commandbuffer = commandQueue.makeCommandBuffer()
        let computeCommandEncoder = commandbuffer?.makeComputeCommandEncoder()
        
        computeCommandEncoder?.setComputePipelineState(rayMarchPass)
        computeCommandEncoder?.setTexture(drawable.texture, index: 0)
        computeCommandEncoder?.setBytes(&parent.uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        
        let w = rayMarchPass.threadExecutionWidth
        let h = rayMarchPass.maxTotalThreadsPerThreadgroup / w
        
        let threadsPerThreadGroup = MTLSize(width: w, height: h, depth: 1)
        
        let threadgroupsPerGrid = MTLSize(width: drawable.texture.width / w, height: drawable.texture.height / h, depth: 1)
        
        computeCommandEncoder?.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadGroup)
        
        computeCommandEncoder?.endEncoding()
        commandbuffer?.present(drawable)
        commandbuffer?.commit()
    }
}

struct rmToggle: View {
    
    init(isOn: Binding<Bool>){
        self._isOn = isOn
    }
    
    @Binding var isOn: Bool
    @State var tapped = false
    
    @State var uniforms = Uniforms()
    @State var scale = CGFloat()
    @State var animation = CGFloat()
    @State var newAnim = CGFloat()
    @State var light = CGFloat()
    
    func animationFunc(){
        let a = animation
        
        scale = tapped ? 1 + sin((.pi / 1000) * a) * 0.2 : 1
        
        uniforms.x = -7
        uniforms.y = Float(sin(a * .pi / 1500-1)*2) - 1
        uniforms.z = 6
        
        uniforms.lx = -8 + Float(cos(light)) * 2
        uniforms.ly = 2 + Float(cos(light)) * 2
        uniforms.lz = Float(sin(light)) * 3
    }
    
    var body: some View{
        MetalView(uniforms: $uniforms)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .frame(width: 256, height: 48)
            .shadow(radius: 5)
            .scaleEffect(scale)
            .onAppear(){
                scale = 1
                animation = 0
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.5){
                    newAnim = isOn ? 0 : 1000
                }
                light = 0
                animationFunc()
            }
            .onTapGesture(){
                newAnim = !isOn ? 0 : 1000
                tapped.toggle()
                
                DispatchQueue.global().asyncAfter(deadline: .now() + 1){
                    isOn.toggle(); tapped.toggle() }
            }
            .onReceive(timer) { time in
                animation += CGFloat(sign(Float(newAnim - animation)))
                animationFunc()
                light += 0.0005
                if light > .pi*2 {light = 0}
            }
    }
}

struct OptionsView:View {
    
    @State var options = [false, true, false, true, true]
    @State var show = Array(repeating: false, count: 5 + 2)
    
    var body: some View{
        ZStack{
            if show[0]{
                Color.gray
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .frame(width: 400, height: 500)
                    .shadow(radius: 10)
                    .transition(AnyTransition.scale.animation(.easeIn(duration: 0.3)))
            }
            if show[1]{
                Text("Ray Marching Options")
                    .font(.title) 
                    .fontWeight(.semibold)
                    .offset(y: -180)
                    .transition(AnyTransition.opacity.animation(.easeIn(duration: 0.5)))
            }
            ZStack{
                    ForEach(options.indices, id:\.self){ id in
                        if show[id+2]{ 
                            ZStack{
                            rmToggle(isOn: $options[id])
                                Text("Option \(id):")
                            .offset(x: -50, y: 0)
                            }.offset(y: CGFloat(id * 70 - 100))
                            .transition(AnyTransition.opacity.animation(Animation.easeIn(duration: 0.5)))
                        }
                    }
            }.onAppear(){
                    DispatchQueue.global().async {
                        for id in show.indices{
                            DispatchQueue.global().asyncAfter(deadline: .now() + Double(id)*0.1){
                                show[id].toggle() }
                        }
                    }
                }
            }
        }
    }


struct ContentView: View {
    
    @State var show = false
    
    var body: some View{
        ZStack{
            Color.white
            if show {
                OptionsView()
            }
        }.onAppear(){
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5){
                show.toggle()
            }
        }
    }
}

PlaygroundPage.current.setLiveView(ContentView())
