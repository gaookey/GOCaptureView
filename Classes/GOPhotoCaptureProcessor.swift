//
//  GOPhotoCaptureProcessor.swift
//  GOCaptureView
//
//  Created by 高文立 on 2020/7/30.
//

import UIKit
import AVFoundation
import Photos

@objcMembers class GOPhotoCaptureProcessor: NSObject {
    
    private(set) var requestedPhotoSettings: AVCapturePhotoSettings
    private let willCapturePhotoAnimation: () -> Void
    private let livePhotoCaptureHandler: (Bool) -> Void
    private lazy var context = CIContext()
    private let completionHandler: (Data?, String?, [Data], Error?, GOPhotoCaptureProcessor) -> Void
    private let photoProcessingHandler: (Bool) -> Void
    private let savePhotoAlbumHandler: (Bool) -> Void
    private var portraitEffectsMatteData: Data?
    private var semanticSegmentationMatteDatas = [Data]()
    private var maxPhotoProcessingTime: CMTime?
    
    private var isSavePhotoAlbum = false
    private var error: Error?
    private var photoData: Data?
    private var livePhotoCompanionMovieURL: URL?
    private var imageScale: CGFloat = 0
    private var isLivePhoto = false
    
    init(isLivePhoto: Bool = false,
         imageScale: CGFloat,
         isSavePhotoAlbum: Bool = false,
         requestedPhotoSettings: AVCapturePhotoSettings,
         willCapturePhotoAnimation: @escaping () -> Void,
         livePhotoCaptureHandler: @escaping (Bool) -> Void,
         completionHandler: @escaping (Data?, String?, [Data], Error?, GOPhotoCaptureProcessor) -> Void,
         photoProcessingHandler: @escaping (Bool) -> Void,
         savePhotoAlbumHandler: @escaping (Bool) -> Void) {
        
        self.isLivePhoto = isLivePhoto
        self.imageScale = imageScale
        self.isSavePhotoAlbum = isSavePhotoAlbum
        self.requestedPhotoSettings = requestedPhotoSettings
        self.willCapturePhotoAnimation = willCapturePhotoAnimation
        self.livePhotoCaptureHandler = livePhotoCaptureHandler
        self.completionHandler = completionHandler
        self.photoProcessingHandler = photoProcessingHandler
        self.savePhotoAlbumHandler = savePhotoAlbumHandler
    }
    
    private func didFinish() {
        //        if let livePhotoCompanionMoviePath = livePhotoCompanionMovieURL?.path {
        //            if FileManager.default.fileExists(atPath: livePhotoCompanionMoviePath) {
        //                do {
        //                    try FileManager.default.removeItem(atPath: livePhotoCompanionMoviePath)
        //                } catch { }
        //            }
        //        }
        
        completionHandler(photoData, livePhotoCompanionMovieURL?.path, self.semanticSegmentationMatteDatas, error, self)
    }
    
}

// MARK: - AVCapturePhotoCaptureDelegate
extension GOPhotoCaptureProcessor: AVCapturePhotoCaptureDelegate {
    
    // 设置完毕
    func photoOutput(_ output: AVCapturePhotoOutput, willBeginCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        if resolvedSettings.livePhotoMovieDimensions.width > 0 && resolvedSettings.livePhotoMovieDimensions.height > 0 {
            livePhotoCaptureHandler(true)
        }
        maxPhotoProcessingTime = resolvedSettings.photoProcessingTimeRange.start + resolvedSettings.photoProcessingTimeRange.duration
    }
    
    // 开始曝光
    func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        willCapturePhotoAnimation()
        
        guard let maxPhotoProcessingTime = maxPhotoProcessingTime else {
            return
        }
        
