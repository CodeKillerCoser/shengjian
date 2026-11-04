# 声笺

<img src="Brand/shengjian-logo-v1.png" alt="声笺" width="112">

让表达，自然成文。macOS 本地语音转写与 AI 改写工具，独立于任何输入法。

- Apple 设备端语音识别或 Whisper.cpp 本地模型。
- 热词、改写规则与录音测试在同一页调整。
- 可选在线 Chat Completions 服务改写；只发送文字，不发送原始录音。
- 全局录音快捷键、后台波形、可选复制与自动填写。
- 本地音频及处理历史，支持重试和模型/耗时/用量记录。
- 音频输入设备启动检测与 Core Audio 变更订阅，防止双开。

## 构建

仅支持 Apple Silicon（M 系列芯片），要求 macOS 14+、Xcode Command Line Tools 和已有固定自签名证书的私钥。

```sh
./build.sh          # 默认 Release，仅 arm64
./build.sh Debug    # 本地调试
```

产物：`build/声笺.app`。脚本从源文件、`App/Info.plist` 和品牌资源创建全新 App，不依赖已有二进制。

可选环境变量：`APP_VERSION=1.0.0`、`BUILD_NUMBER=1`、`BUILD_DIR=/absolute/path`。
固定证书配置仅保存在本机 `~/.config/shengjian/signing`，私钥保存在系统钥匙串。可用 `SHENGJIAN_SIGNING_DIR` 指定配置目录，不允许 ad-hoc 签名或每次重建证书。

```sh
python3 -m unittest discover -s Tests -p 'test_*.py' -v
python3 Scripts/run_checks.py
python3 Tests/SigningChecks.py # 构建后执行
```

隔离检查使用模拟识别程序和本机 HTTP 测试服务，不读取用户录音、API Key 或系统授权。

### 首次授权回归

建议在独立 macOS 测试账户中验证，避免重置日常账户的权限：

1. 首次打开设置，麦克风和语音识别显示“未申请”。点击“申请授权”应先出现系统授权弹窗，不应直接进入空的系统权限列表；等待期间按钮不可重复点击。
2. 允许后状态变为“已授权”；拒绝后变为“已拒绝”，再次点击才打开对应系统权限页。下方“系统听写”是独立的键盘设置入口。
3. 保持辅助功能未授权，打开辅助功能引导，拖动系统设置窗口。引导卡片应随窗口移动；系统设置切页重建窗口后应能重新跟随，无需先授予辅助功能或录屏权限。
4. 最小化系统设置或切换到无关 App 时卡片应隐藏，恢复系统设置后重新出现；授权完成或退出系统设置后卡片应关闭。

`python3 Scripts/run_checks.py` 包含权限状态流转、重复请求、系统设置窗口替换和卡片坐标回归。系统授权弹窗与实际拖动跟随仍需上述人工验收。

## GitHub Actions

`.github/workflows/macos.yml` 包含两个独立节点：

1. **build**：main 推送或手动运行时，在 GitHub 托管 macOS ARM64 runner 执行检查、Release arm64 构建、验证签名，上传 ZIP、SHA256SUMS 与构建清单。
2. **release**：仅手动运行并勾选 `publish_release` 时运行，使用 build 的同一签名产物创建版本标签和 GitHub Release。

在 Actions → macOS Build and Release → Run workflow 中：

- 不勾选发布：仅构建，版本号可留空。
- 勾选发布：必须填写 `X.Y.Z`（允许 `vX.Y.Z`），例如 `1.0.0`；仅允许 main 分支发布。
- 重复版本会失败，不覆盖旧标签或旧 Release。

GitHub 的输入表单不支持“根据勾选动态必填”，因此版本约束由 build 的第一步强制校验。

### 签名托管

固定签名身份通过 GitHub Actions Secrets 托管：`SIGNING_CERTIFICATE_P12`、`SIGNING_CERTIFICATE_PASSWORD`、`SHENGJIAN_EXPECTED_SIGNING_IDENTITY`。
证书文件、私钥及密码不进入代码或 Git 历史。CI 导入临时钥匙串，结束后删除。
本机配置位于 `~/.config/shengjian/signing`，私钥保存在系统钥匙串。
更新 Secrets：`python3 Scripts/configure_signing_secrets.py CodeKillerCoser/shengjian`。

自签名产物没有 Apple 公证，首次安装可能需要用户在系统设置中允许打开。

## 应用身份与升级

Bundle ID：**`com.shengjian.app`**，可执行文件名 `Shengjian`。

此前本机原型使用 `local.rimevoice.desktop`，切换到正式 Bundle ID 需重新授权一次麦克风、语音识别和辅助功能。后续保持 Bundle ID、签名证书和安装位置一致。

现阶段保留旧原型的 `Application Support/RimeVoice` 数据目录与钥匙串服务名以继续读取原有配置、音频和历史；它们是兼容标识，不是产品名称。发布包不包含这些用户数据。
