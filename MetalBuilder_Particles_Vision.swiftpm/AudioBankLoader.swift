import SwiftUI

import AVFoundation

extension AVAudioUnitSampler{
    func loadBank1() throws{
        let url = Bundle.main.url(forResource: "8bitsf", withExtension: "sf2")!
        try self.loadSoundBankInstrument(at: url,
                                         program: 0,
                                         bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                                         bankLSB: UInt8(kAUSampler_DefaultBankLSB))
        
    }
    func loadBank2() throws{
        let url = Bundle.main.url(forResource: "Xylophone-MediumMallets-20200706", withExtension: "sf2")!
        try self.loadSoundBankInstrument(at: url,
                                         program: 0,
                                         bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                                         bankLSB: UInt8(kAUSampler_DefaultBankLSB))
        
    }
    func loadBank3() throws{
        let url = Bundle.main.url(forResource: "flutey synth", withExtension: "sf2")!
        try self.loadSoundBankInstrument(at: url,
                                         program: 0,
                                         bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                                         bankLSB: UInt8(kAUSampler_DefaultBankLSB))
        
    }
}
