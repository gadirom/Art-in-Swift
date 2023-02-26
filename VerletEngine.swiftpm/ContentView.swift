import SwiftUI
import MetalBuilder
import MetalKit
import MetalPerformanceShaders
import TransformGesture

let particlesCount = 3000

struct Particle: TouchableParticle, RenderableParticle, SimulatableParticle{
    var coord: simd_float2 = [0, 0]
    var prevCoord: simd_float2 = [0, 0]
    var size: Float = 0
    var color: simd_float3 = [0, 0, 0]
    var moves = false
    var connected = false
    var p1: UInt32 = 0
    var p2: UInt32 = 0
}

var uniformsDesc: UniformsDescriptor{
    var desc = UniformsDescriptor()
    Simulation<Particle>.addUniforms(&desc)
    //DrawCircle.addUniforms(&desc)
    return desc
        .float("size", range: 0...5, value: 1.9)
        .float("bright", range: 0...5, value: 2.7)
        .float("brpow", range: 0...5, value: 3.9)
}

//Canvas size
var canvasSize: simd_float2 = [200, 200]
//Canvas edge coords
var canvasD: simd_float2{
    canvasSize/2
}

var canvasTextureScaleFactor: Float = 5

let textureDesc = TextureDescriptor()
    .fixedSize(.init(width:  Int(canvasSize.x*canvasTextureScaleFactor),
                     height: Int(canvasSize.y*canvasTextureScaleFactor)))
    .pixelFormat(.rgba16Float)

struct ContentView: View {
    
    enum DrawMode: String, Equatable, CaseIterable  {
        case glue, solid, rope, `static`, edit, blob
        var localizedName: LocalizedStringKey { LocalizedStringKey(rawValue) }
    }
    
    let touchDelegate = MyTouchDelegate()
    @State var particleSpawner: ParticleSpawner!
    
    var viewSettings: MetalBuilderViewSettings{
        MetalBuilderViewSettings(framebufferOnly: false,
                                 preferredFramesPerSecond: 60)
    }
    
    @MetalState var particlesCountState = particlesCount
    @MetalState var canvasSizeState = canvasSize
    
    @ObservedObject var transform = TouchTransform(
        translation: CGSize(width: 0,
                            height:0),
        scale: 1,
        rotation: 0,
        scaleRange: 0.1...20,
//        rotationRange: -CGFloat.pi...CGFloat.pi,
//        translationRangeX: -500...500,
//        translationRangeY: -500...500,
        translationXSnapDistance: 10,
        translationYSnapDistance: 10,
        rotationSnapPeriod: .pi/4,
        rotationSnapDistance: .pi/60,
        scaleSnapDistance: 0.1
    )

    @State var drawMode: DrawMode = .glue
    @State var transformActive = false
    
    @State var disableDragging = false
    @State var disableTransform = false
    
    @MetalState var justStarted = true
    
    @MetalState var dragging = false
    @MetalState var tapped: CGPoint? = nil
    @MetalState var drawCircle = false
    @MetalState var oneParticleIsTouched = false
    @MetalState var testTouch = false
    
    @MetalState var touchedParticleId = 0
    @MetalState var touchedParticleInitialCoords: simd_float2 = [0, 0]
    @MetalState var particleId = 0
    
    @MetalBuffer<Particle>(count: particlesCount) var particlesBuffer
    @MetalBuffer<Particle>(count: particlesCount) var particlesBuffer1
    @MetalTexture(textureDesc) var drawTexture
    
    @MetalState var coordTransformed: simd_float2 = [0, 0]
    @MetalState var drawingCircleSize: Float = 0
    @State var circleSize: CGFloat = 0
    
    @MetalUniforms(uniformsDesc) var uniforms
    
