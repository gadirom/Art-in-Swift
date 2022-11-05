import SwiftUI
import MetalBuilder
import MetalKit
import MetalPerformanceShaders
import AVFoundation

let camTextureDesc = TextureDescriptor()

struct MaskFromCamera: MetalBuildingBlock {

    var context: MetalBuilderRenderingContext
    var helpers = ""
    var librarySource = ""
    var compileOptions: MetalBuilderCompileOptions? = nil
    
    let maskTexture: MTLTextureContainer
    let cameraTexture: MTLTextureContainer
    
    @MetalBinding var position: AVCaptureDevice.Position
    @MetalBinding var videoOrientation: AVCaptureVideoOrientation
    @MetalBinding var isVideoMirrored: Bool
    
    @MetalBinding var maskReady: Bool
    
    @MetalBinding var leftWristVisible: Bool
    @MetalBinding var leftWristPoint: CGPoint
    
    @MetalBinding var rightWristVisible: Bool
    @MetalBinding var rightWristPoint: CGPoint
    
    @MetalState var cameraReady = false
    @MetalState var bufferReady = false
    @MetalState var newTextureIsNeeded = true
    
    @MetalState var radius: Float = 0
    
    @MetalState var createTexture = true
    
    @State var invert = false
    
    @State var cache: CVMetalTextureCache?
    
    let bodyDetect = BodyDetect()
    
    @MetalState var maskPixelBuffer: CVPixelBuffer?
    @MetalState var ciContext: CIContext!
    
    //@MetalState var temp = false
    
    var metalContent: MetalContent {
                Camera(context: context,
                       texture: cameraTexture,
                       position: $position,
                       videoOrientation: $videoOrientation,
                       isVideoMirrored: $isVideoMirrored,
                       ready: $cameraReady){ pixelBuffer in
                    bodyDetect.analyze(with: pixelBuffer)
                }
                EncodeGroup(active: $cameraReady){
                    ManualEncode{device,commandBuffer,drawable in
//                        if ciContext == nil{
//                            ciContext =  CIContext(mtlDevice: device)
//                        }
                        
                        leftWristVisible = bodyDetect.leftWristVisible
                        leftWristPoint = bodyDetect.leftWristPoint
                        
                        rightWristVisible = bodyDetect.rightWristVisible
                        rightWristPoint = bodyDetect.rightWristPoint
                        
                        maskReady = true
                        if let maskPixelBuffer = bodyDetect.maskPixelBuffer{
                            self.maskPixelBuffer = maskPixelBuffer
                            bufferReady = true
                            
                            if newTextureIsNeeded{
                                let size = CGSize(width: CVPixelBufferGetWidth(maskPixelBuffer),
                                                  height: CVPixelBufferGetHeight(maskPixelBuffer))
                            
                                print("creating new texture for the mask: ", size)
                                
                                let tempTexture = MTLTextureContainer(camTextureDesc
                                                                    .usage([.shaderRead, .shaderWrite])
                                                                    .fixedSize(size))
                                try? tempTexture.create(device: device, drawable: drawable!)

                                if let texture = tempTexture.texture{
                                    self.maskTexture.texture = texture
                                    newTextureIsNeeded = false
                                }
                            }
//                            let maskImage = CIImage(cvPixelBuffer: maskPixelBuffer)
//                            self.ciContext.render(maskImage,
//                                                  to: maskTexture.texture!,
//                                                  commandBuffer: commandBuffer,
//                                                  bounds: maskImage.extent,
//                                                  colorSpace: CGColorSpaceCreateDeviceRGB())
                            
                        }
                    }
                    EncodeGroup(active: $bufferReady){
                        CVPixelBufferNonplanarToTexture(context: context,
                                                        buffer: $maskPixelBuffer,
                                                        texture: maskTexture,
                                                        pixelFormat: .r8Unorm,
                                                        createTexture: $createTexture)
//                        ScaleTexture(type: .fit, method: .lanczos)
//                            .source(cameraTexture)
//                            .destination(scaledCameraTexture)
//                        ScaleTexture(type: .fit, method: .lanczos)
//                            .source(maskTexture)
//                            .destination(texture)
//                        MPSUnary{
//                            MPSImageGaussianBlur(device: $0,
//                                                 sigma: 100)
//                        }
//                            .source(scaledMaskTexture)
//                            .destination(texture)
                    }
                }
            }

}
