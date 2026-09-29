#!/usr/bin/env bash
# 生成一张自签名的代码签名证书，给 Pop 的发布包签名用。
#
# 为什么要它：本地签名（ad-hoc）的包每次构建签名都不一样，macOS 会把新版本当成另一个程序，
# 一键更新后辅助功能授权就失效了。用同一张证书签名，每个版本的签名「身份」都一样，更新后授权还在。
# 它不能代替苹果的 Developer ID：第一次打开仍然要解除隔离，也不能公证。有付费开发者账号时直接用 Developer ID 证书更好。
#
# 用法：scripts/create-signing-certificate.sh [证书名字]
# 文件放在 ~/.pop-signing/（可以用 POP_SIGNING_DIR 换位置），按最后打印的提示填进 GitHub 仓库的 Secrets。
# 请备份这个文件夹：证书丢了只能换一张新的，换证书后的第一次更新需要重新授权一次。
set -euo pipefail

NAME="${1:-Pop Release Signing}"
DIR="${POP_SIGNING_DIR:-$HOME/.pop-signing}"
OPENSSL="/usr/bin/openssl"
[ -x "$OPENSSL" ] || OPENSSL="openssl"

mkdir -p "$DIR"
chmod 700 "$DIR"
if [ -e "$DIR/certificate.p12" ]; then
  echo "$DIR 里已经有证书了。要重新生成的话先把这个文件夹挪走（换证书后的第一次更新需要重新授权）。" >&2
  exit 1
fi

cat > "$DIR/openssl.cnf" <<CONF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = ${NAME}
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
CONF

PASSWORD="$("$OPENSSL" rand -hex 16)"
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$DIR/openssl.cnf" \
  -keyout "$DIR/key.pem" -out "$DIR/certificate.pem" 2>/dev/null
# 用老式的加密算法导出，macOS 的 security 命令才能导入
"$OPENSSL" pkcs12 -export -inkey "$DIR/key.pem" -in "$DIR/certificate.pem" -name "$NAME" \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
  -out "$DIR/certificate.p12" -passout "pass:$PASSWORD"
rm -f "$DIR/key.pem" "$DIR/openssl.cnf"
printf '%s' "$PASSWORD" > "$DIR/password.txt"
base64 < "$DIR/certificate.p12" | tr -d '\n' > "$DIR/certificate.p12.base64"
chmod 600 "$DIR"/*

cat <<INFO

已生成签名证书「${NAME}」，有效期 10 年，文件在 ${DIR}：
  certificate.p12          证书和私钥
  certificate.p12.base64   上面那个文件的 base64
  password.txt             .p12 的密码

接下来在 GitHub 仓库 → Settings → Secrets and variables → Actions → New repository secret 里添加两项：
  MACOS_CERTIFICATE_P12        粘贴 certificate.p12.base64 的内容（macOS 上可以 pbcopy < ${DIR}/certificate.p12.base64）
  MACOS_CERTIFICATE_PASSWORD   粘贴 password.txt 的内容

之后用 Release 工作流发布的版本都会用这张证书签名。已经装着本地签名版本的 Mac，
更新到第一个用证书签名的版本时还需要重新授权一次，以后就不用了。
私钥只放在这个文件夹和 GitHub Secrets 里，不要提交进仓库，也请备份好这个文件夹。
INFO
