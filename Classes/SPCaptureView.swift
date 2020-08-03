//
//  SPCaptureView.swift
//  SPCaptureView
//
//  Created by 高文立 on 2020/7/30.
//  Copyright © 2020 mouos. All rights reserved.
//

import UIKit
import AVFoundation
import Photos

public protocol SPCaptureViewDelegate: NSObjectProtocol {
    
    func didFinishRecording(_ view: UIView, videoPath: String, error: Error?)
    func didFinishCapture(_ view: UIView, photoData: Data?, moviePath: String?, semanticSegmentationMatteDatas: [Data], error: Error?)
    func didFinishSavePhotoAlbum(_ view: UIView, success: Bool)
    
    func setupCamera(_ view: UIView, setupResult: Int)
    func resume(_ view: UIView, success: Bool)
    func photoProcessing(_ view: UIView, animate: Bool)
    func sessionInterruption(_ view: UIView, ended: Bool)
}

public extension SPCaptureViewDelegate {
    
    func didFinishRecording(_ view: UIView, videoPath: String, error: Error?) { }
    func didFinishCapture(_ view: UIView, photoData: Data?, moviePath: String?, semanticSegmentationMatteDatas: [Data], error: Error?) { }
    func didFinishSavePhotoAlbum(_ view: UIView, success: Bool) { }
    
    func setupCamera(_ view: UIView, setupResult: Int) { }
    func resume(_ view: UIView, success: Bool) { }
    func photoProcessing(_ view: UIView, animate: Bool) { }
    func sessionInterruption(_ view: UIView, ended: Bool) { }
}

public class SPCaptureView: UIView, SPCaptureViewDelegate {
    
    weak open var delegate: SPCaptureViewDelegate?
    
    private enum SessionSetupResult: Int {
        case success
        case notAuthorized
        case configurationFailed
    }
    
    private enum LivePhotoMode: Int {
        case on
        case off
    }
    
    private enum CaptureMode: Int {
        case photo
        case video
    }
    
    private enum FlashMode : Int {
        case off
        case on
        case auto
    }
    
    private enum DepthDataDeliveryMode: Int {
        case on
        case off
    }
    
    private enum PortraitEffectsMatteDeliveryMode: Int {
        case on
        case off
    }
    
    private var currentZoomScale: CGFloat = 0
    private var matteDeliveryEnabled = false
    private var depthDataDeliveryMode: DepthDataDeliveryMode = .off
    private var portraitEffectsMatteDeliveryMode: PortraitEffectsMatteDeliveryMode = .off
    private var focusMode: AVCaptureDevice.FocusMode = .continuousAutoFocus
    private var exposureMode: AVCaptureDevice.ExposureMode = .continuousAutoExposure
    
    private var livePhotoMode: LivePhotoMode = .off
    private var captureMode: CaptureMode = .photo
    private var flashMode: FlashMode = .off
    private var photoQualityPrioritizationMode: AVCapturePhotoOutput.QualityPrioritization = .balanced
    
    private var isTakePhotoEnabled = false
    private var isToggleLivePhotoEnabled = false
    private var isToggleCameraEnabled = false
    private var isToggleToPhotoOrVideoEnabled = false
    private var isSavePhotoAlbum = false
    
    private var inProgressPhotoCaptureDelegates = [Int64: SPPhotoCaptureProcessor]()
    private var inProgressLivePhotoCapturesCount = 0
    private var backgroundRecordingID: UIBackgroundTaskIdentifier?
    
