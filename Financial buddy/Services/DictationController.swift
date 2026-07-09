//
//  DictationController.swift
//  Finance buddy
//
//  On-device dictation for the Ask tab: taps the mic, streams a live
//  transcript, and hands the final text back. Real implementation is
//  iOS-only (AVAudioSession); other platforms get an inert stub so
//  previews and the macOS destination still compile.
//
//  Requires Info.plist keys (build settings, user-added):
//    NSSpeechRecognitionUsageDescription
//    NSMicrophoneUsageDescription
//

import Foundation

#if os(iOS)
import Speech
import AVFoundation

@MainActor
@Observable
final class DictationController {
    var isRecording = false
    /// Live transcript while recording; final text when stopped.
    var transcript = ""
    var errorMessage: String?
    var isAvailable: Bool { SFSpeechRecognizer(locale: .current)?.isAvailable ?? false }

    @ObservationIgnored private var recognizer = SFSpeechRecognizer(locale: .current)
    @ObservationIgnored private let audioEngine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?

    /// Toggle recording. Returns the final transcript when stopping.
    func toggle() async -> String? {
        if isRecording {
            return stop()
        }
        await start()
        return nil
    }

    private func start() async {
        errorMessage = nil
        transcript = ""

        // Permissions: speech recognition + microphone.
        let speechStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard speechStatus == .authorized else {
            errorMessage = "Speech recognition isn't allowed. Enable it in Settings."
            return
        }
        let micGranted = await AVAudioApplication.requestRecordPermission()
        guard micGranted else {
            errorMessage = "Microphone access isn't allowed. Enable it in Settings."
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.request = request

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }

            task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                    }
                    if error != nil {
                        // Engine teardown also lands here; only surface while live.
                        if self.isRecording { self.stopEngine() }
                    }
                }
            }

            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
        } catch {
            errorMessage = "Couldn't start the microphone: \(error.localizedDescription)"
            stopEngine()
        }
    }

    /// Stops recording and returns whatever was transcribed.
    @discardableResult
    func stop() -> String? {
        stopEngine()
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private func stopEngine() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

#else

/// Inert stand-in for platforms without AVAudioSession (macOS previews).
@MainActor
@Observable
final class DictationController {
    var isRecording = false
    var transcript = ""
    var errorMessage: String?
    var isAvailable: Bool { false }

    func toggle() async -> String? { nil }
    @discardableResult
    func stop() -> String? { nil }
}

#endif
