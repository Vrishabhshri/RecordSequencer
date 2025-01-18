import SwiftUI
import AudioKit
import AVFoundation

class RecordSequencerClass: NSObject, ObservableObject, AVAudioPlayerDelegate {
    
    let engine = AudioEngine()
    var sampler = AppleSampler()
    var sequencer = AppleSequencer()
    var midiCallback = MIDICallbackInstrument()
    var recordingSession: AVAudioSession!
    var recorder: AVAudioRecorder!
    var recordedFileURL: URL!
    var audioPlayer: AVAudioPlayer!
    @Published var numberOfRecords: Int = 0
    @Published var audioFiles = ["Recording name 1", "Recording name 2"]
    @Published var isRecording = false
    @Published var isPlayingSample: Bool = false
    @Published var playing : [Bool] = Array(repeating: false, count: 16)
    @Published var playingNew: [[Bool]]
    @Published var rowIsActive: Int = -1
    @Published var tempo: Double = 120
    @Published var numberOfRows: Int = 1
    @Published var rowToAudioMapping: [Int: String] = [0: ""]
    let notes = [60,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51]
    
    // Testing stuff
    
    var avEngine = AVAudioEngine()
    var mixer: AVAudioMixerNode!
    var playerNodes: [AVAudioPlayerNode]
    var audioFilesURLs: [URL]
    var audioFilesList: [AVAudioFile]
    var timer: Timer?
    let beatsPerMeasure: Int
    let beatDuration: Double
    
