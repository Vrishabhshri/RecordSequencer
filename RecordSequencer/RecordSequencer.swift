import SwiftUI
import AudioKit

class RecordSequencerClass: ObservableObject {
    
    let engine = AudioEngine()
    var instrument = AppleSampler()
    var sequencer = AppleSequencer()
    var midiCallback = MIDICallbackInstrument()
    @Published var playing : [Bool] = Array(repeating: false, count: 16)
    @Published var rowIsActive: Int = -1
    @Published var tempo: Double = 120
    @Published var numberOfRows: Int = 1
    let notes = [100,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51]
    init() {
        midiCallback.callback = { status, note, velocity in
            if status == 144 {
                // Note on
                let beat = self.sequencer.currentRelativePosition.beats * 4
                self.rowIsActive = Int(beat)
                self.instrument.play(noteNumber: note, velocity: velocity, channel: 0)
            }
            else if status == 128 {
                // Note off
                self.instrument.stop(noteNumber: note, channel: 0)
                self.rowIsActive = -1
            }
        }
        engine.output = instrument
        if let url = Bundle.main.url(forResource: "GuitarTaps", withExtension: "exs") {
            try? instrument.loadInstrument(url: url)
        } else {
            print("Error: Could not find the instrument file 'GuitarTaps.exs'")
        }
        try? engine.start()
        
        setUpSequencer()
        
    }
    func setUpSequencer() {
        sequencer.newTrack("Track 1")
        let loopLength = 4.0
        
        sequencer.setLength(Duration(beats: loopLength))
        sequencer.setLoopInfo(Duration(beats: loopLength), loopCount: 0)
        sequencer.setGlobalMIDIOutput(midiCallback.midiIn)
        sequencer.enableLooping()
        sequencer.preroll()
        
    }
    func setTempo(_ tempo: Double) {
        sequencer.setTempo(tempo)
        self.tempo = tempo
    }
    func addSixteenth(number: Double, note: Int, duration: Double) {
        sequencer.tracks.first?.add(noteNumber: MIDINoteNumber(note), velocity: 127, position: Duration(beats: 0.25 * number),
                                    duration: Duration(beats: duration))
    }
    func removeSixteenth(number: Double) {
        sequencer.clearRange(start: Duration(beats: 0.25 * number), duration: Duration(beats: 0.25))
    }
    func addRow() {
        numberOfRows += 1
        playing += Array(repeating: false, count: 16)
    }
    func removeRow() {
//        guard numberOfRows > 1 else { return } // Ensure there's at least one row to remove
//        
//        // Remove notes for the row being deleted
//        for col in 0..<16 {
//            removeSixteenth(number: Double(col))
//            
//            for row in 0..<numberOfRows-1 {
//                let index = col + (row * 16)
//                
//                // Ensure the index is within bounds of the `playing` array
//                if index >= 0 && index < playing.count && playing[index] {
//                    addSixteenth(number: Double(col), note: notes[(row + (numberOfRows - 1)) % notes.count], duration: 0.25)
//                }
//            }
//        }
//        
//        numberOfRows -= 1
//        playing.removeLast(16)
    }
    
}

struct RecordSequencerPadView: Identifiable, View {
    @EnvironmentObject var conductor: RecordSequencerClass
    @GestureState private var isPressed = false
    var id: Int
    @State var isActive = false
    var body: some View {
        RoundedRectangle(cornerRadius: 2.0)
            .fill(conductor.playing[id] ? Color.blue: Color.blue.opacity(0.5))
            .aspectRatio(contentMode: .fit)
            .shadow(color: Color.red, radius: isActive ? 5 : 0, x: 0, y: 0)
            .gesture(DragGesture(minimumDistance: 0)
                .updating($isPressed) { (value, gestureState, transaction) in
                    gestureState = true
                })
            .onChange(of: isPressed, perform: {
                    pressed in
                    if pressed {
                        conductor.playing[id].toggle()
                        if conductor.playing[id] {
                            conductor.addSixteenth(number: Double(id % 16), note: conductor.notes[Int(id / 16)], duration: 0.25)
                        }
                        else {
                            conductor.removeSixteenth(number: Double(id % 16))
                            for row in -conductor.numberOfRows...conductor.numberOfRows {
                                if id + (row * 16) >= 0 && id + (row * 16) < conductor.playing.count &&
                                    conductor.playing[id + (row * 16)] {
                                    conductor.addSixteenth(number: Double(id % 16), note: conductor.notes[Int(id/16) + row], duration: 0.25)
                                    
                                }
                            }
                        }
                    }
                    else {
                        
                    }
                })
                .onChange(of: conductor.rowIsActive) { newValue in
                    isActive = (newValue == id % 16 && conductor.playing[id])
                }
    }
}

struct RecordSequencer: View {
    @Environment(\.scenePhase) var scenePhase
    @StateObject var conductor = RecordSequencerClass()
    @State var isPlaying: Bool = false
    var body: some View {
        ZStack{
            
            RadialGradient(gradient: Gradient(colors: [.blue.opacity(0.5), .black]), center: .center, startRadius: 2, endRadius: 650).edgesIgnoringSafeArea(.all)
            VStack {
                Text(isPlaying ? "Stop" : "Play")
                    .padding(.top)
                    .onTapGesture {
                        isPlaying.toggle()
                        if isPlaying {
                            conductor.sequencer.play()
                        }
                        else {
                            conductor.sequencer.stop()
                            conductor.sequencer.rewind()
                        }
                    }
                Slider(value: $conductor.tempo, in: 30...240, step:1) {
                    Text("Tempo")
                }
                .onChange(of: conductor.tempo) {newTempo in
                    conductor.setTempo(newTempo)
                }
                .padding()
                
                Text("Tempo: \(Int(conductor.tempo)) BPM").padding(.bottom)
                
                ScrollView {
                    VStack {
                        ForEach(0..<conductor.numberOfRows, id: \.self) { row in
                            HStack{
                                ForEach(0..<16, id: \.self) { col in
                                    RecordSequencerPadView(id: col + (row * 16))
                                }
                            }
                        }
                        HStack {
                            Button(action: {
                                conductor.addRow()
                            }) {
                                Text("Add Row")
                                    .foregroundColor(.green)
                                    .padding()
                                    .background(Color.blue)
                                    .cornerRadius(10)
                            }
                            .padding()
                            Button(action: {
                                conductor.removeRow()
                            }) {
                                Text("Remove Row")
                                    .foregroundColor(.green)
                                    .padding()
                                    .background(Color.blue)
                                    .cornerRadius(10)
                            }
                            .padding()
                        }
                    }
                }
            }
            
        }
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
            }
            .environmentObject(conductor)
    }
}

struct RecordSequencer_Previews: PreviewProvider {static var
    previews: some View {RecordSequencer().previewInterfaceOrientation(.landscapeRight)}}
