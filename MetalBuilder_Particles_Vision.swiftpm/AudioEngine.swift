import AVFoundation

class AudioEngine{
    let engine = AVAudioEngine()
    let synths = [AVAudioUnitSampler(),
                  AVAudioUnitSampler(),
                  AVAudioUnitSampler()]
    let reverb = AVAudioUnitReverb()
    let mixer = AVAudioMixerNode()
    
    init(){
        do{
            try synths[0].loadBank1()
            try synths[1].loadBank2()
            try synths[2].loadBank3()
            engine.attach(synths[0])
            engine.attach(synths[1])
            engine.attach(synths[2])
            engine.attach(mixer)
            //engine.attach(delay)
            engine.attach(reverb)
            reverb.wetDryMix = 50
            reverb.loadFactoryPreset(.cathedral)
            
//            synths[0].volume = 0
//            synths[2].volume = 0
            
            _ = (synths).enumerated().map{ id, synth in
                
                
                //let secondPoint = AVAudioConnectionPoint(node: mixer, bus: 0)
                
                // engine.connect(samplers[id], to: revbMixers[id], format: nil)
                let firstPoint = AVAudioConnectionPoint(node: mixer, bus: id)
                engine.connect(synth,
                               to: [firstPoint],
                               fromBus: 0,
                               format: nil)
            }
            
            engine.connect(mixer, to: reverb, format: nil)
            engine.connect(reverb, to: engine.mainMixerNode, format: nil)
            try engine.start()
        }catch{
            print(error)
        }
    }
}




