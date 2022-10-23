import MetalKit
import AVFoundation
import SwiftUI
import Vision

public class BodyDetect{
    
    var poseRequest: VNDetectHumanBodyPoseRequest?
    var segmentationRequest: VNGeneratePersonSegmentationRequest?
    
    public var bodyPoints = [CGPoint]()
    public var ready = true
    
    public var leftWristVisible = false
    public var leftWristPoint = CGPoint()
    
    public var rightWristVisible = false
    public var rightWristPoint = CGPoint()
    
    public var maskPixelBuffer: CVPixelBuffer?
    
    let analysisQueue = DispatchQueue(label: "analysis", qos: .background)
    
    init(){
        poseRequest = VNDetectHumanBodyPoseRequest(completionHandler: bodyPoseHandler)
        segmentationRequest = VNGeneratePersonSegmentationRequest(completionHandler: segmentationHandler)
        segmentationRequest!.qualityLevel = .balanced
        segmentationRequest!.outputPixelFormat = kCVPixelFormatType_OneComponent8
    }
    
    public func analyze(with pixelBuffer: CVPixelBuffer){
        // Create a new image-request handler.
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)
        bodyPoints = []
        if ready == true{
            ready = false
        // Create a new request to recognize a human body pose.
            analysisQueue.async {
                do {
                    // Perform the body pose-detection request.
                    
                    try requestHandler.perform([self.segmentationRequest!,
                                                self.poseRequest!])
                } catch {
                    print("Unable to perform the request: \(error).")
                }
            }
        }
//        guard let maskPixelBuffer =
//                segmentationRequest?.results?.first?.pixelBuffer else { return }
//        self.maskPixelBuffer = maskPixelBuffer
        
    }
    private func segmentationHandler(request: VNRequest, error: Error?){
        guard let observations =
                request.results as? [VNPixelBufferObservation] else {
            return
        }
        
        guard let maskPixelBuffer =
                observations.first?.pixelBuffer else { return }
              self.maskPixelBuffer = maskPixelBuffer
        ready = true
    }
    private func bodyPoseHandler(request: VNRequest, error: Error?){
        guard let observations =
                request.results as? [VNHumanBodyPoseObservation] else {
            return
        }
        
        // Process each observation to find the recognized body pose points.
        observations.forEach { processObservation($0) }
      //  ready = true
    }
    private func processObservation(_ observation: VNHumanBodyPoseObservation){
        
        // Retrieve all torso points.
        guard let recognizedPoints =
                try? observation.recognizedPoints(.all) else { return }

        if let point = recognizedPoints[.leftWrist], point.confidence > 0.1{
            leftWristVisible = true
            leftWristPoint = point.location
        }else{
            leftWristVisible = false
        }
        if let point = recognizedPoints[.rightWrist], point.confidence > 0.1{
            rightWristVisible = true
            rightWristPoint = point.location
        }else{
            rightWristVisible = false
        }
    }
}
