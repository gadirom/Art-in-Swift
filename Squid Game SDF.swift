// Just copy and paste the code into a blank playground template
// in Swift Playgrounds app on an iPad or a Mac
// !!! Turn off Enable Results in the settings, otherwise you'll get an error !!!
// Created by Roman Gaditskiy: https://GitHub.com/gadirom/Art-in-Swift

import MetalKit
import PlaygroundSupport
import UIKit

let vertexCount = 100000
let samplesCount = 4

var initialSpeed: Float = 0.0
let scatter: Float = 50;

let particleMaxSize: Float = 20

var i = 0

var tapped = false

struct Vertex{
    var position : float2 
    var velocity: float2
    var color : float4
    var size: Float
}

struct Uniforms {
    var aspect: Float = 1
    var t: Float = 0
    var k: Float = 0
    var id: Int32 = 0
    var friction: Float = 0.987
    var noise: Float = 0.0005
    var speed: Float = 15
    var power: Float = 0.001
    var radius: Float = 1
}
func animationFunc(uniforms: inout Uniforms){
    if tapped {uniforms.speed *= scatter; tapped = false}
    else {uniforms.speed = initialSpeed}
}

let metalFunctions = """
#include <metal_stdlib>
using namespace metal;

float3 hash1( float3 p )
{
    p = float3( dot(p,float3(127.1,311.7, 74.7)),
              dot(p,float3(269.5,183.3,246.1)),
              dot(p,float3(113.5,271.9,124.6)));

    return fract(sin(p)*43758.5453123) - 0.5;
}

float rand(int x, int y, int z)
{
    int seed = x + y * 57 + z * 241;
    seed= (seed<< 13) ^ seed;
    return (( 1.0 - ( (seed * (seed * seed * 15731 + 789221) + 1376312589) & 2147483647) / 1073741824.0f) + 1.0f) / 2.0f;
}

struct Vertex
{
    float2 position;
    float2 velocity;
    float4 color;
    float size;
};

struct Uniforms {
    float a;
    float t;
    float k;
    int id;
    float friction;
    float noise;
    float speed;
    float power;
    float radius;
};
// Vertex shader outputs and fragment shader inputs
struct VertexOut
{
    float4 position [[position]];
    float4 color; //[[flat]];
    float size [[point_size]];
};

float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5*(a-b)/k, 0.0, 1.0);
    return mix(a, b, h) - k*h*(1.0-h);
}

float sdCircle(float2 p, float r){
   return length(p) - r;
}

float sdPlane( float2 p, float height ) {
    return -p.y + height;
}
float sdTriangle(float2 p, float2 p0, float2 p1, float2 p2 )
{
    float2 e0 = p1 - p0;
    float2 e1 = p2 - p1;
    float2 e2 = p0 - p2;

    float2 v0 = p - p0;
    float2 v1 = p - p1;
    float2 v2 = p - p2;

    float2 pq0 = v0 - e0*clamp( dot(v0,e0)/dot(e0,e0), 0.0, 1.0 );
    float2 pq1 = v1 - e1*clamp( dot(v1,e1)/dot(e1,e1), 0.0, 1.0 );
    float2 pq2 = v2 - e2*clamp( dot(v2,e2)/dot(e2,e2), 0.0, 1.0 );
    
    float s = e0.x*e2.y - e0.y*e2.x;
    float2 d = min( min( float2( dot( pq0, pq0 ), s*(v0.x*e0.y-v0.y*e0.x) ),
                       float2( dot( pq1, pq1 ), s*(v1.x*e1.y-v1.y*e1.x) )),
                       float2( dot( pq2, pq2 ), s*(v2.x*e2.y-v2.y*e2.x) ));

    return -sqrt(d.x)*sign(d.y);
}

float opSmUn( float d1, float d2, float k ) {
    float h = clamp( 0.5 + 0.5*(d2-d1)/k, 0.0, 1.0 );
    return mix( d2, d1, h ) - k*h*(1.0-h); }

float opSmSub( float d1, float d2, float k ) {
    float h = clamp( 0.5 - 0.5*(d2+d1)/k, 0.0, 1.0 );
    return mix( d2, -d1, h ) + k*h*(1.0-h); }

float sdRoundBox( float2 p, float2 b, float4 r )
{
    r.xy = (p.x>0.0)?r.xy : r.zw;
    r.x  = (p.y>0.0)?r.x  : r.y;
    float2 q = abs(p)-b+r.x;
    return min(max(q.x,q.y),0.0) + length(max(q,0.0)) - r.x;
}

float sdBox( float2 p, float2 b )
{
    float2 d = abs(p)-b;
    return length(max(d,0.0)) + min(max(d.x,d.y),0.0);
}

float sdArc( float2 p, float2 sca, float2 scb, float ra, float rb )
{
    p *= float2x2(sca.x,sca.y,-sca.y,sca.x);
    p.x = abs(p.x);
    float k = (scb.y*p.x>scb.x*p.y) ? dot(p.xy,scb) : length(p);
    return sqrt( dot(p,p) + ra*ra - 2.0*ra*k ) - rb;
}

float sdUmbrella(float2 p){

float rad = .24;
float high = 0.67;

float4 rb = float4(rad, .0, rad, 0.);
float2 bb = float2(rad, 1.);

float lc = sdRoundBox(p - float2(1.-rad*.9, -high), bb, rb);
float rc = sdRoundBox(p - float2(-1.+rad*.9, -high), bb, rb);


float lc1 = sdRoundBox(p - float2(1.-rad*2.8, -high), bb, rb);
float rc1 = sdRoundBox(p - float2(-1.+rad*2.8, -high), bb, rb);

float box = sdBox(p - float2(0, -1.8+rad), float2(rad*8.,rad*4.));

float box1 = sdBox(p - float2(-6.5*rad, -5.3*rad), float2(rad*6.,rad*6.));
float box2 = sdBox(p - float2(6.5*rad, -5.3*rad), float2(rad*6.,rad*6.));

float pip = sdCircle(p - float2(0, 1.), .05);

float ta = 3.14*(1.5);
float tb = 3.14*(0.6);
float r = rad*0.37;
float2 pa = p - float2(rad, -.9+rad);
float arc = sdArc(pa, float2(sin(ta),cos(ta)), float2(sin(tb), cos(tb)), rad, r);

float d = sdCircle(p, 1.);

float k = 0.05;

d = opSmSub(lc, d, k);
d = opSmSub(rc, d, k);

d = opSmSub(lc1, d, k);
d = opSmSub(rc1, d, k);

d = opSmSub(box, d, k);
d = opSmSub(box1, d, k);
d = opSmSub(box2, d ,k);

d = opSmUn(pip, d, k);

d = opSmUn(arc, d, k);

return d;
}

float scene(float2 p, constant Uniforms *u, int id){
    p *= float2(u->a, 1);
    if (u->id == 0) {return sdCircle(p, 0.4);}
    if (u->id == 3) {return sdUmbrella(p*2);}
    if (u->id == 1) {return sdBox(p, 0.5);}
    if (u->id == 2) {float3 e = float3(1, -1, 0) *0.5;
            return sdTriangle(p, e.yy, e.zx, e.xy);}
}

float2 accel(float2 p, constant Uniforms *u, int id){
float d = scene(p, u, id);
float2 e = float2(0.0001, 0.);

float2 n = d - float2(scene(p - e.xy, u, id),
                       scene(p - e.yx, u, id));
n *= sign(d) * pow(abs(d), u->power);
return -n;
}

kernel void particleFunction(device Vertex *vertices [[ buffer(0) ]],
                             constant Uniforms *u [[ buffer(1) ]],
                           uint id [[ thread_position_in_grid ]]){
Vertex p = vertices[id];
float2 n = accel(p.position, u, id);
p.position += p.velocity;
p.velocity += n * u->speed;

p.velocity += hash1(float3(float(id), p.color.xy)).xy*u->noise;
p.velocity *= pow(u->friction, 1+float(u->id)*2);
p.color.g = pow(length(p.velocity ), 0.2);
vertices[id] = p;
}

vertex VertexOut
vertexShader(uint id [[vertex_id]],
             constant Vertex *vertices [[buffer(0)]],
             constant Uniforms *u [[buffer(1)]])
{
    VertexOut out;
    
    out.position = float4(vertices[id].position, 0.0, 1.0);
    out.color = vertices[id].color;
    out.size = vertices[id].size*float(4-u->id);

    return out;
}
fragment float4 fragmentShader(VertexOut in [[stage_in]],
                               float2 pointCoord [[point_coord]])
{ 
    if (length(pointCoord - 0.5) > 0.5) {
        discard_fragment();
    }
    float a = smoothstep(1, 0, length(pointCoord - 0.5)*2);
    return float4(in.color.xyz, a);
}
"""