        let oneSecond = CMTime(seconds: 1, preferredTimescale: 1)
        if maxPhotoProcessingTime > oneSecond {
            photoProcessingHandler(true)
        }
    }
    
    // 静态图片获取
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        photoProcessingHandler(false)
        
        if let error = error {
            print("Error capturing photo: \(error)")
        } else {
            photoData = crop(data: photo.fileDataRepresentation()!, scale: imageScale)
        }
        
        if var portraitEffectsMatte = photo.portraitEffectsMatte {
            if let orientation = photo.metadata[ String(kCGImagePropertyOrientation) ] as? UInt32 {
                portraitEffectsMatte = portraitEffectsMatte.applyingExifOrientation(CGImagePropertyOrientation(rawValue: orientation)!)
            }
            let portraitEffectsMattePixelBuffer = portraitEffectsMatte.mattingImage
            let portraitEffectsMatteImage = CIImage( cvImageBuffer: portraitEffectsMattePixelBuffer, options: [ .auxiliaryPortraitEffectsMatte: true ] )
            
            guard let perceptualColorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
                portraitEffectsMatteData = nil
                return
            }
            portraitEffectsMatteData = context.heifRepresentation(of: portraitEffectsMatteImage,
                                                                  format: .RGBA8,
                                                                  colorSpace: perceptualColorSpace,
                                                                  options: [.portraitEffectsMatteImage: portraitEffectsMatteImage])
        } else {
            portraitEffectsMatteData = nil
        }
        
        for semanticSegmentationType in output.enabledSemanticSegmentationMatteTypes {
            handleMatteData(photo, ssmType: semanticSegmentationType)
        }
    }
    
    // 结束动态图片拍摄
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishRecordingLivePhotoMovieForEventualFileAt outputFileURL: URL, resolvedSettings: AVCaptureResolvedPhotoSettings) {
        livePhotoCaptureHandler(false)
    }
    
    // 动态图片结果处理
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingLivePhotoToMovieFileAt outputFileURL: URL, duration: CMTime, photoDisplayTime: CMTime, resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        
        guard error == nil else {
            return
        }
        livePhotoCompanionMovieURL = outputFileURL
    }
    
    // 拍照完成
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        
        self.error = error
        didFinish()
        
        guard error == nil else {
            return
        }
        
        guard let photoData = photoData else {
            return
        }
        
        guard isSavePhotoAlbum else {
            return
        }
        
        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized {
                
                PHPhotoLibrary.shared().performChanges({
                    let options = PHAssetResourceCreationOptions()
                    let creationRequest = PHAssetCreationRequest.forAsset()
                    options.uniformTypeIdentifier = self.requestedPhotoSettings.processedFileType.map { $0.rawValue }
                    creationRequest.addResource(with: .photo, data: photoData, options: options)
                    
                    if let livePhotoCompanionMovieURL = self.livePhotoCompanionMovieURL {
                        let livePhotoCompanionMovieFileOptions = PHAssetResourceCreationOptions()
                        livePhotoCompanionMovieFileOptions.shouldMoveFile = true
                        creationRequest.addResource(with: .pairedVideo,
                                                    fileURL: livePhotoCompanionMovieURL,
                                                    options: livePhotoCompanionMovieFileOptions)
                    }
                    
                    if let portraitEffectsMatteData = self.portraitEffectsMatteData {
                        let creationRequest = PHAssetCreationRequest.forAsset()
                        creationRequest.addResource(with: .photo,
                                                    data: portraitEffectsMatteData,
                                                    options: nil)
                    }
                    
                    for semanticSegmentationMatteData in self.semanticSegmentationMatteDatas {
                        let creationRequest = PHAssetCreationRequest.forAsset()
                        creationRequest.addResource(with: .photo,
                                                    data: semanticSegmentationMatteData,
                                                    options: nil)
                    }
                    
                }) { (success, error) in
                    self.savePhotoAlbumHandler(success)
                }
            } else {
                self.savePhotoAlbumHandler(false)
            }
        }
    }
}

extension GOPhotoCaptureProcessor {
    
    func handleMatteData(_ photo: AVCapturePhoto, ssmType: AVSemanticSegmentationMatte.MatteType) {
        
        guard var segmentationMatte = photo.semanticSegmentationMatte(for: ssmType) else { return }
        
        if let orientation = photo.metadata[String(kCGImagePropertyOrientation)] as? UInt32,
            let exifOrientation = CGImagePropertyOrientation(rawValue: orientation) {
            segmentationMatte = segmentationMatte.applyingExifOrientation(exifOrientation)
        }
        
        var imageOption: CIImageOption!
        
        switch ssmType {
        case .hair:
            imageOption = .auxiliarySemanticSegmentationHairMatte
        case .skin:
            imageOption = .auxiliarySemanticSegmentationSkinMatte
        case .teeth:
            imageOption = .auxiliarySemanticSegmentationTeethMatte
        default:
            return
        }
        
        guard let perceptualColorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return }
        
        let ciImage = CIImage( cvImageBuffer: segmentationMatte.mattingImage,
                               options: [imageOption: true,
                                         .colorSpace: perceptualColorSpace])
        
        guard let imageData = context.heifRepresentation(of: ciImage,
                                                         format: .RGBA8,
                                                         colorSpace: perceptualColorSpace,
                                                         options: [.depthImage: ciImage]) else { return }
        
        semanticSegmentationMatteDatas.append(crop(data: imageData, scale: imageScale))
    }
    
    func crop(data: Data, scale: CGFloat) -> Data {
        
        guard !self.isLivePhoto else {
            return data
        }
        
        guard let image = UIImage(data: data) else {
            return data
        }
        
        var x: CGFloat = 0, y: CGFloat = 0, width: CGFloat = 0, height: CGFloat = 0
        
        if (image.size.width / image.size.height) > scale {
            height = image.size.height
            width = image.size.height * scale
            x = (image.size.width - width) / 2.0
        } else {
            width = image.size.width
            height = image.size.width / scale
            y = (image.size.height - height) / 2.0
        }
        
        let rect = CGRect(x: x, y: y, width: width, height: height)
        
        UIGraphicsBeginImageContextWithOptions(rect.size, false, scale)
        image.draw(at: CGPoint(x: -rect.origin.x, y: -rect.origin.y))
        let image2 = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image2!.jpegData(compressionQuality: 1)!
    }
}

