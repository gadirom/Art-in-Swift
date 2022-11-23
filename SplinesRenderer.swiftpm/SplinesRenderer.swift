
import SwiftUI
import MetalBuilder
import MetalKit

//enum MetalBuilderPointType: UInt32{
//    case inactive=0, active=1, last=2, first=3
//}

let MBSplinesRendererUniformsDescriptor = UniformsDescriptor()
    .float2("uvScale", range: 0...100, value: [0.1,0.1])
    .float("thickness", range: 0...10, value: 5)
    .float("edge", range: 0...50, value: 1)
    .float("alpha", range: 0...1, value: 1)
    .float("tension", range: 0...1, value: 0)
    .float("segmentsCount", range: 0...50, value: 20)

public protocol MetalBuilderPointProtocol: MetalStruct{
    var pos: simd_float2 { get }
    var color: simd_float4 { get }
    var thickness: Float { get }
    var type: UInt32 { get }
}

public struct MetalBuilderPoint: MetalBuilderPointProtocol{
    public init() {}
    
    public var pos: simd_float2 = [0,0]
    public var color: simd_float4 = [0,0,0,0]
    public var thickness: Float = 0
    public var type: UInt32 = 0
}

struct SplinesRendererVertex: MetalStruct{
    var pos: simd_float2 = [0,0]
    var uv: simd_float2 = [0,0]
    var vLength: Float = 0
    var color: simd_float4 = [0,0,0,0]
    var depth: Float = 0
}

/// This extension is for the initializer that doesn't take `curvesPointsBuffer`
public extension SplinesRenderer where S == MetalBuilderPoint{
     /// Use this init if you don't need the interpolated points
     init(context: MetalBuilderRenderingContext,
                count: MetalBinding<Int>,
                maxCount: Int,
                maxSegmentsCount: Int,
                pointsBuffer: MTLBufferContainer<T>,
                toTexture: MTLTextureContainer? = nil,
                uniforms: UniformsContainer,
                fragment: FragmentShader) {
        let curvesPointsBuffer = MTLBufferContainer<MetalBuilderPoint>(count: 100)
        self.init(context: context,
                  count: count,
                  maxCount: maxCount,
                  maxSegmentsCount: maxSegmentsCount,
                  pointsBuffer: pointsBuffer,
                  curvesPointsBuffer: curvesPointsBuffer,
                  toTexture: toTexture,
                  uniforms: uniforms,
                  fragment: fragment)
    }
}

/// The Metal Builder Building block that renders strokes i the form of interpolating splines.
/// The splines connect the points that you pass in `pointsBuffer`
/// with element type conforming to `MetalBuilderPointProtocol`.
/// The first and last point in each stroke should have type `0`.
/// They are used only as control points with no visible splines connected to them.
/// The second and penultimate points should have types `3` and `2` respectively .
/// All the middle points should be of type `1`.
public struct SplinesRenderer<T, S: MetalBuilderPointProtocol>: MetalBuildingBlock {
    public init(context: MetalBuilderRenderingContext,
                count: MetalBinding<Int>,
                maxCount: Int,
                maxSegmentsCount: Int,
                pointsBuffer: MTLBufferContainer<T>,
                curvesPointsBuffer: MTLBufferContainer<S>,
                toTexture: MTLTextureContainer? = nil,
                uniforms: UniformsContainer,
                fragment: FragmentShader) {
        self.context = context
        self._count = count
        self.maxCount = maxCount
        self.maxSegmentsCount = maxSegmentsCount
        self.pointsBuffer = pointsBuffer
        self.toTexture = toTexture
        self.uniforms = uniforms
        
        self.curvedPointsBuffer = curvesPointsBuffer
        self.fragment = fragment
    }
    
    public var context: MetalBuilderRenderingContext
    
    public var helpers = ""
    public var librarySource = ""
    public var compileOptions: MetalBuilderCompileOptions? = nil
    
    var fragment: FragmentShader
    
    @MetalBinding var count: Int
    
    var maxCount: Int
    var maxSegmentsCount: Int
    
    let pointsBuffer: MTLBufferContainer<T>
    
    let toTexture: MTLTextureContainer?
    
    @MetalState var indexCount: Int = 0
    
    let uniforms: UniformsContainer
    
    @MetalBuffer<SplinesRendererVertex>(count: 100, metalName: "vertexBuffer") var vertexBuffer
    @MetalBuffer<UInt32>(count: 100, metalName: "indexBuffer") var indexBuffer
    
    var curvedPointsBuffer: MTLBufferContainer<S>
    
    @MetalState(metalType: "float3x3", metalName: "viewportToDeviceTransform") var viewportToDeviceTransform = matrix_identity_float3x3
    
    @MetalBuffer<UInt32>(
        BufferDescriptor(count: 1, metalType: "atomic_uint", metalName: "counter")
    ) var pointsCounterBuffer
    
