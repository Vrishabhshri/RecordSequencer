import SwiftUI
import AudioKit

class RecordSequencerClass: ObservableObject {
    
    let engine = AudioEngine()
    var instrument = AppleSampler()
    var sequencer = AppleSequencer()
    var midiCallback = MIDICallbackInstrument()
    @Published var playing : [Bool] = Array(repeating: false, count: 16)
    let notes = [36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51]
    init() {
        engine.output = instrument
        if let url = Bundle.main.url(forResource: "GuitarTaps", withExtension: "exs") {
            try? instrument.loadInstrument(url: url)
        } else {
            print("Error: Could not find the instrument file 'GuitarTaps.exs'")
        }
        try? engine.start()
        sequencer.newTrack("Track 1")
        sequencer.setLength(Duration(beats:4))
        sequencer.setGlobalMIDIOutput(midiCallback.midiIn)
        sequencer.enableLooping()
        sequencer.play()
        sequencer.tracks.first?.add(noteNumber: MIDINoteNumber(40), velocity: 127,
                                    position: Duration(beats: 0.25 * Double(0)), duration: Duration(beats: 0.25))
    }
    
}

struct RecordSequencer: View {
    @Environment(\.scenePhase) var scenePhase
    @StateObject var conductor = RecordSequencerClass()
    var body: some View {
        Text("Hey Folks")
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active {
                    if !conductor.engine.avEngine.isRunning {
                        try? conductor.instrument.loadInstrument(url:
                                                                    Bundle.main.url(forResource: "Sounds/GuitarTaps", withExtension: "exs")!)
                        try? conductor.engine.start()
                    }
                    
                } else if newPhase == .background {
                    conductor.sequencer.stop()
                    conductor.engine.stop()
                }
            }
            .onDisappear() {
                self.conductor.sequencer.stop()
                self.conductor.engine.stop()
            }.environmentObject(conductor)
    }
}

struct RecordSequencer_Previews: PreviewProvider {static var
    previews: some View {RecordSequencer()}}
