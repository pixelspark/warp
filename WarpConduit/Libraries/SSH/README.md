To build these:

* Clone LibSSH2 into a directory
* brew install openssl
* mkdir xcode
* cd xcode
* cmake -DOPENSSL_ROOT_DIR=/usr/local/opt/openssl -G Xcode ..
* Open the generated XCode project
* Set the libssh2 target build configuration to Release and build it
* Duplicate the libssh2 target, set SDK to iOS, set 'Build active architecture only' to false
* Build once for the iPhone simulator and once for 'generic iOS device'

Check that the generated files contain images for the right architectures; lipo -info libssh*.lib should show that the macOS library is a non-fat x86_64 image, the iOS library contains armv7 and arm64 images, and the simulator library contains both i386 as well as x86_64 images.
