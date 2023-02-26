//Created by Roman Gaditskii https://twitter.com/gadirom_
//2022(c)

import SwiftUI
import MetalBuilder
import MetalKit
import MetalPerformanceShaders
import AVFoundation

struct Particle: MetalStruct{
    var coord: simd_float4 = [0,0,0,0]
    var size: Float = 0
    var color: simd_float4 = [0,0,0,0]
    var force: simd_float2 = [0,0]
    var breed: Float = 0
    var cooldown: Float = 0
}

struct Note: MetalStruct{
    var hit: Float = 0
    var coord: simd_float4 = [0,0,0,0]
    var instrument: Float = 0
}
let uniforms = UniformsContainer(UniformsDescriptor()
    .float("gravity", range: -0.1...0.1, value: 0.0)
    .float("fric", value: 0.05)
    .float("threshold", range: 0...1, value: 0)
    .float("mask", range: 0...1, value: 0)
    .float("sigma", range: 0...50, value: 0)
    .float("brightness", range: 0...50, value: 1)
    .float("dim", range: 0...0.5, value: 0.01)
    .float("size", range: 0...10, value: 1)
    .float("pressure", range: 0...50, value: 25)
    .float("blob", value: 0, show: false)
    .float("simNotes", value: Float(simultaneousNotes), show: false)
    .float("dist", range: 0...1, value: 0.1)
    .float("cooldown", range: 0...1, value: 0.5),
                                 name: "u"
)

let particlesCount = 3000//increase if you have a powerful device!

let simultaneousNotes = 10

let texDesc = TextureDescriptor()
    .type(.type2D)
    .pixelFormatFromDrawable()
    //.pixelFormat(.rgba16Float)
    .usage([.renderTarget, .shaderRead, .shaderWrite])
    .sizeFromViewport(scaled: 1)

let maskTextureDesc = TextureDescriptor()
    .usage([.shaderRead, .shaderWrite])
    .pixelFormat(.r8Unorm)
    .fixedSize(CGSize(width: 384, height: 512))

let bufDescriptor = BufferDescriptor()
    .metalName("particles")
    .count(particlesCount)

struct ContentView: View {
    
    let audioEngine = AudioEngine()
    
    var viewSettings: MetalBuilderViewSettings{
        MetalBuilderViewSettings(framebufferOnly: false,
                                 preferredFramesPerSecond: 60)
    }
    
    @MetalTexture(texDesc
                  //.pixelFormat(.rgba16Float)
    ) var blurTexture
    @MetalTexture(texDesc) var targetTexture
    @MetalTexture(texDesc) var drawTexture
    
    @MetalTexture(maskTextureDesc) var maskTexture
    @MetalTexture(maskTextureDesc) var blurredMask
    @MetalTexture(texDesc) var cameraTexture
    
    @MetalBuffer<Particle>(bufDescriptor) var particlesBuffer
    @MetalBuffer<Particle>(bufDescriptor) var particlesBuffer1
    
    @State var isDrawing = false
    
    @MetalState var lastTime: Float = -1
    @MetalState var particleId = 0
    
    @MetalBuffer<UInt32>(
        BufferDescriptor(count: 1, metalType: "atomic_uint", metalName: "counter")
    ) var counterBuffer
    
    @MetalBuffer<Note>(BufferDescriptor(count: simultaneousNotes, metalName: "notes")) var notesBuffer
    
    let colors: [Color] = [.red, .yellow, .mint]
    @State var breed = 0
    @MetalState var color: simd_float4 = simd_float4([1, 0, 0, 1])
    
    @State var blob = false
    @State var play = false
    @State var fps: Float = 0
    @MetalState var cameraReady = false

    @MetalState var dragging = false
    @MetalState var touchPoint = CGPoint()
    @State var save = false
    @State var load = false
    @MetalState var data = Data()
    @MetalState var bufData = Data()
    
    @MetalState var cameraOrientation: AVCaptureVideoOrientation = .portrait
    @MetalState var cameraPosition: AVCaptureDevice.Position = .front
    @MetalState var cameraMirrored: Bool = true
    
    @MetalState var leftWristVisible = false
    @MetalState var leftWristPoint = CGPoint()
    
