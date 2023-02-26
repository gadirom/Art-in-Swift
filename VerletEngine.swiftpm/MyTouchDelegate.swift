import SwiftUI
import TransformGesture

class MyTouchDelegate: TouchDelegate{
    
    func startTransform() {
        print("transform started")
    }
    func changeTransform(_ transform: TouchTransform) {
        print("transform changed")
    }
    func endTransform(_ transform: TouchTransform) {
        print("transform ended")
    }
    
    func touched(_ point: CGPoint) {
        print("view is touched")
    }
    
    func moveDragging(_ point: CGPoint) {
        print("dragging moved")
    }
    
    func endDragging() {
        print("dragging ended")
    }
    
    func tap(_ point: CGPoint) {
        print("tapped")
    }
}
