import SwiftUI
import MetalBuilder
import MetalKit
import MetalPerformanceShaders

struct Particle: MetalStruct{
    var coord: simd_float4 = [0, 0, 0, 0]
    var size: Float = 0
    var color: simd_float4 = [0, 0, 0, 0]
    var breed: Float = 0
    var force: simd_float2 = [0, 0]
}

struct ColorID: MetalStruct{
    var id: Float = 0
}

struct ColorItem: Hashable{
    var id: Int
    var color: Color
}

let particlesCount = 2000

let colors: [Color] = [.red, .yellow, .green, .purple, .blue]
let colorsCount = colors.count

let desc = TextureDescriptor()
    .type(.type2D)
    .pixelFormatFromDrawable()
    .usage([.renderTarget, .shaderRead, .shaderWrite])
    .sizeFromViewport(scaled: 1)

struct ContentView: View {
    
    @MetalTexture(desc) var renderTexture
    @MetalTexture(desc
        .pixelFormat(.rgba16Float)) var blurTexture
    
    @MetalBuffer<Particle>(count: particlesCount, metalName: "particles") var particlesBuffer
    @MetalBuffer<Particle>(count: particlesCount) var particlesBuffer1
    @MetalBuffer<ColorID>(count: colorsCount) var breedIDs
    
    @State var frame = CGRect()
    
    @State var breed = 0
    @State var colorItem: ColorItem? = ColorItem(id: 0, color: .red)
    @State var colorItems: [ColorItem] = []
    
    @State var isDrawing = false
    @MetalState var particleId = 0
    
    @MetalState var dragging = false
    @MetalState var coord: simd_float2 = [0, 0]
    
    @State var threshold: Float = 0
    @State var sigma: Float = 10
    @State var brightness: Float = 1.6
    @State var fric: Float = 0.135
    @State var force: Float = 0.005
    @State var gravity: Float = 0.01
    @State var mul: Float = 1.5
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack{
                MetalBuilderView(librarySource: metalFunctions,
                                 isDrawing: $isDrawing) { context in
                    CPUCompute{_ in
                        if $dragging.wrappedValue{
                            let coord = (context.scaleFactor*2*coord/simd_float2(context.viewportSize)-1)*simd_float2(1, -1)
                            spawnParticle(coord: coord)
                        }
                    }
                    Compute("integration")
                        .buffer(particlesBuffer, space: "device",
                                fitThreads: true)
                        .bytes($fric, name: "fric")
                        .bytes($gravity, name: "gravity")
                    Compute("collision")
                        .buffer(particlesBuffer, space: "constant", name: "particlesIn",
                                fitThreads: true)
                        .buffer(particlesBuffer1, space: "device", name: "particlesOut")
                        .bytes($fric, name: "fric")
                        .bytes($force, name: "force")
                        .bytes($mul, name: "mul")
                        .buffer(breedIDs, space: "constant", name: "breedIDs")
                    BlitBuffer()
                        .source(particlesBuffer1)
                        .destination(particlesBuffer)
                    Render(vertex: "vertexShader", fragment: "fragmentShader", type: .point, count: particlesCount)
                        .vertexBuf(particlesBuffer)
                        .vertexBytes(context.$viewportSize)
                        .toTexture(renderTexture)
                    MPSUnary { device in
                        MPSImageGaussianBlur(device: device, sigma: sigma)
                    }
                    .source(renderTexture)
                    .destination(blurTexture)
                    Compute("threshold")
                        .texture(blurTexture, argument: .init(type: "float", access: "read", name: "blur"))
                        .bytes($threshold, name: "threshold")
                        .bytes($brightness, name: "brightness")
                        .drawableTexture(argument: .init(type: "float", access: "write", name: "out"))
                    
                }.onResize{ size in
                    if !isDrawing{
                        createIDs()
                        isDrawing = true
                    }
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
            .overlay(
                GeometryReader { geometry in
                    Color.clear
                        .preference(key: FramePreferenceKey.self,
                                    value: geometry.frame(in: .global))
                }
            )
            .onPreferenceChange(FramePreferenceKey.self){ value in
               // DispatchQueue.main.async {
                frame = value
              //  }
            }
            if(isDrawing){
                ColorGrid(colorItems: $colorItems, active: $colorItem, itemHeight: frame.height/CGFloat(colorsCount)){ _, _ in
                    for i in colorItems.indices{
                        breedIDs.pointer![colorItems[i].id].id = Float(i)
                    }
                }
                    .frame(width: 100)
            }
            }
            HStack{
                VStack(alignment: .leading, spacing: 18){
                    Text("Threshold: "+String(format:"%.3f", threshold))
                    Text("Blur: "+String(format:"%.2f", sigma))
                    Text("Brightness: "+String(format:"%.3f", brightness))
                    Text("Friction: "+String(format:"%.3f", fric))
                    Text("Force: "+String(format:"%.4f", force))
                    Text("Gravity: "+String(format:"%.4f", gravity))
                    Text("Mul: "+String(format:"%.3f", mul))
                }
                .font(.system(.body).monospacedDigit())
                .frame(width: 150, alignment: .leading)
                .padding()
                Spacer()
                VStack{
                    Slider(value: $threshold, in: 0...0.2)
                    Slider(value: $sigma, in: 0...50)
                    Slider(value: $brightness, in: 0...50)
                    Slider(value: $fric, in: 0...1)
                    Slider(value: $force, in: 0...0.1)
                    Slider(value: $gravity, in: 0...0.1)
                    Slider(value: $mul, in: 0...10)
                }
                .padding()
            }
        }
    }
    func createIDs(){
        for i in colors.indices{
            breedIDs.pointer![i].id = Float(i)
            colorItems.append(ColorItem(id: i, color: colors[i]))
        }
    }
    func spawnParticle(coord: simd_float2){
        let velo = simd_float2(repeating: -0.03)
        let size = Float.random(in: 0.04...0.05)
        let color = simd_float4(UIColor(colorItem!.color).cgColor.components!.map{ Float($0) })
        particlesBuffer.pointer![particleId] = Particle(coord: [coord.x, coord.y, coord.x-velo.x, coord.y-velo.y],
                                                        size: size,
                                                        color: color,
                                                        breed: Float(colorItem!.id))
        particleId = (particleId+1) % particlesCount
    }
}


struct FramePreferenceKey: PreferenceKey {
    static var defaultValue = CGRect()
    
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}
