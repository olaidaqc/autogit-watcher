# AutoGit Watcher

Windows (PowerShell 5.1) background watcher:

- `C:\Users\11918\Desktop\claude\projects` 下新建项目文件夹：自动 `git init` + 首次 `commit`
-（可选）自动创建 GitHub 仓库 + `push`
- 之后项目内文件变更：自动 `commit` + `push`（带防抖）
- `projects` 第一层项目文件夹改名：自动把 GitHub 仓库改名，并更新本地 `origin`

文档在 `details\`。