    @MetalState var gravity: simd_float2 = [0, 0]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack{
                Rectangle()
                    .fill(Color.gray)
                    .frame(width: CGFloat(canvasSize.x), height: CGFloat(canvasSize.y))
                    .transformEffect(transform)
                MetalBuilderView(viewSettings: viewSettings) { context in
                    EncodeGroup(active: $justStarted){
                        ClearRender()
                            .texture(drawTexture)
                            .color(MTLClearColor())
                    }
                    CPUCompute{ device in
                        if justStarted{
                            uniforms.setup(device: device)
                            particleSpawner = ParticleSpawner(spawnParticle: spawnParticle,
                                                              readParticle: readParticle,
                                                              particlesCount: particlesCount)
                            clearCanvas()
                            justStarted = false
                        }
                        
                        //compute gravity
                        let g: simd_float2 = [0, uniforms.getFloat("grav")!]
                        let a = -transform.floatRotation
                        gravity = [g.x*cos(a)-g.y*sin(a),
                                       g.x*sin(a)+g.y*cos(a)]
                        
                        var coord: simd_float2
                        //prepare to check if a particle is touched
                        if transform.isTouching &&
                            !transform.isDragging &&
                            !dragging &&
                            !transform.isTransforming &&
                            drawMode == .edit{
                            
                            testTouch = true
                            coord = transform.floatFirstTouch
                            
                            //print("firstTouch")
                        }else{
                            testTouch = false
                            coord = transform.floatCurrentTouch
                        }
                        
                        if let tapped = tapped{
                            coord = tapped.simd_float2
                        }
                        
                        //prepare transformed coordinates
                        coord = transform
                            .matrixInveresed
                            .transformed2D(coord)
                        
                        let rx: ClosedRange<Float> = -canvasD.x...canvasD.x
                        let ry: ClosedRange<Float> = -canvasD.y...canvasD.y
                        
                        let coordInside = rx.contains(coord.x) &&
                                          ry.contains(coord.y)
                        guard coordInside else {
                            return
                        }
                        coordTransformed = coord
                        
                        //draw
                        if !oneParticleIsTouched &&
                            (transform.isDragging || tapped != nil){
                            
                            let size = uniforms.getFloat("size")!
                            
                            switch drawMode {
                            case .glue:
                                drawingCircleSize = size * canvasTextureScaleFactor
                                drawCircle = true
                            case .solid:
                                particleSpawner.drawSolid(coord: coordTransformed,
                                                          size: size)
                            case .edit: break
                            case .rope:
                                particleSpawner.drawRope(coord: coordTransformed,
                                                         size: size)
                            case .static:
                                particleSpawner.drawStatic(coord: coordTransformed,
                                                           size: size)
                            case .blob:
                                break
                            }
                        }else{
                            drawCircle = false
                            particleSpawner.endDrawingRope()
                        }
                        
                        self.tapped = nil
                    }
                   EncodeGroup(active: $testTouch){
                        TouchParticle(context: context,
                                      particlesBuffer: particlesBuffer,
                                      touchCoord: $coordTransformed,
                                      particlesCount: $particlesCountState,
                                      touchedId: $touchedParticleId,
                                      isTouched: $oneParticleIsTouched)
                    }
                    CPUCompute{ _ in
                        
                        if !transform.isTouching || drawCircle{
                            oneParticleIsTouched = false
                            dragging = false
                            if drawMode == .edit{
                                disableDragging = true
                            }
                            return
                        }
                        if oneParticleIsTouched{
                            if drawMode == .edit{
                                disableDragging = false
                            }
                            circleSize = CGFloat(particlesBuffer.pointer![touchedParticleId].size)
                            if dragging{
                                particlesBuffer
                                    .pointer![touchedParticleId].coord =
                                transform
                                    .matrixInveresed
                                    .transformed2D(transform.floatCurrentTouch)
                            }else{
                                touchedParticleInitialCoords = particlesBuffer.pointer![touchedParticleId].coord
                                dragging = true
                                testTouch = false
                            }
                            
                        }else{
                            circleSize = CGFloat(uniforms.getFloat("size")!)
                        }
                    }
                    EncodeGroup(active: $drawCircle){
                        DrawCircle(context: context,
                                   texture: drawTexture,
                                   touchCoord: $coordTransformed,
                                   circleSize: $drawingCircleSize,
                                   canvasSize: $canvasSizeState)
                    }
                    Simulation(context: context,
                               particlesBuffer: particlesBuffer,
                               particlesBuffer1: particlesBuffer1,
                               particlesCount: $particlesCountState,
                               obstacleTexture: drawTexture,
                               uniforms: uniforms,
                               gravity: $gravity,
                               canvas: $canvasSizeState)
                    RenderParticles(context: context,
                                    particlesBuffer: particlesBuffer,
                                    uniforms: uniforms,
                                    transform: transform)
                    QuadRenderer(context: context,
                                 toTexture: nil,
                                 sampleTexture: drawTexture,
                                 transformMatrix: $transform.matrix)
                        
                }
                .transformGesture(transform: transform,
                                      draggingDisabled: disableDragging,
                                      transformDisabled: disableTransform,
                                      touchDelegate: touchDelegate,
                                      active: true){ coords in
                    if !oneParticleIsTouched && drawMode != .edit{
                        if drawMode == .blob{
                            createBlob(coords: transform.matrixInveresed.transformed2D(coords.simd_float2))
                        }else{
                            tapped = coords
                        }
                    }
                }
                if transform.isTouching && drawMode != .edit && !disableDragging{
                    Circle()
                        .stroke(transform.isDragging ? Color.white : Color.black)
                        .frame(width: transform.scale*circleSize)
                        .position(transform.firstTouch)
                        .offset(transform.offset)
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
            .hapticsEffects(transform)
            VStack{
                HStack{
                    Picker("", selection: $drawMode) {
                        ForEach(DrawMode.allCases, id: \.self) { value in
                            Text(value.localizedName)
                                .tag(value)
                        }
                    }.pickerStyle(.segmented)
                        .onChange(of: drawMode) { newValue in
                            if newValue != .edit{
                                disableDragging = false
                            }
                        }
                    Button {
                        clearCanvas()
                        justStarted = true
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
    }
    
    func clearCanvas(){
        for id in 0..<particlesCount{
            spawnParticle(id, coord: [1000, 1000], size: 0,
                          moves: false, connected: false
            )
        }
    }
    func spawnParticle(_ id: Int, coord: simd_float2, size: Float? = nil,
                       moves: Bool = true,
                       connected: Bool = true, p1: Int = 0, p2: Int = 0){
        //print(coord)
        let size = size ?? Float.random(in: 0.03...0.05)
        //let color = simd_float3.random(in: 0.1...1)
        let color: simd_float3 = connected ? [0.1,1,0.1] : (moves ? [0.1, 0.1, 1] : [0,0,0])
        let p = Particle(coord: coord,
                         prevCoord: coord,
                         size: size,
                         color: color,
                         moves: moves,
                         connected: connected,
                         p1: UInt32(p1),
                         p2: UInt32(p2))
        particlesBuffer.pointer![id] = p
        particlesBuffer1.pointer![id] = p
    }
    func readParticle(_ id: Int)->Particle{
        particlesBuffer.pointer![id]
    }
    
    func createBlob(coords: simd_float2){
        let numberOfRopePoints = 100
        let blobR: Float = 20
        for j in 0..<numberOfRopePoints{
            let a = Float(j)*Float.pi*2/Float(numberOfRopePoints)
           
            let coord: simd_float2 = [sin(a), cos(a)]
            particleSpawner.drawRope(coord: coords+coord*blobR, size: 1)
        }
        particleSpawner.endDrawingBlob()
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