    private var keyValueObservations = [NSKeyValueObservation]()
    private var movieFileOutput: AVCaptureMovieFileOutput?
    private let videoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera, .builtInTrueDepthCamera], mediaType: .video, position: .unspecified)
    private var isSessionRunning = false
    private var setupResult: SessionSetupResult = .success
    private let sessionQueue = DispatchQueue(label: "com.swiftprimer.session.queue")
    private let session = AVCaptureSession()
    @objc dynamic private var videoDeviceInput: AVCaptureDeviceInput!
    private let photoOutput = AVCapturePhotoOutput()
    private var semanticSegmentationMatteTypes = [AVSemanticSegmentationMatte.MatteType]()
    
    private var imageScale: CGFloat = 0
    private var windowOrientation: UIInterfaceOrientation {
        return window?.windowScene?.interfaceOrientation ?? .unknown
    }
    
    private lazy var previewViewTapGesture: UITapGestureRecognizer = {
        let tap = UITapGestureRecognizer(target: self, action: #selector(self.focusAndExposeTap(_:)))
        return tap
    }()
    
    private lazy var previewView = SPPreviewView()
    
    private lazy var focusImageView: UIImageView = {
        let image = UIImageView(frame: CGRect(x: 0, y: 0, width: 80, height: 80))
        image.image = UIImage(named: "focus_image")
        image.isHidden = true
        return image
    }()
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        
        previewView.session = session
        addSubview(previewView)
        
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
                if !granted {
                    self.setupResult = .notAuthorized
                }
                self.sessionQueue.resume()
            })
        default:
            setupResult = .notAuthorized
        }
        
        sessionQueue.async {
            self.configureSession()
            self.config()
        }
        DispatchQueue.main.async {
            self.previewView.videoPreviewLayer.videoGravity = .resizeAspectFill
            self.previewView.addSubview(self.focusImageView)
            self.previewView.addGestureRecognizer(self.previewViewTapGesture)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        
        if livePhotoMode == .off {
            previewView.frame = bounds
        } else {
            if bounds.height > bounds.width {
                previewView.frame = CGRect(x: 0, y: (bounds.height - bounds.width * 4.0 / 3.0) / 2.0, width: bounds.width, height: bounds.width * 4.0 / 3.0)
            } else {
                previewView.frame = CGRect(x: (bounds.width - bounds.height * 4.0 / 3.0) / 2.0, y: 0, width: bounds.height * 4.0 / 3.0, height: bounds.height)
            }
        }
        
        imageScale = bounds.width / bounds.height
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

extension SPCaptureView {
    
    private func configureSession() {
        if setupResult != .success {
            return
        }
        
        session.beginConfiguration()
        session.sessionPreset = .photo
        
        do {
            var defaultVideoDevice: AVCaptureDevice?
            
            if let dualCameraDevice = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) {
                defaultVideoDevice = dualCameraDevice
            } else if let backCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
                defaultVideoDevice = backCameraDevice
            } else if let frontCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
                defaultVideoDevice = frontCameraDevice
            }
            guard let videoDevice = defaultVideoDevice else {
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
            let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
            
            if session.canAddInput(videoDeviceInput) {
                session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
                
                DispatchQueue.main.async {
                    
                    var initialVideoOrientation: AVCaptureVideoOrientation = .portrait
                    if self.windowOrientation != .unknown {
                        if let videoOrientation = AVCaptureVideoOrientation(interfaceOrientation: self.windowOrientation) {
                            initialVideoOrientation = videoOrientation
                        }
                    }
                    
                    self.previewView.videoPreviewLayer.connection?.videoOrientation = initialVideoOrientation
                }
            } else {
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
        } catch {
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        do {
            let audioDevice = AVCaptureDevice.default(for: .audio)
            let audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice!)
            
            if session.canAddInput(audioDeviceInput) {
                session.addInput(audioDeviceInput)
            } else { }
        } catch { }
        
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            
            photoOutput.isHighResolutionCaptureEnabled = true
            photoOutput.isLivePhotoCaptureEnabled = photoOutput.isLivePhotoCaptureSupported
            photoOutput.isDepthDataDeliveryEnabled = photoOutput.isDepthDataDeliverySupported
            photoOutput.isPortraitEffectsMatteDeliveryEnabled = photoOutput.isPortraitEffectsMatteDeliverySupported
            photoOutput.enabledSemanticSegmentationMatteTypes = photoOutput.availableSemanticSegmentationMatteTypes
            semanticSegmentationMatteTypes = photoOutput.availableSemanticSegmentationMatteTypes
            photoOutput.maxPhotoQualityPrioritization = .quality
            //livePhotoMode = photoOutput.isLivePhotoCaptureSupported ? .on : .off
            depthDataDeliveryMode = photoOutput.isDepthDataDeliverySupported ? .on : .off
            portraitEffectsMatteDeliveryMode = photoOutput.isPortraitEffectsMatteDeliverySupported ? .on : .off
            photoQualityPrioritizationMode = .balanced
        } else {
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        session.commitConfiguration()
    }
    
    func config() {
        DispatchQueue.main.async {
            self.delegate?.setupCamera(self, setupResult: self.setupResult.rawValue)
        }
        
        sessionQueue.async {
            switch self.setupResult {
            case .success:
                self.addObservers()
                self.session.startRunning()
                self.isSessionRunning = self.session.isRunning
            case .notAuthorized:
                break
            case .configurationFailed:
                break
            }
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(orientationNotification(_:)), name: NSNotification.Name(rawValue: UIApplication.didChangeStatusBarOrientationNotification.rawValue), object: nil)
    }
}

