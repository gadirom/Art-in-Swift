
import MetalKit
import MetalBuilder

class ParticleSpawner{
    public init(spawnParticle: @escaping (Int, simd_float2, Float?, Bool, Bool, Int, Int, Bool, Int, Int)->(),
                readParticle:  @escaping (Int)->(Particle),
                particlesCount: Int) {
        self.particlesCount = particlesCount
        self.spawnParticle = spawnParticle
        self.readParticle = readParticle
    }
    
    var lightID = 0
    
    var id: Int = 0
    var blobID: Int = 0
    var p = Particle()
    var firstParticleOfRope = true
    var firstIdOfRope = -1
    
    let particlesCount: Int
    
    var b = 0
    
    let spawnParticle: (Int, simd_float2, Float?, Bool, Bool, Int, Int, Bool, Int, Int)->()
    let readParticle: (Int)->(Particle)
        
    func drawSolid(coord: simd_float2, size: Float){
        spawnParticle(lightID+firstLightID, coord, size, true, false, 0, 0, false, 0, 0)
        increaseLightId()
    }
    func drawStatic(coord: simd_float2, size: Float){
        spawnParticle(lightID+firstLightID, coord, size, false, false, 0, 0, false, 0, 0)
        increaseLightId()
    }
    func drawRope(coord: simd_float2, size: Float, angular: Bool){
        if firstParticleOfRope{
            b = Int.random(in: 0...2)
        }
        spawnParticle(id, coord, size, !firstParticleOfRope, true, max(id-1, 0), id+1, angular, b, blobID)
        p = readParticle(id)
        if firstParticleOfRope{
            firstParticleOfRope = false
            firstIdOfRope = id
        }
        increaseId()
    }
    func endDrawingRope(){
        if firstParticleOfRope{ return }
        spawnParticle(id, p.coord, p.size, false, true, max(id-1, 0), id+1, false, b, 0)
        increaseId()
        firstParticleOfRope = true
        firstIdOfRope = -1
    }
    func endDrawingBlob(angular: Bool){
        if firstParticleOfRope{ return }
        spawnParticle(id, p.coord, p.size, true, true, id-1, firstIdOfRope, angular, b, blobID)
        let pFirst = readParticle(firstIdOfRope)
        spawnParticle(firstIdOfRope, pFirst.coord, pFirst.size, true, true, id, firstIdOfRope+1, angular, b, blobID)
        increaseId()
        if angular{
            increaseBlobId()
        }
        firstParticleOfRope = true
        firstIdOfRope = -1
    }
    func increaseLightId(){
        //prevId = id
        lightID = (lightID+1) % maxLights
    }
    func increaseId(){
        //prevId = id
        id = (id+1) % particlesCount
    }
    func increaseBlobId(){
        //prevId = id
        blobID = (blobID+1) % maxBlobCount
    }
}
