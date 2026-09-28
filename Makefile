# 常用命令。第一次使用前先：brew install xcodegen

.PHONY: project open build test sparkle-tools release clean

project:
	xcodegen generate

open: project
	open Pop.xcodeproj

build: project
	xcodebuild -project Pop.xcodeproj -scheme Pop -configuration Debug -clonedSourcePackagesDirPath build/SourcePackages build

test: project
	xcodebuild -project Pop.xcodeproj -scheme Pop -destination 'platform=macOS' -clonedSourcePackagesDirPath build/SourcePackages CODE_SIGNING_ALLOWED=NO test

# 下载 Sparkle 并打印 generate_keys / generate_appcast 等工具所在目录
sparkle-tools: project
	xcodebuild -resolvePackageDependencies -project Pop.xcodeproj -clonedSourcePackagesDirPath build/SourcePackages
	@find build/SourcePackages/artifacts -type f -name generate_keys -exec dirname {} \;

# 用法：make release VERSION=0.2.0
release:
	scripts/release.sh $(VERSION)

clean:
	rm -rf build Pop.xcodeproj