extension SPCaptureView {
    
    private func addObservers() {
        let keyValueObservation = session.observe(\.isRunning, options: .new) { _, change in
            
            guard let isSessionRunning = change.newValue else { return }
            
            DispatchQueue.main.async {
                
                self.isTakePhotoEnabled = isSessionRunning
                self.isToggleLivePhotoEnabled = isSessionRunning && self.photoOutput.isLivePhotoCaptureEnabled
                self.isToggleCameraEnabled = isSessionRunning && self.videoDeviceDiscoverySession.uniqueDevicePositionsCount > 1
                self.isToggleToPhotoOrVideoEnabled = isSessionRunning
            }
        }
        keyValueObservations.append(keyValueObservation)
        
        let systemPressureStateObservation = observe(\.videoDeviceInput.device.systemPressureState, options: .new) { _, change in
            guard let systemPressureState = change.newValue else { return }
            self.setRecommendedFrameRateRangeForPressureState(systemPressureState: systemPressureState)
        }
        keyValueObservations.append(systemPressureStateObservation)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(subjectAreaDidChange),
                                               name: .AVCaptureDeviceSubjectAreaDidChange,
                                               object: videoDeviceInput.device)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(sessionRuntimeError),
                                               name: .AVCaptureSessionRuntimeError,
                                               object: session)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(sessionWasInterrupted),
                                               name: .AVCaptureSessionWasInterrupted,
                                               object: session)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(sessionInterruptionEnded),
                                               name: .AVCaptureSessionInterruptionEnded,
                                               object: session)
    }
    
    private func removeObservers() {
        NotificationCenter.default.removeObserver(self)
        
        for keyValueObservation in keyValueObservations {
            keyValueObservation.invalidate()
        }
        keyValueObservations.removeAll()
    }
    
    private func setRecommendedFrameRateRangeForPressureState(systemPressureState: AVCaptureDevice.SystemPressureState) {
        
        let pressureLevel = systemPressureState.level
        if pressureLevel == .serious || pressureLevel == .critical {
            if self.movieFileOutput == nil || self.movieFileOutput?.isRecording == false {
                do {
                    try self.videoDeviceInput.device.lockForConfiguration()
                    self.videoDeviceInput.device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 20)
                    self.videoDeviceInput.device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 15)
                    self.videoDeviceInput.device.unlockForConfiguration()
                } catch { }
            }
        } else if pressureLevel == .shutdown {
            
        }
    }
    
    @objc func subjectAreaDidChange(notification: NSNotification) {
        let devicePoint = CGPoint(x: 0.5, y: 0.5)
        focus(with: focusMode, exposureMode: exposureMode, at: devicePoint, monitorSubjectAreaChange: false)
    }
    
    @objc func sessionRuntimeError(notification: NSNotification) {
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError else { return }
        
        if error.code == .mediaServicesWereReset {
            sessionQueue.async {
                if self.isSessionRunning {
                    self.session.startRunning()
                    self.isSessionRunning = self.session.isRunning
                } else {
                    DispatchQueue.main.async {
                        self.delegate?.resume(self, success: false)
                    }
                }
            }
        } else {
            self.delegate?.resume(self, success: false)
        }
    }
    
    @objc func sessionWasInterrupted(notification: NSNotification) {
        
        if let userInfoValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as AnyObject?,
            let reasonIntegerValue = userInfoValue.integerValue,
            let reason = AVCaptureSession.InterruptionReason(rawValue: reasonIntegerValue) {
            
            if reason == .audioDeviceInUseByAnotherClient || reason == .videoDeviceInUseByAnotherClient {
                
            } else if reason == .videoDeviceNotAvailableWithMultipleForegroundApps {
                
            } else if reason == .videoDeviceNotAvailableDueToSystemPressure {
                
            }
            
            delegate?.sessionInterruption(self, ended: false)
        }
    }
    
    @objc func sessionInterruptionEnded(notification: NSNotification) {
        delegate?.sessionInterruption(self, ended: true)
    }
}