    @MetalState var rightWristVisible = false
    @MetalState var rightWristPoint = CGPoint()
    
    @State var settingsOpen = true
    
    var body: some View {
        VStack {
            HStack{
                Text("\(fps)")
                Spacer()
                Image(systemName: settingsOpen ? "gearshape" : "gearshape.fill")
                    .onTapGesture {
                        withAnimation{
                            settingsOpen.toggle()
                        }
                    }
            }.padding()
            ZStack{
            MetalBuilderView(librarySource: metalFunctions,
                             isDrawing: $isDrawing,
                             viewSettings: viewSettings) { context in
                ManualEncode{_, _, _ in
                    audioEngine.playNotes(notesBuffer: notesBuffer,
                                          notesCount: simultaneousNotes,
                                          root: 0,
                                          mode: "pentatonic")
                    counterBuffer.pointer![0] = 0
                    let lastTime = lastTime
                    let time = context.time
                    self.lastTime = time
                    fps = fps*0.99+0.01/(time-lastTime)
                    
                    if $dragging.wrappedValue{
                        print("Coord:Touch point:", touchPoint)
                        setBreed(2)
                        let size = simd_float2(context.viewportSize)
                        var coord: simd_float2 =
                        [Float(touchPoint.x)*context.scaleFactor*2,
                         Float(touchPoint.y)*context.scaleFactor*2]
                        coord /= size
                        coord -= 1
                        coord *= simd_float2(1, -1)
                        createParticle(coord: coord)
                                    //let coord = (context.scaleFactor*2*coord/simd_float2(size)-1)*simd_float2(1, -1)
                        //uniforms.setFloat(0.1, for: "fric")
                        //uniforms.setFloat(1, for: "size")
                    }
                    
                    if leftWristVisible{
                        print("Coord:left wrist:", leftWristPoint)
                        setBreed(0)
                        let coord: simd_float2 = [Float(rightWristPoint.x)*context.scaleFactor-1,
                           Float(rightWristPoint.y)*context.scaleFactor-1]
                        createParticle(coord: coord)
                        //uniforms.setFloat(Float(leftWristPoint.y), for: "fric")
                        //uniforms.setFloat(Float(leftWristPoint.x), for: "size")
                    }
                    if rightWristVisible{
                        print("Coord:right wrist:", rightWristPoint)
                        setBreed(1)
                        let coord: simd_float2 = [Float(leftWristPoint.x)*context.scaleFactor-1,
                           Float(leftWristPoint.y)*context.scaleFactor-1]
                        createParticle(coord: coord)
                        //uniforms.setFloat(Float(rightWristPoint.y)*10, for: "sigma")
                        //uniforms.setFloat(Float(rightWristPoint.x), for: "dim")
                    }
                }
//                Camera(context: context,
//                       texture: maskTexture,
//                       ready: $cameraReady){_ in}
                MaskFromCamera(context: context,
                               maskTexture: maskTexture,
                               cameraTexture: cameraTexture,
                               position: $cameraPosition,
                               videoOrientation: $cameraOrientation,
                               isVideoMirrored: $cameraMirrored,
                               maskReady: $cameraReady,
                leftWristVisible: $leftWristVisible,
                leftWristPoint: $leftWristPoint,
                rightWristVisible: $rightWristVisible,
                rightWristPoint: $rightWristPoint)
                MPSUnary { device in
                    MPSImageGaussianBlur(device: device, sigma: uniforms.getFloat("sigma")!)
                }
                .source(maskTexture)
                .destination(blurredMask)
                EncodeGroup(active: $play){
                    Compute("integration")
                        .texture(blurredMask, argument: .init(type: "float", access: "sample", name: "sdf"))
                        .buffer(particlesBuffer, space: "device", fitThreads: true)
                        .uniforms(uniforms)
                    EncodeGroup{
                        Compute("collision")
                            .buffer(particlesBuffer, name: "particlesIn", fitThreads: true)
                            .buffer(particlesBuffer1, space: "device", name: "particlesOut")
                            .uniforms(uniforms)
                            .buffer(counterBuffer, space: "device")
                            .buffer(notesBuffer, space: "device")
                        Compute("collision")
                            .buffer(particlesBuffer1, name: "particlesOut", fitThreads: true)
                            .buffer(particlesBuffer, space: "device", name: "particlesIn")
                            .uniforms(uniforms)
                            .buffer(counterBuffer, space: "device")
                            .buffer(notesBuffer, space: "device")
                    }//.repeating(2)
                Render(vertex: "vertexShader", fragment: "fragmentShader", type: .point, count: particlesCount)
                    .toTexture(blurTexture)
                    .vertexBuf(particlesBuffer)
                    .uniforms(uniforms)
                    .vertexBytes(context.$viewportSize)
                    .vertexTexture(maskTexture, argument: .init(type: "float", access: "sample", name: "sdf"))
                    
//                MPSUnary { device in
//                    MPSImageGaussianBlur(device: device, sigma: uniforms.getFloat("sigma")!)
//                }
//                .source(blurTexture)
                Compute("threshold")
                    .texture(blurTexture,
                             argument: .init(type: "float", access: "read", name: "blur"))
                    .texture(targetTexture,
                             argument: .init(type: "float", access: "read", name: "prev"))
                    .texture(drawTexture,
                             argument: .init(type: "float", access: "write", name: "out"))
                    //.texture(maskTexture,
                    //         argument: .init(type: "float", access: "read", name: "mask"))
                    .uniforms(uniforms)
                BlitTexture()
                    .source(drawTexture)
                    .destination(targetTexture)
                }
                EncodeGroup(active: $save){
                    CPUCompute{ device in
                        print("save")
                        data = targetTexture.getData(type: SIMD4<UInt8>.self)
                        //saveTexture(device: device)
                        bufData = particlesBuffer.getData()
                        save = false
                    }
                }
                EncodeGroup(active: $load){
                    CPUCompute{ device in
                        print("load")
                        targetTexture.load(data: data, type: SIMD4<UInt8>.self)
                        drawTexture.load(data: data, type: SIMD4<UInt8>.self)
                        //loadTexture(device: device)
                        particlesBuffer.load(data: bufData)
                        print("loaded")
                        load = false
                    }
                }
                BlitTexture()
                    .source(drawTexture)
            }.onResize { size in
                createParticles(particlesBuffer)
                isDrawing = true
            }
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged{ value in
                    touchPoint = value.location
                    //print(coord)
                    dragging = true
                }
                .onEnded{_ in
                    dragging = false
                })
            if settingsOpen{
                VStack{
            HStack{
                ForEach(colors.indices, id:\.self){breed in
                    ZStack{
                        Rectangle()
                            .fill(colors[breed])
                        Rectangle()
                            .opacity(breed == self.breed ? 0.5 : 0)
                    }.frame(width: 50, height: 30)
                    /*.onTapGesture {
                        self.breed = breed
                        if let c = UIColor(colors[breed]).cgColor.components{
                            color = simd_float4(c.map{ Float($0) })
                        }
                    }*/
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged{ value in
                            setBreed(breed)
                            dragging = true
                        }
                        .onEnded{_ in
                            dragging = false
                        })
                }
                ZStack{
                    Text("blob mode")
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(blob ? Color.white : Color.clear)
                }
                .frame(width: 100, height: 30)
                .onTapGesture {
                    blob.toggle()
                    uniforms.setFloat(blob ? 1:0, for: "blob")
                }
                ZStack{
                    Text("pause")
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(play==false ? Color.white : Color.clear)
                }
                .frame(width: 100, height: 30)
                .onTapGesture {
                    play.toggle()
                }
                Button("save") {
                    play = false
                    save = true
                }
                Button("load") {
                    play = false
                    load = true
                }
            }
            UniformsView(uniforms)
                    //.frame(height: 100)
                }//.opacity(0.5)
            }
            }
        }
    }
    func saveTexture(device: MTLDevice){
        //save
        let texture = drawTexture.texture!
        let region = MTLRegion(origin: MTLOrigin(),
                               size: MTLSize(width: texture.width,
                                             height: texture.height, depth: 1))
        
        let bytesPerRow = MemoryLayout<SIMD4<UInt8>>.size * texture.width
        let bytesPerImage = bytesPerRow*texture.height
        var texArray = [SIMD4<UInt8>](repeating: SIMD4<UInt8>(repeating: 0), count: bytesPerImage)
        texArray.withUnsafeMutableBytes{ bts in
            texture.getBytes(bts.baseAddress!,
                             bytesPerRow: bytesPerRow,
                             from: region,
                             mipmapLevel: 0)
        }
        data = Data(bytes: &texArray, count: bytesPerImage)
    }
    func loadTexture(device: MTLDevice){
        //load
        let texture = drawTexture.texture!
        let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                               size: MTLSize(width: texture.width,
                                             height: texture.height, depth: 1))
        let bytesPerRow = MemoryLayout<SIMD4<UInt8>>.size * texture.width
        data.withUnsafeBytes{ bts in
            drawTexture.texture!.replace(region: region, mipmapLevel: 0,
                                         withBytes: bts.baseAddress!, bytesPerRow: bytesPerRow)
        }
    }
    func saveBuffer(device: MTLDevice){
        let elementSize = MemoryLayout<Particle>.stride
        let length = elementSize*particlesCount
        bufData = Data(bytes: particlesBuffer.buffer!.contents(), count: length)
    }
    func loadBuffer(device: MTLDevice){
        let elementSize = MemoryLayout<Particle>.stride
        let length = elementSize*particlesCount
        bufData.withUnsafeBytes{ bts in
            particlesBuffer.buffer = device.makeBuffer(bytes: bts.baseAddress!, length: length)
            if let buffer = particlesBuffer.buffer{
                
                particlesBuffer.pointer = buffer.contents().bindMemory(to: Particle.self, capacity: length)
            }
        }
    }
    func createParticle(coord: simd_float2){
        for _ in 0..<Int(uniforms.getFloat("pressure")!){
            let velo = simd_float2.random(in: 0...0.01)
            particlesBuffer.pointer![$particleId.wrappedValue].coord = [coord.x, coord.y, coord.x-velo.x, coord.y-velo.y]
            particlesBuffer.pointer![$particleId.wrappedValue].size = Float.random(in: 0.05...0.05)
            particlesBuffer.pointer![$particleId.wrappedValue].color = color
            particlesBuffer.pointer![$particleId.wrappedValue].breed = Float(breed)
            particleId += 1
            if particleId >= particlesCount{particleId = 0}
        }
    }
    func setBreed(_ breed: Int){
        self.breed = breed
        setColor()
    }
    func setColor(){
        if let c = UIColor(colors[breed]).cgColor.components{
            color = simd_float4(c.map{ Float($0) })
        }
    }
}