class MetalView: MTKView{
    
    var commandQueue: MTLCommandQueue!
    var renderPipelineState: MTLRenderPipelineState!
    var vertexBuffer: MTLBuffer!
    var library: MTLLibrary!
    var computePiplineState: MTLComputePipelineState!
    
    var uniforms = Uniforms()
    var t: Float = 0
    
    @objc func didTapView(_ sender: UITapGestureRecognizer) {
        uniforms.id += uniforms.id==3 ? -3 : 1
        tapped = true
    }
    
    init(rect: CGRect, device: MTLDevice?){
        
        super.init(frame: rect, device: device)
        
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(didTapView(_:)))
        
        tapGestureRecognizer.numberOfTapsRequired = 1
        
        self.addGestureRecognizer(tapGestureRecognizer)
        
        isPaused = false
        
        delegate = self
        
        self.sampleCount = samplesCount
        
        commandQueue = self.device!.makeCommandQueue()!
        
        // loading compute Metal functions and creating a Compute Pipeline State
        var library : MTLLibrary!
        
        do{ library = try self.device?.makeLibrary(source: metalFunctions, options: nil)
        }catch{print(error)}
        
        let particleFunction = library?.makeFunction(name: "particleFunction")
        
        do{ computePiplineState = try self.device?.makeComputePipelineState(function: particleFunction!)
        }catch{print(error)}
        