extension SPCaptureView {
    
    @objc private func focusAndExposeTap(_ gestureRecognizer: UITapGestureRecognizer) {
        let devicePoint = previewView.videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: gestureRecognizer.location(in: gestureRecognizer.view))
        focus(with: .autoFocus, exposureMode: .autoExpose, at: devicePoint, monitorSubjectAreaChange: true)
        
        focusImageView.center = gestureRecognizer.location(in: gestureRecognizer.view)
        focusImageView.isHidden = false
        UIView.animate(withDuration: 0.25, animations: {
            self.focusImageView.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
        }) { (finish) in
            self.focusImageView.transform = CGAffineTransform.identity
            self.focusImageView.isHidden = true
        }
    }
    
    private func focus(with focusMode: AVCaptureDevice.FocusMode,
                       exposureMode: AVCaptureDevice.ExposureMode,
                       at devicePoint: CGPoint,
                       monitorSubjectAreaChange: Bool) {
        
        sessionQueue.async {
            let device = self.videoDeviceInput.device
            do {
                try device.lockForConfiguration()
                
                if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(focusMode) {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = focusMode
                }
                
                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode) {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = exposureMode
                }
                
                device.isSubjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
                device.unlockForConfiguration()
            } catch { }
        }
    }
}

// MARK: - public method
public extension SPCaptureView {
    
    /// LivePhoto on/off
    func toggleLivePhotoMode() {
        guard captureMode == .photo && isToggleLivePhotoEnabled else {
            return
        }
        
        DispatchQueue.main.async {
            self.livePhotoMode = (self.livePhotoMode == .on) ? .off : .on
            self.layoutSubviews()
        }
    }
    