func createParticles(_ buffer: MTLBufferContainer<Particle>){
    for idx in 0..<buffer.count!{
        let coord = simd_float2.random(in: -1...1)
        let velo = simd_float2.random(in: -0.00...0.00)
        let color = simd_float4([0.9, 0.9, 1, 1])*Float.random(in: 0.9...1)
        buffer.pointer![idx] = Particle(coord: [coord.x, coord.y,
                                                coord.x-velo.x,
                                                coord.y-velo.y],
                                        size: 0,
                                        color: color, force: [0, 0], breed: -1)// [0, color.y*0.2, color.z+0.5, 1])
    }
}

let metalFunctions = """

struct VertexOut{
    float4 position [[position]];
    float size [[point_size]];
    float4 color;
};

vertex VertexOut
vertexShader(uint id [[vertex_id]]){
  VertexOut out;
  Particle p = particles[id];
  out.position = float4(p.coord.xy, 0, 1);
  out.size = p.size*float(viewportSize.x)*0.1*u.size;

  constexpr sampler s(address::clamp_to_edge, filter::linear);
  float2 uv = p.coord.xy*float2(1,-1)*.5+.5;
  int breed = int(p.breed);
  float d = mix(1, sdf.sample(s, uv).r, u.mask);
  out.color = p.color*(0.01+length(p.coord.xy-p.coord.zw))*d*u.brightness+p.cooldown*10.;
  return out;
}
fragment float4 fragmentShader(VertexOut in [[stage_in]],
                               float2 p [[point_coord]]){
    if(length(p-.5)>0.5) discard_fragment();
    return in.color;
}
kernel void integration(uint id [[thread_position_in_grid]],
                      uint count [[threads_per_grid]]){
   if(id>=count) return;
   //Integration
   Particle p = particles[id];
   float2 velo = p.coord.xy-p.coord.zw;
   p.coord.zw = p.coord.xy;
   
   constexpr sampler s(address::clamp_to_edge, filter::linear);
   float2 e = float2(0.001, 0.);

   float2 uv = p.coord.xy*float2(1,-1)*.5+.5;
   int breed = int(p.breed);
   float d = sdf.sample(s, uv).r;
   float d1 = sdf.sample(s, uv-e.xy).r;
   float d2 = sdf.sample(s, uv-e.yx).r;
   float2 n = d - float2(d1, d2);
   n = length(n)==0 ? float2(0) : normalize(n);
   d = .5-d;
   n *= sign(d) * pow(abs(d), 1.);
   n = 0;
   //float2 sdfForce = n*(d);
   
   float2 force = n*u.gravity;//+p.force;//+sdfForce;

   velo += force/(1+velo*velo);
   //velo *= -1*(ceil(max(0., abs(p.coord.xy)-1.))*2-1);
   p.coord.xy += velo*0.9;

   //Edge constraint
   if (p.coord.x>1) p.coord.x=1;
   if (p.coord.x<-1) p.coord.x=-1;
   if (p.coord.y>1) p.coord.y=1;
   if (p.coord.y<-1) p.coord.y=-1;
   
   p.cooldown = p.cooldown <= 0. ? 0. : p.cooldown-.01;

   particles[id] = p;
}

kernel void collision(uint id [[thread_position_in_grid]],
                      uint count [[threads_per_grid]]){
   if(id>=count) return;
  Particle p = particlesIn[id];
  float2 fgrav = 0;
  //float2 frep = 0;
  for(uint id1=0; id1<count; id1++){
      if (id==id1) continue;
      Particle p1 = particlesIn[id1];
      float2 axis = p1.coord.xy - p.coord.xy;
      float dist = length(axis);
       if (dist == 0) continue;
      float size = p.size+p1.size;
      float2 n = axis/dist;
      if (u.blob==1){
      if (p.breed == p1.breed){
         fgrav += n/(dist*dist)*u.gravity*size;
      }else{
         fgrav -= n/(dist*dist)*u.gravity*size;
      }
      }else{
         fgrav += n/(dist*dist)*u.gravity*size;
      }
      if (dist<size){
          
        float shift = min(size-dist, 0.05);
        p.coord.xy -= (p.size/size)*shift*n*u.fric;
        //p1.coord.xy -= 0.5*shift*n;
        //particlesIn[id1] = p1;
      }
   }
   float2 dir = p.coord.xy - p.coord.zw;
   float dist = length(dir);
   if (dist>0){
      float2 n = dir/dist;
      dist = min(dist, 0.05);
          uint currentNote = atomic_fetch_add_explicit(&counter[0], 1, memory_order_relaxed);
          if(dist>u.dist*.1 && p.cooldown==0. && currentNote<=uint(u.simNotes)){
              p.cooldown = u.cooldown;
              Note note;
              note.hit = 1;
              note.coord = p.coord;
              note.instrument = p.breed;
              notes[currentNote]=note;
          }
      p.coord.xy = p.coord.zw + n*dist;
   }
   p.force = fgrav;
   particlesOut[id] = p;
}

kernel void threshold(uint2 gid [[thread_position_in_grid]]){
     float3 in = blur.read(gid).rgb;
     //float3 hue = normalize(in);
     //float light = smoothstep(u.threshold, u.threshold+0.05, length(in));
     float3 color = in;//pow(hue*light*(u.brightness), 1.);

     float3 prevCol = prev.read(gid).rgb-u.dim;
     color = max(color, prevCol);
     //float3 maskColor = mask.read(gid).rgb;
     //color = mix(color, maskColor, u.mask);
     out.write(float4(color, 1), gid);
     //out.write(float4(d*.001), gid);
}
"""
