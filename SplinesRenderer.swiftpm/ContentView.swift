import SwiftUI
import MetalBuilder
import MetalKit

struct Particle: MetalBuilderPointProtocol{
    var type: UInt32 = 0
    
    var pos: simd_float2 = [0,0]
    var thickness: Float = 0
    
    var color: simd_float4 = [0,0,0,0]
    var breed: Float = 0
}

let particlesCount = 3000
let maxSegments = 50

let bufDescriptor = BufferDescriptor()
    .metalName("particles")
    .count(particlesCount)

let colors: [Color] = [.indigo, .yellow, .mint, .brown, .pink]

struct ContentView: View {
    
    @MetalBuffer<Particle>(bufDescriptor) var particlesBuffer
    
    @MetalBuffer<MetalBuilderPoint>(count: 100, metalName: "curvedPoints") var curvedPointsBuffer
    
    @MetalUniforms(UniformsDescriptor()
        .float("speed", range: 0...100, value: 5)) var uniforms
    
    @State var breed = 0
    
    @MetalState var dragging = false
    
    @MetalState var coord: simd_float2 = [0, 0]
    
    @MetalState var pointsCount = 0
    
    @State var pointsCreator: PointsCreator!
    
    @State var shifting = false
    @State var glow = false
    
    var viewSettings: MetalBuilderViewSettings{
        MetalBuilderViewSettings(depthStencilPixelFormat: .depth32Float,
                                 clearDepth: 0,
                                 framebufferOnly: false,
                                 preferredFramesPerSecond: 120)
    }
    
    @MetalUniforms(MBSplinesRendererUniformsDescriptor
        .float("deform", range: 0...10)
        .float("deformFreq", range: 0...100)
                   , type: "Uni") var uni
    
    var fragment: FragmentShader{
        FragmentShader("metalBuilderSplinesRenderer_FragmentShader",
                                   source:
    """
    fragment
    float4 metalBuilderSplinesRenderer_FragmentShader(metalBuilderSplinesRenderer_VertexOut in [[stage_in]]){
        float edge = u.edge;
        
        float mask = 1.;
        
        mask = smoothstep(0, edge, in.uv.y);
        mask *= smoothstep(in.vLength, in.vLength-edge, in.uv.y);
        
        float2 chUV = float2(in.uv.x*u.uvScale.x/1000.,
                             in.uv.y/in.vLength*2.*u.uvScale.y);
        chUV.y += sin(chUV.x*u.deformFreq)*u.deform;
        float4 col = in.color;
        col.rgb *= mix(snoise(float3(chUV, time)).xyz, 1., 0.9);
        col = mix(1., col, mask);
        
        return col;
    }
    """)
        .bytes($time, name: "time")
    }
    
    @MetalState var performRestart = false
    @MetalState var clearRender = true
    @MetalState var drawing = true

    @MetalState var time: Float = 0
    
    func restart(){
        pointsCount = 0
        pointsCreator = PointsCreator(pointsBuffer: particlesBuffer)
        performRestart = true
        drawing = true
    }
    
    var body: some View {
        VStack {
            MetalBuilderView(helpers: simplexNoise1,
                             viewSettings: viewSettings) { context in
                ManualEncode{_,_,_ in
                    if glow{
                        context.resumeTime()
                    }else{
                        context.pauseTime()
                    }
                    time = context.time
                }
                EncodeGroup(active: $clearRender){
                    ClearRender()
                        .color(.white)
                }
                EncodeGroup(active: $drawing){
                    ManualEncode{device, commandBuffer, drawable in
                        if performRestart{
                            try! particlesBuffer.create(device: device)
                            performRestart = false
                        }
                        pointsCreator.point(dragging, coord,
                                            context: context,
                                            pointsCount: &pointsCount,
                                            breed: &breed)
                        if pointsCount>0 {
                            clearRender = false
                        }else{
                            clearRender = true
                        }
                    }
                }
                SplinesRenderer(context: context,
                              count: $pointsCount,
                              maxCount: particlesCount,
                              maxSegmentsCount: maxSegments,
                              pointsBuffer: particlesBuffer,
                              curvesPointsBuffer: curvedPointsBuffer,
                              uniforms: uni,
                              fragment: fragment)
                EncodeGroup(active: $shifting){
                    Compute("shiftStroke")
                        .buffer(particlesBuffer, space: "device", name: "points", fitThreads: true)
                        .buffer(curvedPointsBuffer)
                        .bytes($pointsCount, name: "count")
                        .uniforms(uni, name: "u")
                        .uniforms(uniforms, name: "uniforms")
                        .source("""
                        kernel void shiftStroke(uint id [[thread_position_in_grid]]){
                            if(id>=count) return;
                        
                            auto p = points[id];
                            
                            float2 step;
                            
                            if(id>0){
                                auto p0 = points[id-1];
                                //end control
                                if(p.type == 0 && p0.type == 2){
                                    step = (p.pos-p0.pos)/floor(u.segmentsCount);
                                }
                                //start
                                if(p.type == 3){
                                    step = (p0.pos-p.pos)/floor(u.segmentsCount);
                                }
                            }
                            //start control
                            if(id<count-1){
                                auto p1 = points[id+1];
                                if(p.type == 0 && p1.type == 3){
                                    step = (p.pos-p1.pos)/floor(u.segmentsCount);
                                }
                            }
                            
                            //middle or end
                            if(p.type==1||p.type==2){
                                uint sc = uint(u.segmentsCount);
                                uint cId = (id-1)*sc-1;
                                step = curvedPoints[cId].pos - p.pos;
                            }
                            step = normalize(step)*uniforms.speed;
                            p.pos += step;
                            points[id] = p;
                        }
                        """)
                }
            }.onResize { size in
                restart()
            }
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged{ value in
                    coord = [Float(value.location.x),
                             Float(value.location.y)]
                    dragging = true
                }
                .onEnded{_ in
                    dragging = false
                })
            ScrollView{
                HStack{
                    Button {
                        restart()
                    } label: {
                        Text("Clear!")
                            .font(.system(size: 50))
                    }
                    .padding()
                    Button {
                        glow.toggle()
                    } label: {
                        Text("Glow!")
                            .font(.system(size: 50))
                    }
                    .padding()
                    .overlay(
                        glow ?
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.white)
                        :
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.clear)
                    )
                    Button {
                        shifting.toggle()
                    } label: {
                        Text("GO!")
                            .font(.system(size: 50))
                    }
                    .padding()
                    .overlay(
                        shifting ?
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.white)
                        :
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.clear)
                    )
                }
                UniformsView(uni)
                UniformsView(uniforms)
            }.frame(height: 300)
        }
    }
}