    /// 切换摄像头
    func toggleCamera() {
        
        sessionQueue.async {
            let currentVideoDevice = self.videoDeviceInput.device
            let currentPosition = currentVideoDevice.position
            
            let preferredPosition: AVCaptureDevice.Position
            let preferredDeviceType: AVCaptureDevice.DeviceType
            
            switch currentPosition {
            case .unspecified, .front:
                preferredPosition = .back
                preferredDeviceType = .builtInDualCamera
                
            case .back:
                preferredPosition = .front
                preferredDeviceType = .builtInTrueDepthCamera
                
            @unknown default:
                preferredPosition = .back
                preferredDeviceType = .builtInDualCamera
            }
            let devices = self.videoDeviceDiscoverySession.devices
            var newVideoDevice: AVCaptureDevice? = nil
            
            if let device = devices.first(where: { $0.position == preferredPosition && $0.deviceType == preferredDeviceType }) {
                newVideoDevice = device
            } else if let device = devices.first(where: { $0.position == preferredPosition }) {
                newVideoDevice = device
            }
            
            if let videoDevice = newVideoDevice {
                do {
                    let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
                    
                    self.session.beginConfiguration()
                    
                    self.session.removeInput(self.videoDeviceInput)
                    
                    if self.session.canAddInput(videoDeviceInput) {
                        NotificationCenter.default.removeObserver(self, name: .AVCaptureDeviceSubjectAreaDidChange, object: currentVideoDevice)
                        NotificationCenter.default.addObserver(self, selector: #selector(self.subjectAreaDidChange), name: .AVCaptureDeviceSubjectAreaDidChange, object: videoDeviceInput.device)
                        
                        self.session.addInput(videoDeviceInput)
                        self.videoDeviceInput = videoDeviceInput
                    } else {
                        self.session.addInput(self.videoDeviceInput)
                    }
                    if let connection = self.movieFileOutput?.connection(with: .video) {
                        if connection.isVideoStabilizationSupported {
                            connection.preferredVideoStabilizationMode = .auto
                        }
                    }
                    
                    self.photoOutput.isLivePhotoCaptureEnabled = self.photoOutput.isLivePhotoCaptureSupported
                    self.photoOutput.isDepthDataDeliveryEnabled = self.photoOutput.isDepthDataDeliverySupported
                    self.photoOutput.isPortraitEffectsMatteDeliveryEnabled = self.photoOutput.isPortraitEffectsMatteDeliverySupported
                    self.photoOutput.enabledSemanticSegmentationMatteTypes = self.photoOutput.availableSemanticSegmentationMatteTypes
                    self.semanticSegmentationMatteTypes = self.photoOutput.availableSemanticSegmentationMatteTypes
                    self.photoOutput.maxPhotoQualityPrioritization = .quality
                    
                    self.session.commitConfiguration()
                } catch { }
            }
        }
    }
    
    /// 拍照
    func takePhoto(isSavePhotoAlbum: Bool = false) {
        
        guard isTakePhotoEnabled else {
            return
        }
        
        let videoPreviewLayerOrientation = previewView.videoPreviewLayer.connection?.videoOrientation
        self.isSavePhotoAlbum = isSavePhotoAlbum
        
        sessionQueue.async {
            if let photoOutputConnection = self.photoOutput.connection(with: .video) {
                photoOutputConnection.videoOrientation = videoPreviewLayerOrientation!
            }
            var photoSettings = AVCapturePhotoSettings()
            
            if  self.photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            }
            
            if self.videoDeviceInput.device.isFlashAvailable {
                photoSettings.flashMode = AVCaptureDevice.FlashMode(rawValue: self.flashMode.rawValue)!
            }
            
            photoSettings.isHighResolutionPhotoEnabled = true
            if !photoSettings.__availablePreviewPhotoPixelFormatTypes.isEmpty {
                photoSettings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String: photoSettings.__availablePreviewPhotoPixelFormatTypes.first!]
            }
            
            if self.livePhotoMode == .on && self.photoOutput.isLivePhotoCaptureSupported {
                let livePhotoMovieFileName = NSUUID().uuidString
                let livePhotoMovieFilePath = (NSTemporaryDirectory() as NSString).appendingPathComponent((livePhotoMovieFileName as NSString).appendingPathExtension("mov")!)
                photoSettings.livePhotoMovieFileURL = URL(fileURLWithPath: livePhotoMovieFilePath)
            }
            
            photoSettings.isDepthDataDeliveryEnabled = (self.depthDataDeliveryMode == .on && self.photoOutput.isDepthDataDeliveryEnabled)
            photoSettings.isPortraitEffectsMatteDeliveryEnabled = (self.portraitEffectsMatteDeliveryMode == .on && self.photoOutput.isPortraitEffectsMatteDeliveryEnabled)
            
            if photoSettings.isDepthDataDeliveryEnabled {
                if !self.photoOutput.availableSemanticSegmentationMatteTypes.isEmpty {
                    photoSettings.enabledSemanticSegmentationMatteTypes = self.semanticSegmentationMatteTypes
                }
            }
            
            photoSettings.photoQualityPrioritization = self.photoQualityPrioritizationMode
            
            let photoCaptureProcessor = SPPhotoCaptureProcessor(isLivePhoto: (self.livePhotoMode == .on), imageScale: self.imageScale, isSavePhotoAlbum: self.isSavePhotoAlbum, requestedPhotoSettings: photoSettings, willCapturePhotoAnimation: {
                
                //                DispatchQueue.main.async {
                //                    self.previewView.videoPreviewLayer.opacity = 0
                //                    UIView.animate(withDuration: 0.25) {
                //                        self.previewView.videoPreviewLayer.opacity = 1
                //                    }
                //                }
            }, livePhotoCaptureHandler: { capturing in
                self.sessionQueue.async {
                    if capturing {
                        self.inProgressLivePhotoCapturesCount += 1
                    } else {
                        self.inProgressLivePhotoCapturesCount -= 1
                    }
                    
                    let inProgressLivePhotoCapturesCount = self.inProgressLivePhotoCapturesCount
                    DispatchQueue.main.async {
                        if inProgressLivePhotoCapturesCount > 0 {
                            // LivePhoto
                        } else if inProgressLivePhotoCapturesCount == 0 {
                            // no LivePhoto
                        } else {
                            //Error: In progress Live Photo capture count is less than 0.
                        }
                    }
                }
            }, completionHandler: { (data, path, semanticSegmentationMatteDatas, error, photoCaptureProcessor) in
                
                self.sessionQueue.async {
                    self.inProgressPhotoCaptureDelegates[photoCaptureProcessor.requestedPhotoSettings.uniqueID] = nil
                }
                DispatchQueue.main.async {
                    self.delegate?.didFinishCapture(self, photoData: data, moviePath: path, semanticSegmentationMatteDatas: semanticSegmentationMatteDatas, error: error)
                }
            }, photoProcessingHandler: { animate in
                
                DispatchQueue.main.async {
                    if animate {
                        // photo is processing
                    } else {
                        
                    }
                }
            }, savePhotoAlbumHandler: { success in
                self.delegate?.didFinishSavePhotoAlbum(self, success: success)
            })
            
            self.inProgressPhotoCaptureDelegates[photoCaptureProcessor.requestedPhotoSettings.uniqueID] = photoCaptureProcessor
            self.photoOutput.capturePhoto(with: photoSettings, delegate: photoCaptureProcessor)
        }
    }
    
    /// 切换为视频
    func toggleToVideo() {
        guard captureMode == .photo && isToggleToPhotoOrVideoEnabled else {
            return
        }
        captureMode = .video
        
        sessionQueue.async {
            let movieFileOutput = AVCaptureMovieFileOutput()
            
            if self.session.canAddOutput(movieFileOutput) {
                self.session.beginConfiguration()
                self.session.addOutput(movieFileOutput)
                self.session.sessionPreset = .high
                if let connection = movieFileOutput.connection(with: .video) {
                    if connection.isVideoStabilizationSupported {
                        connection.preferredVideoStabilizationMode = .auto
                    }
                }
                self.session.commitConfiguration()
                
                self.movieFileOutput = movieFileOutput
                //self.photoQualityPrioritizationMode = .speed
            }
        }
    }
    
    /// 切换为拍照
    func toggleToPhoto() {
        guard captureMode == .video && isToggleToPhotoOrVideoEnabled else {
            return
        }
        captureMode = .photo
        
        sessionQueue.async {
            
            self.session.beginConfiguration()
            self.session.removeOutput(self.movieFileOutput!)
            self.session.sessionPreset = .photo
            
            self.movieFileOutput = nil
            
            if self.photoOutput.isLivePhotoCaptureSupported {
                self.photoOutput.isLivePhotoCaptureEnabled = true
            }
            if self.photoOutput.isDepthDataDeliverySupported {
                self.photoOutput.isDepthDataDeliveryEnabled = true
            }
            if self.photoOutput.isPortraitEffectsMatteDeliverySupported {
                self.photoOutput.isPortraitEffectsMatteDeliveryEnabled = true
            }
            if !self.photoOutput.availableSemanticSegmentationMatteTypes.isEmpty {
                self.photoOutput.enabledSemanticSegmentationMatteTypes = self.photoOutput.availableSemanticSegmentationMatteTypes
                self.semanticSegmentationMatteTypes = self.photoOutput.availableSemanticSegmentationMatteTypes
            }
            
            self.session.commitConfiguration()
        }
    }
    
    
    /// 开始/结束录像
    func recordVideo(isSavePhotoAlbum: Bool = false) {
        guard let movieFileOutput = self.movieFileOutput else {
            return
        }
        
        isTakePhotoEnabled = false
        isToggleCameraEnabled = false
        isToggleToPhotoOrVideoEnabled = false
        
        let videoPreviewLayerOrientation = previewView.videoPreviewLayer.connection?.videoOrientation
        
        sessionQueue.async {
            if !movieFileOutput.isRecording {
                self.isSavePhotoAlbum = isSavePhotoAlbum
                
                if UIDevice.current.isMultitaskingSupported {
                    self.backgroundRecordingID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
                }
                
                let movieFileOutputConnection = movieFileOutput.connection(with: .video)
                movieFileOutputConnection?.videoOrientation = videoPreviewLayerOrientation!
                
                let availableVideoCodecTypes = movieFileOutput.availableVideoCodecTypes
                
                if availableVideoCodecTypes.contains(.hevc) {
                    movieFileOutput.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.hevc], for: movieFileOutputConnection!)
                }
                
                let outputFileName = NSUUID().uuidString
                let outputFilePath = (NSTemporaryDirectory() as NSString).appendingPathComponent((outputFileName as NSString).appendingPathExtension("mov")!)
                movieFileOutput.startRecording(to: URL(fileURLWithPath: outputFilePath), recordingDelegate: self)
            } else {
                movieFileOutput.stopRecording()
            }
        }
    }
    
    /// 恢复
    func resume() {
        sessionQueue.async {
            self.session.startRunning()
            self.isSessionRunning = self.session.isRunning
            
            DispatchQueue.main.async {
                self.delegate?.resume(self, success: self.session.isRunning)
            }
        }
    }
    
    /// 手电筒
    func torch() {
        sessionQueue.async {
            let device = self.videoDeviceInput.device
            var mode = device.torchMode
            mode = (mode == .off) ? .on : .off
            
            do {
                try device.lockForConfiguration()
                if device.hasTorch {
                    if device.isTorchModeSupported(mode) {
                        device.torchMode = mode
                    }
                }
                device.unlockForConfiguration()
            } catch { }
        }
    }
    
    /// 闪光灯
    func flash() {
        flashMode = (flashMode == .off) ? .on : ((flashMode == .on) ? .auto : .off)
    }
    
    /// 缩放
    func zoom(factor: CGFloat, rate: Float) {
        
        sessionQueue.async {
            let device = self.videoDeviceInput.device
            
            do {
                try device.lockForConfiguration()
                if device.activeFormat.videoMaxZoomFactor > factor && factor >= 1.0 {
                    device.ramp(toVideoZoomFactor: factor, withRate: rate)
                }
                device.unlockForConfiguration()
            } catch { }
        }
    }
    
    /// 聚焦模式
    func focus(point: CGPoint = .zero) {
        
        sessionQueue.async {
            let device = self.videoDeviceInput.device
            self.focusMode = (self.focusMode == .locked) ? .autoFocus : ((self.focusMode == .autoFocus) ? .continuousAutoFocus : .locked)
            
            DispatchQueue.main.async {
                if self.focusMode == .locked {
                    self.previewView.removeGestureRecognizer(self.previewViewTapGesture)
                } else {
                    self.previewView.addGestureRecognizer(self.previewViewTapGesture)
                }
            }
            
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(self.focusMode) {
                    device.focusPointOfInterest = point
                    device.focusMode = self.focusMode
                }
                device.unlockForConfiguration()
            } catch { }
        }
    }
    
    /// 曝光模式
    func exposure(exposureMode: AVCaptureDevice.ExposureMode, point: CGPoint = .zero) {
        
        sessionQueue.async {
            let device = self.videoDeviceInput.device
            
            do {
                try device.lockForConfiguration()
                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode) {
                    device.exposurePointOfInterest = point
                    device.exposureMode = exposureMode
                }
                device.unlockForConfiguration()
            } catch { }
        }
    }
    
    /// iso
    func iso(value: Float) {
        let device = self.videoDeviceInput.device
        guard device.activeFormat.minISO < value && value < device.activeFormat.maxISO else {
            return
        }
        
        do {
            try device.lockForConfiguration()
            device.setExposureModeCustom(duration: device.exposureDuration, iso: value, completionHandler: { (time) in })
            device.unlockForConfiguration()
        } catch { }
    }
    
    /// 白平衡模式
    func whiteBalance(mode: AVCaptureDevice.WhiteBalanceMode) {
        
        sessionQueue.async {
            let device = self.videoDeviceInput.device
            
            do {
                try device.lockForConfiguration()
                if device.isWhiteBalanceModeSupported(mode) {
                    device.whiteBalanceMode = mode
                }
                device.unlockForConfiguration()
            } catch { }
        }
    }
    
    func setPhotoQualityPrioritizationMode(mode: AVCapturePhotoOutput.QualityPrioritization) {
        self.photoQualityPrioritizationMode = mode
    }
    
    /// 配置深度数据捕获
    func toggleDepthDataDeliveryMode() {
        
        guard photoOutput.isDepthDataDeliveryEnabled else {
            return
        }
        
        sessionQueue.async {
            self.depthDataDeliveryMode = (self.depthDataDeliveryMode == .on) ? .off : .on
            let depthDataDeliveryMode = self.depthDataDeliveryMode
            if depthDataDeliveryMode == .on {
                self.portraitEffectsMatteDeliveryMode = .on
            } else {
                self.portraitEffectsMatteDeliveryMode = .off
            }
            
            if depthDataDeliveryMode == .on {
                self.matteDeliveryEnabled = true
            } else {
                self.matteDeliveryEnabled = false
            }
        }
    }
    
    /// 生成肖像效果
    func togglePortraitEffectsMatteDeliveryMode() {
        
        guard matteDeliveryEnabled && photoOutput.isPortraitEffectsMatteDeliveryEnabled else {
            return
        }
        
        sessionQueue.async {
            if self.portraitEffectsMatteDeliveryMode == .on {
                self.portraitEffectsMatteDeliveryMode = .off
            } else {
                self.portraitEffectsMatteDeliveryMode = (self.depthDataDeliveryMode == .off) ? .off : .on
            }
        }
    }
    
    func setSemanticSegmentationMatteTypes(_ types: [AVSemanticSegmentationMatte.MatteType]) {
        guard matteDeliveryEnabled else {
            return
        }
        self.semanticSegmentationMatteTypes = types
    }
    
    func setupFocusImageView(image: UIImage = UIImage(named: "focus_image")!, size: CGSize = CGSize(width: 80, height: 80)) {
        focusImageView.image = image
        focusImageView.frame.size = size
    }
    
    func stop() {
        sessionQueue.async {
            if self.setupResult == .success {
                self.session.stopRunning()
                self.isSessionRunning = self.session.isRunning
                self.removeObservers()
            }
        }
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate
extension SPCaptureView: AVCaptureFileOutputRecordingDelegate {
    
    public func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        
    }
    
    public func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        
        func cleanup() {
            //            if FileManager.default.fileExists(atPath: outputFileURL.path) {
            //                do {
            //                    try FileManager.default.removeItem(atPath: path)
            //                } catch { }
            //            }
            
            if let currentBackgroundRecordingID = backgroundRecordingID {
                backgroundRecordingID = UIBackgroundTaskIdentifier.invalid
                
                if currentBackgroundRecordingID != UIBackgroundTaskIdentifier.invalid {
                    UIApplication.shared.endBackgroundTask(currentBackgroundRecordingID)
                }
            }
        }
        
        var success = true
        
        if error != nil {
            success = (((error! as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as AnyObject).boolValue)!
        }
        
        if success && isSavePhotoAlbum {
            
            PHPhotoLibrary.requestAuthorization { status in
                if status == .authorized {
                    
                    PHPhotoLibrary.shared().performChanges({
                        let options = PHAssetResourceCreationOptions()
                        options.shouldMoveFile = true
                        let creationRequest = PHAssetCreationRequest.forAsset()
                        creationRequest.addResource(with: .video, fileURL: outputFileURL, options: options)
                    }, completionHandler: { success, error in
                        self.delegate?.didFinishSavePhotoAlbum(self, success: success)
                        cleanup()
                    })
                } else {
                    self.delegate?.didFinishSavePhotoAlbum(self, success: false)
                    cleanup()
                }
            }
        } else {
            cleanup()
        }
        
        self.delegate?.didFinishRecording(self, videoPath: outputFileURL.path, error: error)
        
        self.isTakePhotoEnabled = true
        self.isToggleCameraEnabled = self.videoDeviceDiscoverySession.uniqueDevicePositionsCount > 1
        self.isToggleToPhotoOrVideoEnabled = true
    }
}

