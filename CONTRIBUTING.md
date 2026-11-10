# Contributing / 贡献

This is a personally maintained, early-stage open-source library. Keep changes
small and purposeful. Discuss a new command, dependency or supported platform
before adding it. Submit a focused issue or pull request with the intended
behaviour, a specification/reference link and synthetic reproduction data.
No contributor agreement is required; contributions use Apache-2.0.

Install the native dependencies listed in README.md. Before a pull request:

```sh
moon fmt
moon check --target native --deny-warn
moon test --target native --deny-warn
moon build --target native --deny-warn
moon run examples/offline --target native
python3 tools/interop.py _build/native/debug/build/examples/loopback/loopback.exe
moon info
```

Update both READMEs when user-visible behaviour changes. Test the changed
boundary, not an expensive unrelated matrix. Do not commit generated build
outputs, local paths, packet captures, credentials or internal work logs. Use
English commit messages and preserve unrelated work. Security reports belong
in a private channel; see SECURITY.md.

本项目处于早期阶段，由个人维护。改动应小而明确；新增命令、依赖或支持平台前先讨论。
Issue 或 PR 请给出目标行为、规范/参考链接和合成复现数据。无需额外贡献者协议，
贡献采用 Apache-2.0。

提交前运行上面的格式化、检查、测试、示例和接口生成命令。可见行为变化时同步更新中英 README。
验证改动涉及的边界，不堆叠无关昂贵测试。不要提交构建产物、本机路径、抓包、凭据或内部工作记录。
提交信息使用英文，保留无关改动。安全问题走私密渠道，见 SECURITY.md。

## Releases / 发布

Mooncakes publication is a manual maintainer action after reviewing the release
contents and validation results. CI never publishes packages. Keep existing
release versions and tags intact; prepare a new version for any later release.
Do not add an automatic publish step to a workflow or validation script.

Mooncakes 发布由维护者审阅内容与验证结果后手动执行，CI 不发布包。
保留既有发布版本与标签，后续发布准备新版本。不要在工作流或验证脚本中加入自动发布步骤。
