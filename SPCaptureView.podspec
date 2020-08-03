Pod::Spec.new do |spec|
 
  spec.name                   = 'SPCaptureView'
  spec.version                = '0.0.5'
  spec.summary                = 'A simple custom camera.'
  spec.homepage               = 'https://mouos.com'
  spec.license                = { :type => 'MIT', :file => 'LICENSE' }
  spec.author                 = { '高文立' => 'swiftprimer@gmail.com' }
  spec.platform               = :ios, "13.0"
  spec.source                 = { :git => "https://github.com/mouos/SPCaptureView.git", :tag => spec.version }
  spec.source_files           = "Classes/**/*"
  spec.resource               = 'SPCaptureView/SPCaptureView.bundle'
  spec.swift_version          = '5.0'
 
 end