import SwiftUI
import MetalKit
import MetalBuilder

class PointsCreator{
    internal init(pointsBuffer: MTLBufferContainer<Particle>) {
        self.pointsBuffer = pointsBuffer
    }
    
    enum PointState {
        case zero, first, second, third, fourthAndGreater
    }
    
    let pointsBuffer: MTLBufferContainer<Particle>
    let pointsSpacing: Float = 5
    
    private var pointState: PointState = .zero
    private var lastPointCoord: simd_float2 = [0,0]
    
    private var lastCoord: simd_float2 = [0,0]
    private var speed: Float = 0
    private var particleId = 0
    
    private var color: simd_float4{
        let c = UIColor(colors[breed]).cgColor.components!
        return simd_float4(c.map{ Float($0) })
    }
    private var breed = 0
    
    func point(_ dragging: Bool, _ coord: simd_float2,
               context: MetalBuilderRenderingContext,
               pointsCount: inout Int, breed: inout Int){
        if particleId>=particlesCount{ return }
        self.breed = breed
        if dragging{
            
            speed = speed*0.95 + length(coord-lastCoord)*0.05
            lastCoord = coord
            
            let thickness = speed
            
            switch pointState {
            case .zero:
                pointState = .first
            case .first:
                guard length(lastPointCoord-coord)>0
                else{
                    print("toClose", coord, lastPointCoord, pointState)
                    return
                }
                createPoint(particleId, lastPointCoord, thickness: thickness,
                            type: 0, context)
                createPoint(particleId+1, coord, thickness: thickness,
                            type: 3, context)
                pointState = .second
                particleId += 2
            case .second:
                guard length(lastPointCoord-coord)>pointsSpacing
                else{
                    print("toClose", coord, lastPointCoord, pointState)
                    return
                }
                createPoint(particleId, coord, thickness: thickness,
                            type: 2, context)
                pointState = .third
                particleId += 1
            case .third:
                guard length(lastPointCoord-coord)>pointsSpacing
                else{
                    print("toClose", coord, lastPointCoord, pointState)
                    return
                }
                createPoint(particleId, coord, thickness: thickness,
                            type: 0, context)
                //setType(id: particleId-1, type: 1)
                pointState = .fourthAndGreater
                particleId += 1
                pointsCount = particleId
            case .fourthAndGreater:
                guard length(lastPointCoord-coord)>pointsSpacing
                else{
                    print("toClose", coord, lastPointCoord, pointState)
                    return
                }
                createPoint(particleId, coord, thickness: thickness,
                            type: 0, context)
                setType(id: particleId-1, type: 2)
                setType(id: particleId-2, type: 1)
                pointState = .fourthAndGreater
                particleId += 1
                pointsCount = particleId
            }
            lastPointCoord = coord
        }else{
            switch pointState {
            case .zero:
                break
            case .first:
                break
            case .second:
                particleId -= 2
            case .third:
                particleId -= 3
            case .fourthAndGreater:
                breed = (breed+1)%colors.count
                break
            }
            speed = 0
            pointState = .zero
        }
    }
    func createPoint(_ id: Int, _ coord: simd_float2, thickness: Float,
                     type: Int,
                     _ context: MetalBuilderRenderingContext){
        let coord = context.scaleFactor*coord

        pointsBuffer.pointer![id].color = color
        pointsBuffer.pointer![id].breed = Float(breed)
        
        pointsBuffer.pointer![id].pos = coord
        pointsBuffer.pointer![id].type = UInt32(type)
        pointsBuffer.pointer![id].thickness = thickness
    }
    func setType(id: Int, type: Int){
        pointsBuffer.pointer![id].type = UInt32(type)
    }
}
