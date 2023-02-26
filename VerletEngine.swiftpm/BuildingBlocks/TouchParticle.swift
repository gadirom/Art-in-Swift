
import MetalBuilder
import MetalKit

protocol TouchableParticle: MetalStruct{
    var coord: simd_float2 { get }
    var size: Float { get set }
}

// Building block for hit testing with a compute function
struct TouchParticle<T: TouchableParticle>: MetalBuildingBlock {
    
    var context: MetalBuilderRenderingContext
    var helpers = ""
    var librarySource = ""
    var compileOptions: MetalBuilderCompileOptions? = nil
    
    var particlesBuffer: MTLBufferContainer<T>
    
    @MetalBinding var touchCoord: simd_float2
    @MetalBinding var particlesCount: Int
    @MetalBinding var touchedId: Int
    @MetalBinding var isTouched: Bool
    
    @MetalBuffer<UInt32>(
        BufferDescriptor(count: 2, metalType: "atomic_uint", metalName: "counter")
    ) var counterBuffer
    
    var metalContent: MetalContent{
        Compute("hitTesting")
             .buffer(particlesBuffer, name: "particles", fitThreads: true)
             .buffer(counterBuffer, space: "device")
             .bytes($particlesCount, name: "count")
             .bytes($touchCoord, name: "touch")
             .source("""
             kernel void hitTesting(uint id [[thread_position_in_grid]]){
                 if(id>=count) return;
                auto p = particles[id];
                if(length(p.coord-touch)<p.size*.5){
                    atomic_store_explicit(&counter[0], id, memory_order_relaxed);
                    atomic_store_explicit(&counter[1], 1, memory_order_relaxed);
                    //touched[currentId] = id;
                }
             }
             """)
        CPUCompute{_ in
            if counterBuffer.pointer![1] == 1{
                print("touched!: ", counterBuffer.pointer![0])
                touchedId = Int(counterBuffer.pointer![0])
                isTouched = Int(counterBuffer.pointer![1]) == 1
                counterBuffer.pointer![0] = 0
                counterBuffer.pointer![1] = 0
            }
        }
    }
}
