# 常用命令。第一次使用前先：brew install xcodegen

.PHONY: project open build test app release signing-certificate clean

project:
	xcodegen generate

open: project
	open Pop.xcodeproj

build: project
	xcodebuild -project Pop.xcodeproj -scheme Pop -configuration Debug -clonedSourcePackagesDirPath build/SourcePackages build

test: project
	xcodebuild -project Pop.xcodeproj -scheme Pop -destination 'platform=macOS' -clonedSourcePackagesDirPath build/SourcePackages CODE_SIGNING_ALLOWED=NO test

# 在本机构建 Release 版 Pop.app（默认本地签名；设置 CODESIGN_IDENTITY 时用证书签名）
# 用法：make app VERSION=0.3.0
app:
	scripts/build-app.sh $(or $(VERSION),0.0.0-dev) build/app

# 在 GitHub Actions 上构建并发布（需要 GitHub CLI：brew install gh && gh auth login）
# 用法：make release VERSION=0.3.0            发布测试版
#       make release VERSION=1.0.0 STABLE=1   发布正式版
release:
	@test -n "$(VERSION)" || (echo "用法：make release VERSION=0.3.0" && exit 1)
	gh workflow run release.yml -f version=$(VERSION) -f prerelease=$(if $(STABLE),false,true)
	@echo "已开始发布，进度见：gh run watch 或 GitHub 的 Actions 页面"

# 生成一张自签名的代码签名证书（让更新后不用重新授权辅助功能），见 README「签名与公证」
signing-certificate:
	scripts/create-signing-certificate.sh

clean:
	rm -rf build Pop.xcodeproj
