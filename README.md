# Wordie

一个帮你科学背单词的 Flutter 应用，内置词库 + 自定义生词本 + 智能复习提醒。

*基于 [lyming99/english](https://github.com/lyming99/english) 改编，重写了学习调度、词书管理、UI 和启动流程等模块。*

## 功能

- **内置 19 本系统词库**：从小学到 GRE，覆盖主流考试
- **自定义生词本**：搜索单词直接收藏，或者用 TXT 批量导入
- **自动复习调度**：根据遗忘曲线自动安排复习时间，到期弹出复习
- **学习统计**：打卡天数、学习时长、完成进度一目了然
- **每日一词**：每天自动推送
- **深色模式** / **日历提醒** / **词库导入导出**

## 搭建 & 运行

### 环境

| 工具 | 版本 |
|------|------|
| Flutter | 3.7.12 (FVM) |
| Dart | ≥ 2.16.1, < 3.0.0 |
| Android AGP | 4.1.0 |
| Kotlin | 1.6.10 |

### 构建

```bash
# 安装依赖
fvm flutter pub get

# 生成 Floor 数据库代码
fvm flutter packages pub run build_runner build

# 调试运行
fvm flutter run

# 打包 APK
fvm flutter build apk --release
```

### 首次启动

应用会自动从 `assets/dict.db1` 释放内置词库到设备存储，无需额外配置。

## 项目结构

```
lib/
├── controller/   # GetX 控制器（业务逻辑 + 状态）
├── view/         # UI 页面
├── service/      # 服务层（词库加载、学习调度）
├── dao/          # Floor 数据库访问层
├── entity/       # 数据模型（PO / VO）
├── dicts/        # 词典解析与读取
├── util/         # 工具函数
├── widget/       # 可复用组件
└── route/        # 路由表
```

## 依赖

基于 [GetX](https://pub.dev/packages/get) 状态管理，[Floor](https://pub.dev/packages/floor) + [sqflite](https://pub.dev/packages/sqflite) 本地数据库，零后端。



## 许可

个人学习项目，请勿用于商业用途。