extension SPCaptureView {
    
    @objc func orientationNotification(_ noti: Notification) {
        
        if let videoPreviewLayerConnection = previewView.videoPreviewLayer.connection {
            let deviceOrientation = UIDevice.current.orientation
            guard let newVideoOrientation = AVCaptureVideoOrientation(deviceOrientation: deviceOrientation),
                deviceOrientation.isPortrait || deviceOrientation.isLandscape else {
                    return
            }
            videoPreviewLayerConnection.videoOrientation = newVideoOrientation
        }
    }
}

extension AVCaptureVideoOrientation {
    init?(deviceOrientation: UIDeviceOrientation) {
        switch deviceOrientation {
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeRight
        case .landscapeRight: self = .landscapeLeft
        default: return nil
        }
    }
    
    init?(interfaceOrientation: UIInterfaceOrientation) {
        switch interfaceOrientation {
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeLeft
        case .landscapeRight: self = .landscapeRight
        default: return nil
        }
    }
}

extension AVCaptureDevice.DiscoverySession {
    var uniqueDevicePositionsCount: Int {
        
        var uniqueDevicePositions = [AVCaptureDevice.Position]()
        for device in devices where !uniqueDevicePositions.contains(device.position) {
            uniqueDevicePositions.append(device.position)
        }
        return uniqueDevicePositions.count
    }
}

