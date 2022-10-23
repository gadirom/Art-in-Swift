import AVFoundation
import MetalBuilder

extension AudioEngine{
    func playNotes(notesBuffer: MTLBufferContainer<Note>,
                   notesCount: Int,
                   root: Int,
                   mode: String){
        let v = notesBuffer.pointer!
        
        for i in 0..<notesCount{
            
            if v[i].hit == 0 { continue }
            
            let note = (Int(abs(v[i].coord[0]-0.5) * 10 + 20).clamp(0, 107))
            let qNote = quantize(note: note, root: root, mode: mode)
            let vel = UInt8(Int(abs(v[i].coord[1]*50)).clamp(0, 127))
            //print(v[i].hit)
            //print(i, note, qNote, vel, v[i].instrument)
            if v[i].instrument > -1{
                synths[Int(v[i].instrument)]
                    .startNote(qNote,
                               withVelocity: vel,
                               onChannel: 0)
            }
            v[i].hit = 0
        }
    }
    func quantize(note: Int, root: Int, mode: String) -> UInt8{
        let intervs = modes[mode]!
        let modeLength = intervs.count
        let octave = note / modeLength
        let step = note % modeLength
        let qNote = (0..<step).reduce(0, { $0 + intervs[$1]})
        return UInt8((qNote+octave*12+root).clamp(0, 127))
    }
}

let modes = ["ionian" : [2, 2, 1, 2, 2, 2, 1],
             "pentatonic": [2, 2, 3, 2, 3],
             "western" : [2, 2, 1, 4, 3],
             "eastern" : [2, 3, 1, 2, 1, 1]]
let roots = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]


extension Int{
    func clamp(_ minI: Int, _ maxI: Int) -> Int{
        Swift.min(Swift.max(self, minI), maxI)
    }
}
