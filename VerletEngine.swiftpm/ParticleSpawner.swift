
import MetalKit
import MetalBuilder

class ParticleSpawner{
    public init(spawnParticle: @escaping (Int, simd_float2, Float?, Bool, Bool, Int, Int)->(),
                readParticle:  @escaping (Int)->(Particle),
                particlesCount: Int) {
        self.particlesCount = particlesCount
        self.spawnParticle = spawnParticle
        self.readParticle = readParticle
    }
    
    var id: Int = 0
    var p = Particle()
    var firstParticleOfRope = true
    var firstIdOfRope = -1
    
    let particlesCount: Int
    
    let spawnParticle: (Int, simd_float2, Float?, Bool, Bool, Int, Int)->()
    let readParticle: (Int)->(Particle)
        
    func drawSolid(coord: simd_float2, size: Float){
        spawnParticle(id, coord, size, true, false, 0, 0)
        increaseId()
    }
    func drawStatic(coord: simd_float2, size: Float){
        spawnParticle(id, coord, size, false, false, 0, 0)
        increaseId()
    }
    func drawRope(coord: simd_float2, size: Float){
        spawnParticle(id, coord, size, !firstParticleOfRope, true, max(id-1, 0), id+1)
        p = readParticle(id)
        if firstParticleOfRope{
            firstParticleOfRope = false
            firstIdOfRope = id
        }
        increaseId()
    }
    func endDrawingRope(){
        if firstParticleOfRope{ return }
        spawnParticle(id, p.coord, p.size, false, true, max(id-1, 0), id+1)
        increaseId()
        firstParticleOfRope = true
        firstIdOfRope = -1
    }
    func endDrawingBlob(){
        if firstParticleOfRope{ return }
        spawnParticle(id, p.coord, p.size, true, true, id-1, firstIdOfRope)
        let pFirst = readParticle(firstIdOfRope)
        spawnParticle(firstIdOfRope, pFirst.coord, pFirst.size, true, true, id, firstIdOfRope+1)
        increaseId()
        firstParticleOfRope = true
        firstIdOfRope = -1
    }
    func increaseId(){
        //prevId = id
        id = (id+1) % particlesCount
    }
}
