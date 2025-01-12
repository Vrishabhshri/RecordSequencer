import SwiftUI
import AudioKit
import AVFoundation

class RecordSequencerClass: ObservableObject {
    
    let engine = AudioEngine()
    var instrument = AppleSampler()
    var sequencer = AppleSequencer()
    var midiCallback = MIDICallbackInstrument()
    var recordingSession: AVAudioSession!
    var recorder: AVAudioRecorder!
    var recordedFileURL: URL!
    var numberOfRecords: Int = 0
    @Published var isRecording = false
    @Published var playing : [Bool] = Array(repeating: false, count: 16)
    @Published var rowIsActive: Int = -1
    @Published var tempo: Double = 120
    @Published var numberOfRows: Int = 1
    let notes = [60,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51]
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
        try? engine.start()
        
        setUpSequencer()
        setUpRecorder()
        
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
    func setUpRecorder() {
        recordingSession = AVAudioSession.sharedInstance()
        
        if let storedNumberOfRecords: Int = UserDefaults.standard.object(forKey: "numberOfRecords") as? Int{
            numberOfRecords = storedNumberOfRecords
        }
        
        AVAudioApplication.requestRecordPermission {
            hasPermission in
            if hasPermission {
                print("Accepted")
            }
        }
        
    }
    func setTempo(_ tempo: Double) {
        sequencer.setTempo(tempo)
        self.tempo = tempo
    }
    func addSixteenth(number: Double, note: Int, duration: Double) {
        sequencer.tracks.first?.add(noteNumber: MIDINoteNumber(note), velocity: 127, position: Duration(beats: 0.25 * number),
                                    duration: Duration(beats: duration))
        
//        print(playing)
//        print("addSixteenth")
    }
    func removeSixteenth(number: Double) {
        sequencer.clearRange(start: Duration(beats: 0.25 * number), duration: Duration(beats: 0.25))
//        print(playing)
//        print("removeSixteenth")
    }
    func addRow() {
        numberOfRows += 1
        playing += Array(repeating: false, count: 16)
//        print(playing.count)
//        print("addRow")
    }
    func removeRow() {
        guard numberOfRows > 1 else { return } // Ensure there's at least one row to remove
        
        for col in 0..<16 {
            removeSixteenth(number: Double(col))
        }
        
        numberOfRows -= 1
        
        for row in 0..<numberOfRows {
            for col in 0..<16 {
                if playing[col + row * 16] {
                    addSixteenth(number: Double(col % 16), note: notes[Int(col/16) + row], duration: 0.25)
                }
            }
        }
    }
    func getDirectory() -> URL {
        let documentURLS = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentDirectory = documentURLS[0]
        return documentDirectory
    }
    func startRecording() {
        let fileName = getDirectory().appendingPathComponent("\(numberOfRecords).m4a")
        let settings = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 41000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        do {
            recorder = try AVAudioRecorder(url: fileName, settings: settings)
            recorder?.record()
        }
        catch {
            print("Recording did not work sir")
        }
    }
    func stopRecording() {
        recorder?.stop()
        isRecording = false
        recorder = nil
        
        UserDefaults.standard.set(numberOfRecords, forKey: "numberOfRecords")
    }
    func loadRecordedAudio(url: URL) {
        do {
            try instrument.loadAudioFile(AVAudioFile(forReading: url))
        }
        catch {
            print("Failed to load recorded audio: \(error.localizedDescription)")
        }
    }
    
}

struct RecordSequencerPadView: Identifiable, View {
    @EnvironmentObject var conductor: RecordSequencerClass
    @GestureState var isPressed = false
//    @GestureState var dragOffset: CGFloat = 0
    var id: Int
    @State var isActive = false
    var body: some View {
        RoundedRectangle(cornerRadius: 2.0)
            .fill(conductor.playing[id] ? Color.blue: Color.blue.opacity(0.5))
            .aspectRatio(contentMode: .fit)
            .shadow(color: Color.red, radius: isActive ? 5 : 0, x: 0, y: 0)
//            .simultaneousGesture(DragGesture(minimumDistance: 10)
//                .updating($dragOffset) {
//                    (value, gestureState, transaction) in
//                    gestureState = value.translation.height
//                })
            .simultaneousGesture(DragGesture(minimumDistance: 0)
                .updating($isPressed) {
                    (value, gestureState, transaction) in

//                    if dragOffset == .zero {
                        gestureState = true
//                    }
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
    @State var isDragging: Bool = false
    @State var dragOffset: CGFloat = 0
    var body: some View {
        ZStack{
            
            RadialGradient(gradient: Gradient(colors: [.blue.opacity(0.5), .black]), center: .center, startRadius: 2, endRadius: 650).edgesIgnoringSafeArea(.all)
            VStack {
                
                HStack {
//                    Slider(value: $conductor.tempo, in: 30...240, step:1) {
//                        Text("Tempo")
//                    }
//                    .onChange(of: conductor.tempo) {newTempo in
//                        conductor.setTempo(newTempo)
//                    }
//                    .rotationEffect(.degrees(-90))
//                    .frame(width: 200)
                
                    Text("\(Int(conductor.tempo)) BPM")
                    .frame(width: 150)
                    .font(.largeTitle)
                    .padding()
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                isDragging = true
                                let delta = value.translation.height
                                let adjustment = -delta / 100 // Adjust sensitivity
                                conductor.tempo = max(30, min(240, conductor.tempo + adjustment)) // Clamp tempo between 30 and 240
                            }
                            .onEnded { _ in
                                isDragging = false
                            }
                    )
                    .foregroundColor(isDragging ? .yellow : .primary) // Highlight while dragging
                    .padding()
                    .onChange(of: conductor.tempo) {newTempo in
                        conductor.setTempo(newTempo)
                    }
//                    Text("Tempo: \(Int(conductor.tempo)) BPM").padding(.top)
                    
                    Button(action: {
    //                    conductor.isRecording.toggle()
                        if conductor.isRecording {
                            conductor.stopRecording()
                        }
                        else {
                            conductor.startRecording()
                        }
                    }) {
                        Text(conductor.isRecording ? "Stop Recording" : "Start Recording")
                            .foregroundColor(conductor.isRecording ? Color.blue : Color.red)
                            .padding()
                            .background(conductor.isRecording ? Color.red : Color.blue)
                            .cornerRadius(10)
                    }
                    .padding(.top)
                    
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
                }
                .padding(.top, 30)
                
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
