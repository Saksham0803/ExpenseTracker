//
//  SpeechRecognizer.swift
//  Expense Tracker
//
//  On-device dictation for transaction notes (tap-to-talk).
//

import Foundation
import Combine
import Speech
import AVFoundation

@MainActor
final class SpeechRecognizer: ObservableObject {
    @Published var transcript = ""
    @Published var isRecording = false
    /// Shown to the user when dictation can't start, instead of failing silently.
    @Published var errorMessage: String?

    private let recognizer = SFSpeechRecognizer()
    /// A fresh engine per recording — reusing one after a failed start leaves the
    /// audio unit half-configured and can deadlock CoreAudio.
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func toggle() {
        if isRecording {
            stop()
            return
        }
        #if targetEnvironment(simulator)
        // The Simulator's audio input can deadlock CoreAudio and abort the app;
        // dictation is supported on a real iPhone.
        errorMessage = "Voice notes need a real iPhone — the Simulator's microphone isn't supported."
        #else
        requestPermissionsThenStart()
        #endif
    }

    /// Ask for speech + microphone access on first use, then start dictating.
    private func requestPermissionsThenStart() {
        errorMessage = nil
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                guard status == .authorized else {
                    self.errorMessage = "Allow Speech Recognition in Settings to dictate notes."
                    return
                }
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    Task { @MainActor in
                        if granted {
                            self.start()
                        } else {
                            self.errorMessage = "Allow Microphone access in Settings to dictate notes."
                        }
                    }
                }
            }
        }
    }

    private func start() {
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Voice input isn't available right now."
            return
        }
        stop()
        transcript = ""

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Couldn't access the microphone."
            return
        }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            errorMessage = "No microphone input is available."
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            errorMessage = "Couldn't start recording."
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            return
        }

        audioEngine = engine
        self.request = request
        isRecording = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                Task { @MainActor in self.transcript = text }
            }
            if error != nil || (result?.isFinal ?? false) {
                Task { @MainActor in self.stop() }
            }
        }
    }

    func stop() {
        // Only touch the engine if a recording actually started.
        if let engine = audioEngine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        if isRecording {
            isRecording = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