        let vertexFunction = library?.makeFunction(name: "vertexShader")
        let fragmentFunction = library?.makeFunction(name: "fragmentShader")
        
        let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
        pipelineStateDescriptor.label = "Render Pipeline"
        pipelineStateDescriptor.vertexFunction = vertexFunction
        pipelineStateDescriptor.fragmentFunction = fragmentFunction
        pipelineStateDescriptor.sampleCount = samplesCount
        
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = colorPixelFormat
        //pipelineStateDescriptor.colorAttachments[0].isBlendingEnabled = true
        
        do{ renderPipelineState = try self.device?.makeRenderPipelineState(descriptor: pipelineStateDescriptor)
        }catch{print(error)}
        vertexBuffer = self.device!.makeBuffer(length: MemoryLayout<Vertex>.stride * vertexCount, options: [])!
        
        createVertices(vertexBuffer: vertexBuffer)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension MetalView: MTKViewDelegate{
    func draw(in view: MTKView) {
        
        animationFunc(uniforms: &uniforms)
        
        let onscreenCommandBuffer = commandQueue!.makeCommandBuffer()
        
        if let onscreenDescriptor = view.currentRenderPassDescriptor{
            
            let computeCommandEncoder = onscreenCommandBuffer?.makeComputeCommandEncoder()
            computeCommandEncoder?.setComputePipelineState(computePiplineState)
                
            computeCommandEncoder?.setBuffer(vertexBuffer, offset: 0, index: 0)
            computeCommandEncoder?.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            
            let w = computePiplineState.threadExecutionWidth
            let h = computePiplineState.maxTotalThreadsPerThreadgroup
                
            var threadsPerThreadGroup = MTLSize(width: w, height: 1, depth: 1)
            var threadgroupsPerGrid = MTLSize(width: vertexCount / w, height: 1, depth: 1)
            computeCommandEncoder?.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadGroup)
            computeCommandEncoder?.endEncoding()
                
            onscreenDescriptor.colorAttachments[0].storeAction = .multisampleResolve
            
            if let onscreenCommandEncoder = onscreenCommandBuffer?.makeRenderCommandEncoder(descriptor: onscreenDescriptor) {
            
                onscreenCommandEncoder.setRenderPipelineState(renderPipelineState)
                onscreenCommandEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
                onscreenCommandEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                
                onscreenCommandEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: vertexCount)
            
                onscreenCommandEncoder.endEncoding()
                if let currentDrawable = view.currentDrawable{
                    onscreenCommandBuffer?.present(currentDrawable)  
                    uniforms.aspect = Float(currentDrawable.texture.width)/Float(currentDrawable.texture.height)
                }
            }
        }
        onscreenCommandBuffer?.commit()
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        
    }
    func createVertices(vertexBuffer: MTLBuffer){
        var vertices = vertexBuffer.contents().bindMemory(to: Vertex.self, capacity: MemoryLayout<Vertex>.stride * vertexCount)
        DispatchQueue.concurrentPerform(iterations: vertexCount){ 
            let x = Float.random(in: -1..<1)
            let y = Float.random(in: -1..<1)
            let size = Float.random(in: 1..<particleMaxSize)
            
            let r = Float.random(in: 0...1)
            let g = Float(0)//Float.random(in: 0...1)
            let b = pow(Float.random(in: 0...1), 2)
            
            vertices[$0] = Vertex(position: simd_float2(x, y), 
                                  velocity: simd_float2(x*initialSpeed, y*initialSpeed),
                                  color: simd_float4(r, g, b, 1) ,
                                  size: size)
        }
        initialSpeed = uniforms.speed
    }
}


let rect = CGRect()
let device = MTLCreateSystemDefaultDevice()

PlaygroundPage.current.setLiveView(MetalView(rect: rect, device: device))
