import SwiftUI
import MetalBuilder
import MetalKit
import MetalPerformanceShaders
import TransformGesture

let particlesCount = 3010
let firstLightID = 3000
let maxBlobs = 100
let maxLights = particlesCount-firstLightID

struct Particle: RenderableParticle, SimulatableParticle, LightProtocol{
    var coord: simd_float2 = [0, 0]
    var prevCoord: simd_float2 = [0, 0]
    
    var size: Float = 0
    var color: simd_float3 = [0, 0, 0]
    
    var moves = false
    
    var connected = false
    var p1: UInt32 = 0
    var p2: UInt32 = 0
    var angular: Bool = false
    var blobID: UInt32  = 0
    
    var breed: Float = 0
    var cooldown: Float = 0
}

var uniformsDesc: UniformsDescriptor{
    var desc = UniformsDescriptor()
    LightRenderer<Particle>.addUniforms(&desc)
    Simulation<Particle>.addUniforms(&desc)
    return desc
        .float("size", range: 0...10, value: 2)
        .float("bright", range: 0...5, value: 2.7)
        .float("brpow", range: 0...5, value: 3.9)
        .float("ptBlb", range: 0...Float(particlesCount), value: 100)
}

//Canvas size
var canvasSize: simd_float2 = [200, 200]
//Canvas edge coords
var canvasD: simd_float2{
    canvasSize/2
}

var canvasTextureScaleFactor: Float = 5

let textureSize: CGSize = .init(width:  Int(canvasSize.x*canvasTextureScaleFactor),
                                height: Int(canvasSize.y*canvasTextureScaleFactor))

let texturePixelFormat: MTLPixelFormat = .rgba16Float

let blobTexturePixelFormat: MTLPixelFormat = .rgba16Float
let monoTexturePixelFormat: MTLPixelFormat = .r16Float

let textureDesc = TextureDescriptor()
    .fixedSize(textureSize)
    .pixelFormat(texturePixelFormat)

var polygonsPipColorDesc: MTLRenderPipelineColorAttachmentDescriptor{
    let desc = MTLRenderPipelineColorAttachmentDescriptor()
    desc.isBlendingEnabled = false
    desc.rgbBlendOperation = .add
    desc.alphaBlendOperation = .add
    desc.sourceRGBBlendFactor = .sourceAlpha
    desc.sourceAlphaBlendFactor = .one
    desc.destinationRGBBlendFactor = .one
    desc.destinationAlphaBlendFactor = .one
    desc.pixelFormat = blobTexturePixelFormat
    return desc
}