    override init() {
        
        self.avEngine = AVAudioEngine()
        self.mixer = AVAudioMixerNode()
        self.playerNodes = []
        self.audioFilesURLs = []
        self.audioFilesList = []
        self.beatsPerMeasure = 16
        self.beatDuration = 0.125
        self.playingNew = []
        
        super.init()
        
        engine.output = sampler
        try? engine.start()
        
        setUpEngine()
        setUpSequencer()
        reloadAudioFiles()
        setUpRecorder()
        
    }
    func setUpEngine() {
        avEngine.attach(mixer)
        avEngine.connect(mixer, to: avEngine.mainMixerNode, format: nil)
        do {
            try avEngine.start()
        }
        catch {
            print("AVAudioEngine unable to start: \(error.localizedDescription)")
        }
    }
    func setUpSequencer() {
        sequencer.newTrack("Track 1")
        let loopLength = 4.0
        
        sequencer.setTempo(tempo)
        sequencer.setLength(Duration(beats: loopLength))
        sequencer.setLoopInfo(Duration(beats: loopLength), loopCount: 0)
        
        sequencer.enableLooping()
        sequencer.preroll()
    }
    func reloadAudioFiles() {
        do {
            let audioFilesInDirectory = try FileManager.default.contentsOfDirectory(atPath: getDirectory().path)
//            print(getDirectory().path)
//            print(audioFiles)
            
            numberOfRecords = audioFilesInDirectory.count
            audioFiles = audioFilesInDirectory.filter { $0.hasSuffix(".m4a") }
            audioFilesInDirectory.forEach {
                audioFileName in
                audioFilesURLs.append(getDirectory().appendingPathComponent(audioFileName))
            }
            
        }
        catch {
            print("Could not locate files in: \(getDirectory().path)")
        }
    }
    func setUpRecorder() {
        recordingSession = AVAudioSession.sharedInstance()
        
//        let audioDevices = AVAudioSession.sharedInstance().availableInputs
//        print("Available audio devices: \(audioDevices)")
        
        do {
            try recordingSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try recordingSession.setActive(true)
            try recordingSession.setPreferredSampleRate(44100) // Match sample rate
            try recordingSession.setPreferredInputNumberOfChannels(1) // Mono
            try recordingSession.setPreferredIOBufferDuration(0.005)
        } catch {
            print("Failed to configure AVAudioSession: \(error.localizedDescription)")
        }
        
    }
    func loadAudioFiles(fileURLs: [URL]) {
        for fileURL in fileURLs {
            do {
                print(fileURL)
                let audioFile = try AVAudioFile(forReading: fileURL)
                let playerNode = AVAudioPlayerNode()
                playerNodes.append(playerNode)
                audioFilesList.append(audioFile)
                avEngine.attach(playerNode)
                avEngine.connect(playerNode, to: mixer, format: audioFile.processingFormat)
            }
            catch {
                print("Error converting audioFileURL to AVAudioFile: \(error.localizedDescription)")
            }
        }
    }
    func startSequencer() {
        stopSequencer()
        
        var currentBeat = 0
        timer = Timer.scheduledTimer(withTimeInterval: beatDuration, repeats: true) {
            
            [weak self] _ in
            guard let self = self else { return }
            self.playBeat(currentBeat)
            currentBeat = (currentBeat + 1) % self.beatsPerMeasure
            
        }
        
    }
    func stopSequencer() {
        timer?.invalidate()
        timer = nil
        playerNodes.forEach { $0.stop() }
    }
    func playBeat(_ beat: Int) {
        
        for (row, isActive) in playingNew.enumerated() {
            
            if isActive[beat], row < playerNodes.count {
                
                let playerNode = playerNodes[row]
                let audioFile = audioFilesList[row]
                playerNode.stop()
                playerNode.scheduleFile(audioFile, at: nil) {
                    print ("Played row \(row) at beat \(beat)")
                }
                playerNode.play()
                
            }
            
        }
        
    }
    func setTempo(_ tempo: Double) {
        sequencer.setTempo(tempo)
        self.tempo = tempo
    }
    func addSixteenth(number: Double, note: Int, duration: Double) {
        
        // Need to be able to add sequencer tracks related to audio file and note midi notes
        
        sequencer.tracks.first?.add(noteNumber: MIDINoteNumber(60), velocity: 0, position: Duration(beats: 0.25 * number),
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
        guard numberOfRows > 1 else { return }
        
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
        print(fileName)
        let settings = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100, // Sample rate doesn't work for some reason
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        do {
            recorder = try AVAudioRecorder(url: fileName, settings: settings)
            if recorder.prepareToRecord() {
                recorder.record()
                isRecording = true
                print("Recording started.")
            } else {
                print("Failed to prepare for recording.")
            }
        }
        catch {
            print("Recording did not work sir")
        }
    }
    func stopRecording() {
        recorder?.stop()
        isRecording = false
        recorder = nil
        
        reloadAudioFiles()
    }
    func playAudioSample(file: String) {
        
        let filePath = getDirectory().appendingPathComponent(file)
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: filePath)
            audioPlayer.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            
            isPlayingSample = true
        }
        catch {
            print("Audio sample was not able to be playeds: \(error.localizedDescription)")
        }
        
    }
    func stopAudioSample() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlayingSample = false
    }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isPlayingSample = false
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
            .fill(conductor.playing[id] ? Color.blue: Color.black)
            .overlay(
                RoundedRectangle(cornerRadius: 2.0)
                    .stroke(isActive ? Color.blue : Color.blue, lineWidth: 5)
            )
            .aspectRatio(contentMode: .fit)
            .shadow(color: Color.blue, radius: isActive ? 10 : 0, x: 0, y: 0)
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
    @State var highlightedRow: Int = 0
    
    var body: some View {
        ZStack{
            
            RadialGradient(gradient: Gradient(colors: [.blue.opacity(0.8), .black]), center: .center, startRadius: 2, endRadius: 650).edgesIgnoringSafeArea(.all)
            VStack {
                
                Button(action: {
                    let fileURLs = conductor.audioFilesURLs
                    conductor.loadAudioFiles(fileURLs: fileURLs)
                    
                    print(conductor.audioFilesList)
                    
                    conductor.audioFilesList.forEach {
                        (file) in
                        conductor.playingNew.append(Array(repeating: false, count: 16))
                    }
                    
                    
                    conductor.playingNew[0][0] = true
                    conductor.playingNew[0][8] = true
                    
                    conductor.startSequencer()
                    
                }) {
                    Text("Try it out")
                }
                
                HStack {
                    VStack {
                        Text("Audio Recordings")

                        ScrollView {
                            List(conductor.audioFiles, id: \.self) { recording in
                                VStack {
                                    Text(recording)
                                    
                                    if conductor.rowToAudioMapping[highlightedRow] == recording {
                                        Text("Selected")
                                            .font(.caption)
                                            .foregroundColor(.green)
                                    }
                                }
                                .listRowBackground(Color.clear)
                                .onTapGesture {
                                    if recording == conductor.rowToAudioMapping[highlightedRow] {
                                        conductor.rowToAudioMapping[highlightedRow] = ""
                                    }
                                    else {
                                        conductor.rowToAudioMapping[highlightedRow] = recording
                                    }
                                }
                            }
                            .frame(minHeight: 200)
                            .frame(maxWidth: 250)
                            .background(Color.purple.opacity(0.1))
                            .scrollContentBackground(.hidden)
                            .cornerRadius(10)
                            .listStyle(.plain)
                        }

                        Button(action: {
                            if let selected = conductor.rowToAudioMapping[highlightedRow] {
                                conductor.isPlayingSample.toggle()
                                
                                if conductor.isPlayingSample {
                                    conductor.playAudioSample(file: selected)
                                }
                                else {
                                    conductor.stopAudioSample()
                                }
                                
                            }
                        }) {
                            Text(conductor.isPlayingSample ? "Stop" : "Play")
                                .foregroundColor(.white)
                                .padding()
                                .frame(maxWidth: 70)
                                .background(conductor.rowToAudioMapping[highlightedRow] != "" ? Color.green : Color.blue)
                                .cornerRadius(10)
                                .disabled(conductor.rowToAudioMapping[highlightedRow] == "")
                            
                        }
                    }
                
                    Text("\(Int(conductor.tempo)) BPM")
                    .frame(width: 150)
                    .font(.largeTitle)
                    .padding()
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                isDragging = true
                                let delta = value.translation.height
                                let adjustment = -delta / 100
                                conductor.tempo = max(30, min(240, conductor.tempo + adjustment))
                            }
                            .onEnded { _ in
                                isDragging = false
                            }
                    )
                    .foregroundColor(isDragging ? .yellow : .primary)
                    .padding()
                    .onChange(of: conductor.tempo) {newTempo in
                        conductor.setTempo(newTempo)
                    }
                    
                    Button(action: {
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
                                Button(action: {
                                    highlightedRow = row
                                }) {
                                    Circle()
                                        .fill(highlightedRow == row ? Color.blue.opacity(0.5) : Color.gray.opacity(0.5))
                                        .frame(width: 15, height: 15)
                                        .overlay(
                                            Circle().stroke(Color.blue, lineWidth: 2)
                                        )
                                        .shadow(color: highlightedRow == row ? Color.blue : Color.clear, radius: 5)
                                }
                                .padding(.leading, 5)
                                
                                ForEach(0..<16, id: \.self) { col in
                                    RecordSequencerPadView(id: col + (row * 16))
                                }
                            }
                            .padding(.top, 5)
                        }
                        HStack {
                            Button(action: {
                                conductor.rowToAudioMapping[conductor.numberOfRows] = ""
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
                                conductor.rowToAudioMapping.removeValue(forKey: conductor.numberOfRows)
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
