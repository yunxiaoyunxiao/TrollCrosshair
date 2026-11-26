# FloatImage 1.0 — TrollStore 开发工程

这是 FloatImage 的 iPadOS 原型工程，并附带 GitHub Actions 云端构建流程。

## 当前原型功能
- 从系统照片选择一张图片（PHPicker）
- 将图片保存到 App 的 Application Support，重新打开时载入
- X / Y / 宽度 / 高度 / 透明度五项参数
- 参数自动保存、实时刷新
- 五项参数一键重置
- 悬浮开关
- 当前 App 场景内的高层级 UIWindow 实验

## 重要：当前尚未实现的系统级能力
当前 `FloatingController` 使用普通应用的 `UIWindow`。它只是在当前 App 场景内做窗口层级实验，**不等于**可以覆盖 Safari、微信或游戏，也不等于系统级触摸穿透。以下能力尚未实现并且必须在目标 iPadOS 17.0 + TrollStore 设备上研究和实测：
- 跨 App 持续显示 / SpringBoard 级窗口管理
- 覆盖区域触摸事件完整穿透到底层 App
- App 退后台后持续运行
- 快捷指令控制
- 录屏排除、长按触发模式

不能将 `userInteractionEnabled = NO` 当作跨进程触摸穿透已经完成。

## GitHub 新账号快速部署
1. 登录新的 GitHub 账号，创建一个名为 `FloatImage` 的仓库，建议设为 Private。
2. 将本工程 ZIP 解压，把其中**所有文件和隐藏目录**上传到仓库根目录。特别确认 `.github/workflows/build.yml` 已上传。
3. 默认分支使用 `main`。打开仓库的 **Actions** 页面，选择 **Build FloatImage IPA**。
4. 点击 **Run workflow**。也可以在向 `main` 推送提交时自动构建。
5. 构建成功后，在该次运行页面的 **Artifacts** 下载 `FloatImage-TrollStore-IPA`。
6. 解压 Artifact，取出 `FloatImage-TrollStore.ipa`，传到 iPad，再用 TrollStore 尝试安装。

如果 Actions 没有出现工作流，先检查 `.github/workflows/build.yml` 是否在默认分支的正确路径下，以及仓库 Actions 是否启用。手动运行 `workflow_dispatch` 要求工作流文件已经存在于默认分支。

## 构建说明
- GitHub Actions 使用 GitHub 托管的 `macos-14` runner 和其预装的 Xcode。
- 当前 workflow 生成未签名 IPA，**没有在真实设备上验证 TrollStore 安装兼容性**；如果安装失败，需要按设备 TrollStore 版本调整打包/签名流程。
- 本工程目前没有进行真实 Xcode 编译验证，首次运行 Actions 的结果才是编译验证依据。
- 不需要把 GitHub 密码、Personal Access Token 或 Apple 账户密码提供给任何人。

## 本地 Xcode
打开 `FloatImage.xcodeproj`，选择 `FloatImage` scheme 和 iPadOS 17.0 或更新目标设备构建。