var blobPipColorDesc: MTLRenderPipelineColorAttachmentDescriptor{
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

struct ContentView: View {
    
    enum DrawMode: String, Equatable, CaseIterable  {
        case light, staticLight, areaBlob
        var localizedName: LocalizedStringKey { LocalizedStringKey(rawValue) }
    }
    
    @State var particleSpawner: ParticleSpawner!
    
    var viewSettings: MetalBuilderViewSettings{
        MetalBuilderViewSettings(
            framebufferOnly: false,
            preferredFramesPerSecond: 60)
    }
    
    @MetalState var particlesCountState = particlesCount
    @MetalState var canvasSizeState = canvasSize
    
    @StateObject var transform = TouchTransform(
        translation: CGSize(width: 0,
                            height:0),
        scale: 1,
        rotation: 0,
        scaleRange: 0.1...20,
        translationXSnapDistance: 10,
        translationYSnapDistance: 10,
        rotationSnapPeriod: .pi/4,
        rotationSnapDistance: .pi/60,
        scaleSnapDistance: 0.1
    )

    @State var drawMode: DrawMode = .light
    @State var transformActive = false
    
    @MetalBuffer<Particle>(count: particlesCount) var particlesBuffer
    @MetalBuffer<Particle>(count: particlesCount) var particlesBuffer1
    
    @MetalTexture(textureDesc
        .pixelFormat(blobTexturePixelFormat)) var blobTexture
    @MetalTexture(textureDesc
        .pixelFormat(monoTexturePixelFormat)) var monoTexture
    @MetalTexture(textureDesc
        .pixelFormat(monoTexturePixelFormat)) var sdfTexture
    
    @MetalUniforms(uniformsDesc) var uniforms
    
    @MetalState var toTextureTransform: simd_float3x3 = .identity
    //@MetalState var toDeviceTransform: simd_float3x3 = .identity
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack{
                Rectangle()
                    .fill(Color.black)
                    .frame(width: CGFloat(canvasSize.x), height: CGFloat(canvasSize.y))
                    .transformEffect(transform)
                MetalBuilderView(viewSettings: viewSettings) { context in
                    ManualEncode{_, _, _ in
                        toTextureTransform = simd_float3x3(diagonal: [2/canvasSize.x, -2/canvasSize.y, 1])
                    }//set texture transform
                    Simulation(context: context,
                               particlesBuffer: particlesBuffer,
                               particlesBuffer1: particlesBuffer1,
                               particlesCount: $particlesCountState,
                               uniforms: uniforms,
                               canvas: $canvasSizeState)
                    RenderPolygons(renderTexturePixelFormat: blobTexturePixelFormat,
                                   context: context,
                                   particlesBuffer: particlesBuffer,
                                   uniforms: uniforms,
                                   fragmentShader: FragmentShader("myPolygonFragment", returns: "float4",
                                                                  body:"""
                                                                 return float4(in.color, 0.);
                                                                 """),
                                   transform: $toTextureTransform,
                                   particlesCount: $particlesCountState,
                                   maxParticles: particlesCount,
                                   maxPolygons: maxBlobs)
                    .toTexture(blobTexture)
                    .pipelineColorAttachment(polygonsPipColorDesc)
                    .colorAttachement(
                        loadAction: .clear,
                        clearColor: .white
                    )
                    Compute("convertTexture")
                        .texture(blobTexture, argument: .init(type: "float", access: "read", name: "in"), fitThreads: true)
                        .texture(monoTexture, argument: .init(type: "float", access: "write", name: "out"))
                        .source("""
                            kernel void convertTexture(uint2 gid [[thread_position_in_grid]]){
                              //if(id>=count) return;
                              float4 c = in.read(gid).rgba;
                              float mono = 1.-c.a;//sign(length(c))*c.a;
                              out.write(float4(mono), gid);
                            }
                        """)
                    MPSUnary {
                        MPSImageEuclideanDistanceTransform(device: $0)
                    }
                    .source(monoTexture)
                    .destination(sdfTexture)
                    LightRenderer(context: context,
                                 particlesBuffer: particlesBuffer,
                                 sdfTexture: sdfTexture,
                                 colorTexture: blobTexture,
                                 transformMatrix: $transform.matrix,
                                 toTextureTransform: $toTextureTransform,
                                 center: MetalBinding<simd_float2>.constant([0,0]),
                                 size: MetalBinding<simd_float2>.constant(canvasD),
                                 uniforms: uniforms)
                    .pipelineColorAttachment(blobPipColorDesc)
                    .colorAttachement(
                        loadAction: .clear,
                        clearColor: .clear
                    )
                }
                .onStartup {
                    clearCanvas()
                }
                .transformGesture(transform: transform,
                                  active: true){ coord in
                    
                    //prepare transformed coordinates
                    var coords = transform
                        .matrixInveresed
                        .transformed2D(coord.simd_float2)
                    
                    let rx: ClosedRange<Float> = -canvasD.x...canvasD.x
                    let ry: ClosedRange<Float> = -canvasD.y...canvasD.y
                    
                    let coordInside = rx.contains(coords.x) &&
                    ry.contains(coords.y)
                    guard coordInside else {
                        return
                    }
                    let size = uniforms.getFloat("size")!
                    
                    switch drawMode {
                        
                    case .areaBlob:
                        createBlob(coords: coords,
                                   angular: true)
                        
                    case .light:
                        particleSpawner.drawSolid(coord: coords,
                                                  size: size)
                    case .staticLight:
                        particleSpawner.drawStatic(coord: coords,
                                                   size: size)
                    }
                        
                }
                if transform.isTransforming{
                    Rectangle()
                        .fill(Color.clear)
                        .border(Color.white, width: transform.scaleSnapped ? 2 : 1)
                        .frame(width: CGFloat(canvasSize.x), height: CGFloat(canvasSize.y))
                        .transformEffect(transform)
                    let offset = CGSize(width: transform.centerPoint.x,
                                        height: transform.centerPoint.y)
                    ZStack{
                        Rectangle()
                            .fill(Color.white)
                            .frame(height: 1)
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 1)
                    }
                    .frame(width: 20, height: 20)
                    .rotationEffect(Angle(radians: transform.rotation))
                    .offset(offset)
                    if transform.translationXSnapped{
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 0.5)
                    }
                    if transform.translationYSnapped{
                        Rectangle()
                            .fill(Color.white)
                            .frame(height: 0.5)
                    }
                }
            }
        }
            .background(Color.white)
            VStack{
                HStack{
                    Picker("", selection: $drawMode) {
                        ForEach(DrawMode.allCases, id: \.self) { value in
                            Text(value.localizedName)
                                .tag(value)
                        }
                    }.pickerStyle(.segmented)
                    Button {
                        clearCanvas()
                    } label: {
                        Text("clear")
                    }
                    Button {
                        transform.reset()
                    } label: {
                        Text("reset")
                    }

                }
                UniformsView(uniforms)
                    .frame(height: 120)
                /*Toggle("Dragging/Drawing Disabled:", isOn: $disableDragging)
                    .disabled(true)
                Toggle("Disable Transforming:", isOn: $disableTransform)*/
            }
            .padding()
            .background(Color.black)
        }
    
    func clearCanvas(){
        particleSpawner = ParticleSpawner(spawnParticle: spawnParticle,
                                          readParticle: readParticle,
                                          particlesCount: particlesCount)
        for id in 0..<particlesCount{
            spawnParticle(id, coord: [1000, 1000], size: 0,
                          moves: false, connected: false,
                          breed: 0, blobID: 0
            )
        }
    }
    func spawnParticle(_ id: Int, coord: simd_float2, size: Float? = nil,
                       moves: Bool = true,
                       connected: Bool = true, p1: Int = 0, p2: Int = 0, angular: Bool = false,
                       breed: Int, blobID: Int){
        //print(coord)
        let size = size ?? Float.random(in: 0.03...0.05)
        //let color = simd_float3.random(in: 0.1...1)
        var color: simd_float3 = connected ? [0.1,1,0.1] : simd_float3.random(in: 0...1)
        if angular{ color = [0,0,0] }
        let p = Particle(coord: coord,
                         prevCoord: coord + ((!connected && moves) ? [0, 2] : [0,0]),
                         size: size,
                         color: color,
                         moves: moves,
                         connected: connected,
                         p1: UInt32(p1),
                         p2: UInt32(p2),
                         angular: angular,
                         blobID: UInt32(blobID),
                         breed: Float(breed))
        particlesBuffer.pointer![id] = p
        particlesBuffer1.pointer![id] = p
    }
    func readParticle(_ id: Int)->Particle{
        particlesBuffer.pointer![id]
    }
    func createBlob(coords: simd_float2, angular: Bool){
        let numberOfRopePoints = Int(uniforms.getFloat("ptBlb")!)
        let blobR: Float = 20
        for j in 0..<numberOfRopePoints{
            let a = Float(j)*Float.pi*2/Float(numberOfRopePoints)
           
            let coord: simd_float2 = [sin(a), cos(a)]
            particleSpawner.drawRope(coord: coords+coord*blobR, size: 2,
                                     angular: angular)
        }
        particleSpawner.endDrawingBlob(angular: angular)
        if angular{ return }
        let numberOfInsidePointsInARow = 10
        let numberOfRows = 6
        for i in 0..<numberOfRows{
            for j in 0..<numberOfInsidePointsInARow{
                let a = Float(j)*Float.pi*2/Float(numberOfInsidePointsInARow)
                let r: Float = Float(i)/Float(numberOfRows)*blobR+0.1
                let coord: simd_float2 = [sin(a), cos(a)]
                particleSpawner.drawSolid(coord: coords+coord*r, size: 5)
            }
        }
    }
}
