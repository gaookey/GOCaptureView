Pod::Spec.new do |spec|
 
  spec.name                   = 'GOCaptureView'
  spec.version                = '1.0.0'
  spec.summary                = 'A simple custom camera.'
  spec.homepage               = 'https://github.com/gaookey/GOCaptureView'
  spec.license                = { :type => 'MIT', :file => 'LICENSE' }
  spec.author                 = { '高文立' => 'gaookey@gmail.com' }
  spec.platform               = :ios, "13.0"
  spec.source                 = { :git => "https://github.com/gaookey/GOCaptureView.git", :tag => spec.version }
  spec.source_files           = "Classes/**/*"
  spec.swift_version          = '5.0'
 
 end