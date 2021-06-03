Pod::Spec.new do |spec|
 
  spec.name                   = 'SPCaptureView'
  spec.version                = '0.0.10'
  spec.summary                = 'A simple custom camera.'
  spec.homepage               = 'https://github.com/gaookey/SPCaptureView'
  spec.license                = { :type => 'MIT', :file => 'LICENSE' }
  spec.author                 = { '高文立' => 'gaookey@gmail.com' }
  spec.platform               = :ios, "13.0"
  spec.source                 = { :git => "https://github.com/gaookey/SPCaptureView.git", :tag => spec.version }
  spec.source_files           = "Classes/**/*"
  spec.swift_version          = '5.0'
 
 end