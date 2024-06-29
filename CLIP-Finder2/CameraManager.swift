//
//  CameraManager.swift
//  CLIP-Finder2
//
//  Created by Fabio Guzman on 28/06/24.
//

import AVFoundation
import CoreImage
import UIKit

class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var session = AVCaptureSession()
    private var camera: AVCaptureDevice?
    private var input: AVCaptureDeviceInput?
    private var output = AVCaptureVideoDataOutput()
    private let processingQueue = DispatchQueue(label: "processingQueue")
    var onFrameCaptured: ((CIImage) -> Void)?
//    private var isPaused: Bool = false
//    var lastCapturedFrame: CIImage?

    override init() {
        super.init()
        setupSession()
    }
    
//    func pauseCapture() {
//        isPaused = true
//    }
//    
//    func resumeCapture() {
//        isPaused = false
//    }
    
//    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
//        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
//        let ciImage = CIImage(cvImageBuffer: imageBuffer)
//        lastCapturedFrame = ciImage
//        
//        DispatchQueue.main.async { [weak self] in
//            self?.onFrameCaptured?(ciImage)
//        }
//    }
    
    @objc func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
            guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            let ciImage = CIImage(cvImageBuffer: imageBuffer)
            DispatchQueue.main.async { [weak self] in
                self?.onFrameCaptured?(ciImage)
            }
        }

    func setupSession() {
        session.sessionPreset = .high
        camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        
        do {
            input = try AVCaptureDeviceInput(device: camera!)
            if session.canAddInput(input!) {
                session.addInput(input!)
            }
        } catch {
            print("Error setting device input: \(error.localizedDescription)")
            return
        }

        output.setSampleBufferDelegate(self, queue: processingQueue)
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        
        configureCamera()
    }

    func startRunning() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            if !self.session.isRunning {
                self.session.startRunning()
//                DispatchQueue.main.async {
//                // Update UI frome here if required
//                }
            }
        }
    }

    func stopRunning() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    func switchCamera() {
        guard let currentInput = input else { return }
        session.beginConfiguration()
        session.removeInput(currentInput)

        if currentInput.device.position == .back {
            camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        } else {
            camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        }

        do {
            input = try AVCaptureDeviceInput(device: camera!)
            if session.canAddInput(input!) {
                session.addInput(input!)
            }
        } catch {
            print("Error switching camera: \(error.localizedDescription)")
        }

        session.commitConfiguration()
    }
    
    private func configureCamera() {
        guard let camera = self.camera else { return }
        
        do {
            try camera.lockForConfiguration()
            
            if camera.isFocusModeSupported(.continuousAutoFocus) {
                camera.focusMode = .continuousAutoFocus
            }
            
            if camera.isAutoFocusRangeRestrictionSupported {
                camera.autoFocusRangeRestriction = .near
            }
            
            camera.unlockForConfiguration()
        } catch {
            print("Error configurando la cámara: \(error)")
        }
    }
    
    func focusAtPoint(_ point: CGPoint) {
        guard let camera = self.camera else { return }
        
        do {
            try camera.lockForConfiguration()
            
            if camera.isFocusModeSupported(.autoFocus) {
                camera.focusPointOfInterest = point
                camera.focusMode = .autoFocus
            }
            
            if camera.isExposureModeSupported(.autoExpose) {
                camera.exposurePointOfInterest = point
                camera.exposureMode = .autoExpose
            }
            
            camera.unlockForConfiguration()
        } catch {
            print("Error al enfocar: \(error)")
        }
    }
}

