# Wordie

基于 [lyming99/english](https://github.com/lyming99/english)改编的 Flutter 英语单词学习应用。重写了学习调度逻辑、词书管理、启动流程、UI 界面，并新增了词典联网查询等模块。

## 功能

- **19 本系统词书**：小学英语 → MBA 词汇，覆盖主流国内外考试
- **自定义词书**：手动输入或 TXT 批量导入，支持创建、编辑、删除
- **学习模式**：每日新词计划 + 仅今日所学复习，可配每日数量、词序（正序/倒序/乱序）
- **AI 串记**：支持自定义 OpenAI Responses 站点、模型与 Key，流式生成复习文章
- **账号备份**：一键加密导出/恢复词库、进度、学习时长、偏好和 AI 配置
- **联网词典**：搜索界面输入任意英文单词，自动从有道词典抓取释义、音标、例句，并加入生词本
- **书内搜索**：在自定义词书中搜索某单词是否存在，未命中可一键跳转探索页添加
- **每日一词**：首页每日自动推送一个新词
- **学习统计**：打卡天数、学习时长、进度追踪
- **日历提醒**：通过系统日历添加复习提醒（Android ContentResolver / iOS EKEventStore）
- **深色模式**：全界面深色/浅色适配
- **启动动画**：品牌 splash + 随机英文背景图

## 2.0.0

- Android 包名调整为 `com.wordie.english15.coexist`，可与 1.5.x 并存安装
- 新增账号状态加密备份与跨设备恢复
- 新增 OpenAI Responses 流式 AI 串记，支持自定义站点和模型
- 修复自定义词书删除状态不回写、复习范围错误和 AI 请求悬挂问题

## 环境

| 工具 | 版本 |
|------|------|
| Flutter | 3.7.12 (FVM) |
| Dart | ≥ 2.16.1, < 3.0.0 |
| Android AGP | 4.1.0 |
| Gradle | 6.7 |
| Kotlin | 1.6.10 |

## 构建

```bash
# 安装依赖
fvm flutter pub get

# 生成 Floor 数据库代码
fvm flutter packages pub run build_runner build

# 调试运行
fvm flutter run

# 打包 APK（release 签名需先配置 android/app/build.gradle）
fvm flutter build apk --release
```

## 项目结构

```
lib/
├── controller/   # GetX 控制器（业务逻辑 + 状态）
├── view/         # UI 页面
├── service/      # 服务层（词库加载、学习调度）
├── dao/          # Floor 数据库访问层
├── entity/       # 数据模型（PO / VO）
├── dicts/        # 词典解析与内置词库解密
├── util/         # 词典联网抓取等工具
├── widget/       # 可复用组件
└── route/        # 路由表
```

## 技术栈

- **状态管理**：[GetX](https://pub.dev/packages/get)（路由、依赖注入、响应式）
- **本地数据库**：[Floor](https://pub.dev/packages/floor) + sqflite（学习记录持久化）
- **KV 存储**：[GetStorage](https://pub.dev/packages/get_storage)（缓存、偏好设置）
- **网络**：[Dio](https://pub.dev/packages/dio)（有道词典 HTML/JSON API 抓取）
- **原生桥接**：MethodChannel（日历事件、系统文件选择器）
- **加密**：encrypt + cryptography（内置词库资产解密、账号备份加密）
- **AI 协议**：OpenAI Responses（SSE 流式输出）

## 许可

个人学习项目，请勿用于商业用途。