    @MetalState var bufferToCreate = true
    
    @MetalState var isComputingIndices = false
    @MetalState var isRendering = false

    @MetalState var curvedPointsCount = 0
    
    var depthDescriptor: MTLDepthStencilDescriptor{
        let dephDescriptor = MTLDepthStencilDescriptor()
        dephDescriptor.depthCompareFunction = .greater
        dephDescriptor.isDepthWriteEnabled = true
        return dephDescriptor
    }
    
    public var metalContent: MetalContent{
        EncodeGroup(active: $bufferToCreate){
            ManualEncode{ device,_,_ in
                
                try! vertexBuffer.create(device: device,
                                         count: (maxCount-2)*2*maxSegmentsCount)
                
                try! indexBuffer.create(device: device,
                                        count: (maxCount-2)*6*maxSegmentsCount)
                
                try! curvedPointsBuffer.create(device: device,
                                               count: (maxCount-2)*maxSegmentsCount)
                bufferToCreate = false
            }
        }
        //Create Indices
        ManualEncode{ _,_,_ in
            pointsCounterBuffer.pointer![0] = 0
            isComputingIndices = count>3
            curvedPointsCount = (count-2)*Int(uniforms.getFloat("segmentsCount")!)
            
            viewportToDeviceTransform = .init(columns: (
                [2/Float(context.viewportSize[0]), 0, -1],
                [0, -2/Float(context.viewportSize[1]), 1],
                [1,  1,  1]
            ))
        }
        EncodeGroup(active: $isComputingIndices){
            //Calculating and count vertex indices
            Compute("metalBuilderSplinesRenderer_IndexComputeKernel")
                .buffer(pointsBuffer, name: "points", fitThreads: true)
                .buffer(indexBuffer, space: "device")
                .buffer(pointsCounterBuffer, space: "device")
                .bytes($count, name: "count")
                .uniforms(uniforms, name: "u")
                .source("""
            kernel void metalBuilderSplinesRenderer_IndexComputeKernel(
                            uint gid [[ thread_position_in_grid ]]){
                if(gid>=count-1) return;
                if(points[gid].type==1||points[gid].type==3){
                   uint segmentsCount = uint(u.segmentsCount);
                   for(uint i=0;i<segmentsCount;i++){
                        uint iid = atomic_fetch_add_explicit(&counter[0], 1, memory_order_relaxed);
                        
                        uint id = (gid-1)*segmentsCount*2+i*2;
                        indexBuffer[iid*6+0] = id+2;
                        indexBuffer[iid*6+1] = id+1;
                        indexBuffer[iid*6+2] = id+0;
                        
                        indexBuffer[iid*6+3] = id+3;
                        indexBuffer[iid*6+4] = id+2;
                        indexBuffer[iid*6+5] = id+1;
                    }
                }
            }
            """)
            CPUCompute{_ in
                //Getting the overall index count from the atomic counter
                indexCount = Int(pointsCounterBuffer.pointer![0]*6)
                //Rendering is on if at least one segment is present
                //(two triangles = 6 indices)
                isRendering = indexCount >= 6
            }
            EncodeGroup(active: $isRendering){
                //Calculating Spline Segments
                Compute("metalBuilderSplinesRenderer_SegmentsComputeKernel")
                    .buffer(pointsBuffer, name: "points", fitThreads: true)
                    .buffer(curvedPointsBuffer, space: "device", name: "curvedPoints")
                    .uniforms(uniforms, name: "u")
                    .bytes($count, name: "count")
                    .source("""
                kernel void metalBuilderSplinesRenderer_SegmentsComputeKernel(
                                    uint gid [[ thread_position_in_grid ]]){
                
                    typedef remove_address_space_and_reference(curvedPoints) MB_LR_CurvedPoint;
                
                    if(gid>=count-2) return;
                    if(gid<1) return;
                    if(points[gid].type==0) return;
                
                    //Calculating the spline coeffs
                       float alpha = u.alpha;
                       float tension = u.tension;
                    
                       float2 p0 = points[gid-1].pos;
                       float2 p1 = points[gid].pos;
                       float2 p2 = points[gid+1].pos;
                       float2 p3 = points[gid+2].pos;
                        float t01 = pow(length(p0 - p1), alpha);
                        float t12 = pow(length(p1 - p2), alpha);
                        float t23 = pow(length(p2 - p3), alpha);

                        float2 m1 = (1.0f - tension) *
                            (p2 - p1 + t12 * ((p1 - p0) / t01 - (p2 - p0) / (t01 + t12)));
                        float2 m2 = (1.0f - tension) *
                            (p2 - p1 + t12 * ((p3 - p2) / t23 - (p3 - p1) / (t12 + t23)));

                        float2 a = 2.0f * (p1 - p2) + m1 + m2;
                        float2 b = -3.0f * (p1 - p2) - m1 - m1 - m2;
                        float2 c = m1;
                        float2 d = p1;
                
                        //Calculating spline segments
                        uint segmentsCount = uint(u.segmentsCount);
                
                        bool last = points[gid+1].type == 2;
                        if(last) segmentsCount += 1;
                        
                        float thickStep = (points[gid+1].thickness-points[gid].thickness);
                
                        for(uint i=0;i<segmentsCount;i++){
                
                            bool lastEnd = last&&i==segmentsCount-1;
                            float t = lastEnd ? 1 : float(i)/float(segmentsCount);
                
                            MB_LR_CurvedPoint po;

                            po.pos = a * t * t * t +
                                     b * t * t +
                                     c * t +
                                     d;
                            po.color = points[gid].color;
                            po.thickness = points[gid].thickness+t*thickStep;
                            po.type = 1;
                            if(lastEnd) po.type = 2;
                            if(points[gid].type==3&&i==0) po.type = 3;
                            curvedPoints[(gid-1)*uint(u.segmentsCount)+i] = po;
                        }
                }
                """)
                //Calculating the side vertices of the strokes
                Compute("metalBuilderSplinesRenderer_VertexComputeKernel")
                    .buffer(curvedPointsBuffer, name: "points", fitThreads: true)
                    .buffer(vertexBuffer, space: "device")
                    .bytes($curvedPointsCount, name: "count")
                    .uniforms(uniforms, name: "u")
                    .source("""
                kernel void metalBuilderSplinesRenderer_VertexComputeKernel(
                                    uint gid [[ thread_position_in_grid ]]){
                    if(gid>=count) return;
                    if(points[gid].type==0) return;
                
                    bool last = points[gid].type==2;
                    bool first = points[gid].type==3;
                    bool middle = !(first||last);
                
                    float2 p0 = points[gid].pos;

                    float2 p1 = middle ? points[gid-1].pos : p0;
                    float2 p2 = last ? points[gid-1].pos : points[gid+1].pos;
                    float2 p = middle ?
                   normalize(p0-p1)+normalize(p2-p0) :  p2-p1;
                        
                    float normalLength = length(p);
                
                    float cosA = dot(normalize(p0-p1), normalize(p2-p0));
                
                    float lengthCorrection = middle ?
                   sqrt(2.-cosA) : 1;

                    float len = points[gid].thickness*u.thickness;
                    float clampedLen = clamp(len, 0., 200.);// min max thickness

                    float mult = 1./normalLength*clampedLen*lengthCorrection;
                    float2 leftNormal = float2(-p.y, p.x) * mult;
                    float2 rightNormal = float2(p.y, -p.x) * mult;

                    SplinesRendererVertex vertex1;
                    SplinesRendererVertex vertex2;

                    float2 pos1 = p0 + (last ? -leftNormal : leftNormal);
                    float2 pos2 = p0 + (last ? -rightNormal : rightNormal);

                    vertex1.pos = pos1;
                    vertex2.pos = pos2;

                    float vLength = clampedLen*2;//length(pos1-pos2);
                    vertex1.vLength = vLength;
                    vertex2.vLength = vLength;

                    vertex1.uv = float2(float(gid), 0);
                    vertex2.uv = float2(float(gid), vLength);
                
                    float4 color = points[gid].color;
                
                    vertex1.color = color;
                    vertex2.color = color;
                
                    float depth = float(gid)/float(count);
                    vertex1.depth = depth;
                    vertex2.depth = depth;
                
                    vertexBuffer[gid*2] = vertex1;
                    vertexBuffer[gid*2+1] = vertex2;
                }
                """)
                //Rendering the mesh with indexed triangles
                Render(vertex: "metalBuilderSplinesRenderer_VertexShader",
                       type: .triangle,
                       indexBuffer: indexBuffer,
                       indexCount: $indexCount)
                    .vertexBuf(vertexBuffer)
                    .vertexBytes($viewportToDeviceTransform)
                    .uniforms(uniforms, name: "u")
                    .depthDescriptor(depthDescriptor)
                    .colorAttachement(
                        texture: toTexture,
                        loadAction: .clear,
                        clearColor: .white)
                    .vertexShader(VertexShader("metalBuilderSplinesRenderer_VertexShader", vertexOut: """
               struct metalBuilderSplinesRenderer_VertexOut{
                    float4 pos [[position]];
                    float2 uv;
                    float vLength;
                    float4 color;
               };
               """, body: """
                    SplinesRendererVertex v = vertexBuffer[vertex_id];
                    float3 pos3 = float3(v.pos, 1);
                    pos3 *= viewportToDeviceTransform;
                    
                    metalBuilderSplinesRenderer_VertexOut out;
                    out.pos = float4(pos3.xy, v.depth, 1);
                    out.color = v.color;
                    out.uv = v.uv;
                    out.vLength = v.vLength;
                    return out;
               """))
                    .fragmentShader(fragment)
            }
        }
    }
}
