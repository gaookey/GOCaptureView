# SPCaptureView

### 自定义相机 demo

### 安装

使用 `CocoaPods` 安装: `pod 'SPCaptureView'`



### 部分使用方法：



是否拍摄 LivePhoto 图片

```swift
func toggleLivePhotoMode()
```

切换摄像头

```swift
func toggleCamera()
```

拍照

```swift
func takePhoto(isSavePhotoAlbum: Bool = false) 
```

切换为拍摄视频

```swift
func toggleToVideo() 
```

切换为拍照

```swift
func toggleToPhoto() 
```

开始/结束录像

```swift
func recordVideo(isSavePhotoAlbum: Bool = false) 
```

恢复相机

```swift
func resume() 
```

手电筒

```swift
func torch() 
```

闪光灯

```swift
func flash() 
```

缩放

```swift
func zoom(factor: CGFloat, rate: Float) 
```

聚焦模式

```swift
func focus(point: CGPoint = .zero) 
```

曝光模式

```swift
func exposure(exposureMode: AVCaptureDevice.ExposureMode, point: CGPoint = .zero) 
```

iso

```swift
func iso(value: Float) 
```

白平衡模式

```swift
func whiteBalance(mode: AVCaptureDevice.WhiteBalanceMode) 
```

配置深度数据捕获

```swift
func toggleDepthDataDeliveryMode() 
```

生成肖像效果

```swift
func togglePortraitEffectsMatteDeliveryMode() 
```



```swift
func setSemanticSegmentationMatteTypes(_ types: [AVSemanticSegmentationMatte.MatteType]) 
func setPhotoQualityPrioritizationMode(mode: AVCapturePhotoOutput.QualityPrioritization) 
```

设置聚焦图片

```swift
func setupFocusImageView(image: UIImage = UIImage(named: "focus_image")!, size: CGSize = CGSize(width: 80, height: 80)) 
```

停止

```swift
func stop() 
```



##### 代理 

**`SPCaptureViewDelegate`**

```swift
func didFinishRecording(_ view: UIView, videoPath: String, error: Error?) { }
func didFinishCapture(_ view: UIView, photoData: Data?, moviePath: String?, semanticSegmentationMatteDatas: [Data], error: Error?) { }
func didFinishSavePhotoAlbum(_ view: UIView, success: Bool) { }

func setupCamera(_ view: UIView, setupResult: Int) { }
func resume(_ view: UIView, success: Bool) { }
func photoProcessing(_ view: UIView, animate: Bool) { }
func sessionInterruption(_ view: UIView, ended: Bool) { }
```

