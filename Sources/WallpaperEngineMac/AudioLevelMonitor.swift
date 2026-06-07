import AudioToolbox
import CoreMedia
import CoreGraphics
import Foundation
import QuartzCore
import ScreenCaptureKit

struct AudioResponsiveLevel {
    let value: Double
}

final class AudioLevelMonitor: NSObject {
    var onLevelChanged: ((AudioResponsiveLevel) -> Void)?
    var onError: ((Error) -> Void)?

    private let sampleQueue = DispatchQueue(label: "com.irnchk.WallpaperEngineMac.audio-level")
    private var stream: SCStream?
    private var isRunning = false
    private var lastEmitTime: CFTimeInterval = 0
    private var didReportPermissionError = false

    func start() {
        guard !isRunning else {
            return
        }

        guard checkScreenCapturePermission() else {
            report(AudioLevelMonitorError.screenCaptureDenied(appIdentity: appIdentity()))
            return
        }

        isRunning = true
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { [weak self] content, error in
            guard let self else {
                return
            }

            if let error {
                self.report(self.presentableError(from: error))
                self.isRunning = false
                return
            }

            guard let display = content?.displays.first else {
                self.report(AudioLevelMonitorError.noDisplay)
                self.isRunning = false
                return
            }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.width = 2
            configuration.height = 2
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 4)
            configuration.capturesAudio = true
            configuration.excludesCurrentProcessAudio = true

            let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
            do {
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: self.sampleQueue)
            } catch {
                self.report(error)
                self.isRunning = false
                return
            }

            self.stream = stream
            stream.startCapture { [weak self] error in
                guard let self else {
                    return
                }
                if let error {
                    self.report(self.presentableError(from: error))
                    self.isRunning = false
                    self.stream = nil
                }
            }
        }
    }

    func stop() {
        guard isRunning || stream != nil else {
            return
        }

        isRunning = false
        let stream = stream
        self.stream = nil
        stream?.stopCapture { [weak self] _ in
            DispatchQueue.main.async {
                self?.onLevelChanged?(AudioResponsiveLevel(value: 0))
            }
        }
    }

    private func report(_ error: Error) {
        if isPermissionError(error), didReportPermissionError {
            return
        }
        if isPermissionError(error) {
            didReportPermissionError = true
        }
        NSLog("[WallpaperEngineMac AudioResponsive] %@", error.localizedDescription)
        DispatchQueue.main.async { [weak self] in
            self?.onError?(error)
        }
    }

    private func checkScreenCapturePermission() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            didReportPermissionError = false
            return true
        }

        let granted = CGRequestScreenCaptureAccess()
        if granted {
            didReportPermissionError = false
        }
        return granted
    }

    private func presentableError(from error: Error) -> Error {
        if isScreenCaptureDenied(error) {
            return AudioLevelMonitorError.screenCaptureDenied(appIdentity: appIdentity())
        }
        if isSystemAudioCaptureFailure(error) {
            return AudioLevelMonitorError.systemAudioCaptureFailed(appIdentity: appIdentity(), underlying: error)
        }
        return error
    }

    private func isPermissionError(_ error: Error) -> Bool {
        if case AudioLevelMonitorError.screenCaptureDenied = error {
            return true
        }
        return isScreenCaptureDenied(error)
    }

    private func isScreenCaptureDenied(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == SCStreamErrorDomain && nsError.code == -3801
    }

    private func isSystemAudioCaptureFailure(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == SCStreamErrorDomain && nsError.code == -3818
    }

    private func appIdentity() -> String {
        let bundleID = Bundle.main.bundleIdentifier ?? "(no bundle id)"
        let bundlePath = Bundle.main.bundlePath
        let executablePath = Bundle.main.executablePath ?? "(unknown executable)"
        return """
        Bundle ID: \(bundleID)
        Bundle: \(bundlePath)
        Executable: \(executablePath)
        """
    }
}

extension AudioLevelMonitor: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio,
              CMSampleBufferIsValid(sampleBuffer),
              let level = Self.level(from: sampleBuffer)
        else {
            return
        }

        let now = CACurrentMediaTime()
        guard now - lastEmitTime >= 1.0 / 30.0 else {
            return
        }
        lastEmitTime = now

        DispatchQueue.main.async { [weak self] in
            self?.onLevelChanged?(AudioResponsiveLevel(value: level))
        }
    }

    private static func level(from sampleBuffer: CMSampleBuffer) -> Double? {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer),
              let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee
        else {
            return nil
        }

        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        )
        guard status == kCMBlockBufferNoErr,
              let dataPointer,
              totalLength > 0
        else {
            return nil
        }

        let bytesPerFrame = max(1, Int(streamDescription.mBytesPerFrame))
        let frameCount = totalLength / bytesPerFrame
        guard frameCount > 0 else {
            return nil
        }

        let flags = streamDescription.mFormatFlags
        let isFloat = flags & kAudioFormatFlagIsFloat != 0
        let bitsPerChannel = Int(streamDescription.mBitsPerChannel)

        if isFloat, bitsPerChannel == 32 {
            let sampleCount = totalLength / MemoryLayout<Float32>.size
            let samples = dataPointer.withMemoryRebound(to: Float32.self, capacity: sampleCount) { pointer in
                UnsafeBufferPointer(start: pointer, count: sampleCount)
            }
            return normalizedRMS(samples.lazy.map(Double.init))
        }

        if bitsPerChannel == 16 {
            let sampleCount = totalLength / MemoryLayout<Int16>.size
            let samples = dataPointer.withMemoryRebound(to: Int16.self, capacity: sampleCount) { pointer in
                UnsafeBufferPointer(start: pointer, count: sampleCount)
            }
            return normalizedRMS(samples.lazy.map { Double($0) / Double(Int16.max) })
        }

        return nil
    }

    private static func normalizedRMS<S: Sequence>(_ samples: S) -> Double where S.Element == Double {
        var sumSquares = 0.0
        var count = 0
        for sample in samples {
            sumSquares += sample * sample
            count += 1
        }
        guard count > 0 else {
            return 0
        }

        let rms = sqrt(sumSquares / Double(count))
        let boosted = max(0, min(1, rms * 5.5))
        return pow(boosted, 0.7)
    }
}

private enum AudioLevelMonitorError: LocalizedError {
    case noDisplay
    case screenCaptureDenied(appIdentity: String)
    case systemAudioCaptureFailed(appIdentity: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .noDisplay:
            return "No display is available for ScreenCaptureKit audio capture."
        case let .screenCaptureDenied(appIdentity):
            return """
            macOS is still denying Screen & System Audio Recording for this app.

            Grant permission to Wallpaper Engine Mac in System Settings > Privacy & Security > Screen & System Audio Recording, then quit and reopen the app.

            If it is already enabled, remove Wallpaper Engine Mac from that list, reopen this exact app bundle, and grant it again. macOS can keep a stale permission entry when a locally built app is rebuilt.

            \(appIdentity)
            """
        case let .systemAudioCaptureFailed(appIdentity, underlying):
            return """
            ScreenCaptureKit started but system audio capture failed.

            Check System Settings > Privacy & Security > Screen & System Audio Recording for this exact app, then quit and reopen Wallpaper Engine Mac.

            \(appIdentity)

            Underlying error: \(underlying.localizedDescription)
            """
        }
    }
}
