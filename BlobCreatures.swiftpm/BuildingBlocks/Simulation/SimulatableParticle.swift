import MetalBuilder
import MetalKit

protocol SimulatableParticle: ParticleWithRopes{
    var coord: simd_float2 { get }
    var prevCoord: simd_float2 { get }
    var size: Float { get }
    var moves: Bool { get }
}

protocol ParticleWithRopes{
    var connected: Bool { get }
    var p1: UInt32 { get }
    var p2: UInt32 { get }
    var angular: Bool { get }
    var blobID: UInt32 { get }
}
