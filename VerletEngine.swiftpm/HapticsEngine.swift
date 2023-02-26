import CoreHaptics
import SwiftUI
import TransformGesture

struct HapticsEffects: ViewModifier {
    
    @ObservedObject var transform: TouchTransform
    
    @Environment(\.scenePhase) var scenePhase
    @State var hapticsEngine = HapticsEngine()
    
    func body(content: Content) -> some View {
        content
            .onChange(of: transform.offset) { newValue in
                hapticsEngine.onDraw()
            }
            .onChange(of: transform.translationXSnapped) { newValue in
                if newValue{
                    hapticsEngine.onSnap()
                }else{
                    hapticsEngine.offSnap()
                }
            }
            .onChange(of: transform.translationYSnapped) { newValue in
                if newValue{
                    hapticsEngine.onSnap()
                }else{
                    hapticsEngine.offSnap()
                }
            }
            .onChange(of: transform.rotationSnapped) { newValue in
                if newValue{
                    hapticsEngine.onSnap()
                }else{
                    hapticsEngine.offSnap()
                }
            }
            .onChange(of: transform.scaleSnapped) { newValue in
                if newValue{
                    hapticsEngine.onSnap()
                }else{
                    hapticsEngine.offSnap()
                }
            }
            .onChange(of: scenePhase) { newValue in
                if newValue == .active{
                    hapticsEngine.start()
                }
            }
    }
}

public extension View{
    func hapticsEffects(_ transform: TouchTransform) -> some View{
        self.modifier(HapticsEffects(transform: transform))
    }
}


class HapticsEngine{
    
    private var engine: CHHapticEngine?
    
    private var supported = false
    
    init(){
        start()
    }
    
    func start(){
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        
        do {
            engine = try CHHapticEngine()
            try engine?.start()
        } catch {
            print("There was an error creating the engine: \(error.localizedDescription)")
        }
        supported = true
    }
    func onSnap() {
        
        guard supported else { return }
        var events = [CHHapticEvent]()

        // create one intense, sharp tap
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5)
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 1)
        let event = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0)
        events.append(event)

        // convert those events into a pattern and play it immediately
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine?.makePlayer(with: pattern)
            try player?.start(atTime: 0)
        } catch {
            print("Failed to play pattern: \(error.localizedDescription).")
        }
    }
    func offSnap() {
        guard supported else { return }
        
        var events = [CHHapticEvent]()

        // create one intense, non-sharp tap
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5)
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.1)
        let event = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0)
        events.append(event)

        // convert those events into a pattern and play it immediately
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine?.makePlayer(with: pattern)
            try player?.start(atTime: 0)
        } catch {
            print("Failed to play pattern: \(error.localizedDescription).")
        }
    }
    func onDraw() {
        guard supported else { return }
        
        var events = [CHHapticEvent]()

        // create one soft tap
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.2)
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.1)
        let event = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0)
        events.append(event)

        // convert those events into a pattern and play it immediately
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine?.makePlayer(with: pattern)
            try player?.start(atTime: 0)
        } catch {
            print("Failed to play pattern: \(error.localizedDescription).")
        }
    }
}
