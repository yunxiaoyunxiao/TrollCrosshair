# TrollCrosshair Beta 1

TrollStore / iPadOS 17.0 全局图片悬浮实验项目。

## 当前版本

- 版本：0.1.0（Beta 1）
- 最低部署版本：iOS / iPadOS 17.0
- Bundle ID：`com.trollcrosshair.app`
- 目标设备：iPhone、iPad（当前优先验证 iPad）

## 已实现的界面与设置

- 从系统照片选择一张图片，并保存到应用容器。
- 调整图片中心点 X / Y、宽度、高度和透明度。
- 设置值保存在本地，重启应用后恢复。
- 一个开启 / 关闭悬浮按钮。
- 设置页提供实际参数预览。
- X、Y、宽度、高度、透明度可一键重置。

## 全局悬浮实现

使用 TrollStore 可签名的私有 FrontBoard Scene 方式创建独立悬浮场景，并使用自定义 UIWindow 的 `_ignoresHitTest` 让图片层不接收触摸事件。

这部分依赖 iOS 私有 API 和签名 entitlement。云端编译成功不等于已经在真实设备上验证成功；首次安装后必须测试跨 App 显示、触摸穿透、前后台切换和屏幕旋转。

## 获取 Beta 1

1. 打开 GitHub 仓库的 Actions 页面。
2. 选择最新成功的 **iOS Build** 工作流运行记录。
3. 在 Artifacts 中下载 `TrollCrosshair-IPA`。
4. 解压下载的 ZIP，得到 `TrollCrosshair.ipa`。
5. 使用 TrollStore 安装 IPA。

## 首轮设备验收

- [ ] TrollStore 安装成功并能正常启动。
- [ ] 能从照片选择图片，退出应用再打开后图片仍存在。
- [ ] X / Y 以图片中心为定位基准，宽高和透明度调节正确。
- [ ] 开启后离开 TrollCrosshair，图片仍显示在其他 App 上方。
- [ ] 点击图片所在区域时，底层 App 仍能正常接收触摸。
- [ ] 关闭后图片立即消失。
- [ ] 切换横竖屏后位置和尺寸仍正常。
- [ ] 从后台返回后悬浮状态符合预期。

## 已知限制

- 当前为首个 Beta 候选构建，尚未完成真实 iPad 实机验收。
- 锁屏显示、拖动图片、图片编辑和复杂动画不属于本 Beta 范围。
