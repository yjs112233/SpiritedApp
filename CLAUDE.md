# CLAUDE.md

本文件为 Claude Code (claude.ai/code) 在本仓库中工作时提供指引。

## 项目概述

`spirited_app` 是 **QianClouds 多云数据管理 App** 的 Flutter 客户端（Android / iOS），由微信小程序端（下文称 MP）移植而来。功能：绑定多家网盘（阿里云盘、百度、夸克、115、OneDrive、Google Drive、WebDAV、FTP/SFTP 等），在网盘之间做文件传输与定时同步，另有账户、订单、礼包等页面。

代码注释和 UI 文案均为中文，新增代码保持一致。

## 常用命令

```bash
flutter pub get                       # 安装依赖
flutter analyze                       # 静态检查（flutter_lints，已排除 android/ ios/ build/）
flutter test                          # 运行全部测试
flutter test test/widget_test.dart    # 运行单个测试文件
flutter test --plain-name '边界值'     # 按名称运行单个用例
flutter run                           # 在已连接的设备/模拟器上运行
flutter build apk                     # 构建 Android 包
```

## 架构

所有 Dart 代码在 `lib/` 下，分层如下：

- `config.dart` — 网关 `baseUrl`、AES 密钥/IV、版本号。
- `core/` — 基础设施
  - `http_client.dart`：`ApiClient` 单例（dio 封装），同文件内还有全局 `Toast`、`LoadingManager`。
  - `crypto_util.dart`：MD5 签名、防重放盐值、AES-128-CBC 响应解密。
  - `store.dart`：`Store`，SharedPreferences 的同步式静态封装（token、用户信息、网盘/任务/文件列表缓存）。必须先 `await Store.init()`（在 `main.dart` 的 `AppBootstrap` 中完成）。
  - `app_state.dart`：`AppState`（`ChangeNotifier`，由 provider 提供），管理登录态和用户信息。
  - `events.dart`：`UiEvents`，基于 `ValueNotifier` 的版本号广播。
- `api/` — 按领域划分的静态方法类（`DriveApi`、`TransferApi`、`UserApi`、`OrderApi`），全部通过 `ApiClient.instance` 发请求。
- `ui/` — 按功能分目录的页面；`ui/shell.dart` 是应用壳。
- `widgets/`、`utils/` — 公共组件与纯函数工具（`Formatters`）。

### 需要跨文件才能理解的要点

**与 MP / Web 端的对应关系。** 几乎每个文件头部都注明了对应的 MP 源文件（如 `utils/request.js`、`utils/store.js`）。请求签名、加解密、本地存储键名都要求与 MP/Web 端**完全一致**，修改这些逻辑时不要“顺手优化”，否则会与网关或其他端不兼容。

**请求协议（`http_client.dart` + `crypto_util.dart`）。**
- 请求头：`X-IDE`（GET 为 `md5(url)`；POST 为按插入顺序拼接所有参数值后取 MD5，因此参数 Map 的顺序有意义）、`X-APPL`（防重放盐值）、`Authorization`（token）、`device: mobile`。
- 响应为 `ReturnT {code, data, message}`，封装成 `ApiResult`：`200~399` 成功，`data` 是 AES 加密串，由 `ApiClient` 自动解密回填；`100` 为幂等拦截；`400/500` 弹 toast 并抛 `ApiException`；`401` 清 token 并跳转登录页。
- dio 的 `validateStatus` 全放行，HTTP 状态码由 `_doRequest` 自行判定。
- Toast/Loading/401 跳转不依赖页面 `BuildContext`，统一走 `ApiClient.navigatorKey`（挂在 `MaterialApp` 上）。

**导航与刷新。**
- `ShellPage` 用底部 4 个 Tab（云存储 / 传输 / 同步 / 我的）+ `IndexedStack` 保活页面；其余页面是 `main.dart` 中注册的命名路由（`/login`、`/cloud/add`、`/transfer/create` 等），新增页面需在那里注册。
- 因为 `IndexedStack` 下的页面没有 MP 的 `onShow`，跨页面刷新靠 `UiEvents`：授权/删除/创建后调用 `UiEvents.bumpDrives()` / `bumpTasks()`，列表页监听版本号后强制重新拉取；切换 Tab 用 `UiEvents.switchTab(i)`。

**数据形态。** 接口数据不建模型类，直接以 `Map<String, dynamic>` / `List<dynamic>` 流转，并用 `Store` 缓存列表以便先展示缓存再刷新。

## 测试

`test/widget_test.dart` 只测纯工具函数。App 启动依赖 `Store.init()` 等平台通道，不要直接 `pumpWidget` 整个 App；新增测试优先覆盖 `utils/`、`core/crypto_util.dart` 这类无平台依赖的逻辑。
